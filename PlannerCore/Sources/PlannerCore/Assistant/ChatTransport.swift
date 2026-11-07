import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AssistantError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidBaseURL
    case unauthorized(String)
    case modelNotFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded(String)
    case server(status: Int, message: String)
    case network(String)
    case badResponse(String)
    case cancelled

    public var userMessage: String {
        switch self {
        case .missingAPIKey: "Add your OpenAI API key in Settings › Assistant to start."
        case .invalidBaseURL: "The server address in Settings › Assistant isn't a valid URL."
        case .unauthorized: "The API key was rejected. Check it in Settings › Assistant."
        case .modelNotFound(let m): "The model “\(m)” isn't available on this account."
        case .rateLimited: "The service is busy right now. Try again in a moment."
        case .quotaExceeded: "Your OpenAI account is out of credit or over quota."
        case .server(let status, let message): "Server error \(status). \(message)"
        case .network: "You appear to be offline. Your message is kept — tap Retry."
        case .badResponse: "The reply couldn't be read. Tap Retry."
        case .cancelled: "Stopped."
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .network, .badResponse: true
        case .server(let status, _): status >= 500
        default: false
        }
    }
}

public struct AssistantEndpoint: Sendable, Equatable {
    public var baseURL: URL
    public var apiKey: String
    public var isOpenAI: Bool { baseURL.host?.hasSuffix("openai.com") ?? false }

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    public init(baseURLString: String, apiKey: String) throws {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            throw AssistantError.invalidBaseURL
        }
        self.init(baseURL: url, apiKey: apiKey)
    }
}

/// Abstraction over the network so the agent loop is testable with a scripted fake.
public protocol ChatTransport: Sendable {
    func stream(_ request: ChatRequest, endpoint: AssistantEndpoint) -> AsyncThrowingStream<ChatStreamChunk, Error>
    func listModels(endpoint: AssistantEndpoint) async throws -> [String]
}

/// URLSession-backed OpenAI client. One shared ephemeral session (no cookies/cache on disk),
/// HTTP/2 multiplexed, 60 s request timeout.
public final class OpenAIHTTPTransport: ChatTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 180
            #if canImport(Darwin)
            config.waitsForConnectivity = false
            #endif
            config.httpAdditionalHeaders = ["Accept": "text/event-stream"]
            self.session = URLSession(configuration: config)
        }
    }

    func makeRequest(path: String, endpoint: AssistantEndpoint, body: Data?) -> URLRequest {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !endpoint.apiKey.isEmpty {
            request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    public func listModels(endpoint: AssistantEndpoint) async throws -> [String] {
        let request = makeRequest(path: "models", endpoint: endpoint, body: nil)
        let (data, response) = try await data(for: request)
        try Self.check(response: response, data: data, model: "")
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        return list.data.map(\.id).sorted()
    }

    public func stream(_ request: ChatRequest, endpoint: AssistantEndpoint) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try JSONEncoder().encode(request)
                    let urlRequest = makeRequest(path: "chat/completions", endpoint: endpoint, body: body)
                    try await self.run(urlRequest, model: request.model, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AssistantError.cancelled)
                } catch let error as AssistantError {
                    continuation.finish(throwing: error)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: AssistantError.cancelled)
                } catch {
                    continuation.finish(throwing: AssistantError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: URLRequest, model: String, continuation: AsyncThrowingStream<ChatStreamChunk, Error>.Continuation) async throws {
        let decoder = JSONDecoder()
        #if canImport(Darwin)
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 64_000 { break }
            }
            try Self.check(response: response, data: data, model: model)
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            switch SSELine.parse(line) {
            case .data(let payload):
                guard let data = payload.data(using: .utf8) else { continue }
                if let chunk = try? decoder.decode(ChatStreamChunk.self, from: data) {
                    continuation.yield(chunk)
                } else if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data), let body = envelope.error {
                    throw AssistantError.server(status: 200, message: body.message ?? "Unknown error")
                }
            case .done:
                return
            case .ignore:
                continue
            }
        }
        #else
        // Linux / non-Darwin: no incremental byte streams in FoundationNetworking — buffer the whole
        // SSE body and replay it. (Only used by tooling; the app runs on Darwin.)
        let (data, response) = try await data(for: request)
        try Self.check(response: response, data: data, model: model)
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            switch SSELine.parse(String(line)) {
            case .data(let payload):
                if let d = payload.data(using: .utf8), let chunk = try? decoder.decode(ChatStreamChunk.self, from: d) {
                    continuation.yield(chunk)
                }
            case .done: return
            case .ignore: continue
            }
        }
        #endif
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(Darwin)
        return try await session.data(for: request)
        #else
        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let response else {
                    continuation.resume(throwing: AssistantError.badResponse("No response"))
                    return
                }
                continuation.resume(returning: (data ?? Data(), response))
            }.resume()
        }
        #endif
    }

    static func check(response: URLResponse, data: Data, model: String) throws {
        guard let http = response as? HTTPURLResponse else { throw AssistantError.badResponse("No HTTP response") }
        guard !(200..<300).contains(http.statusCode) else { return }
        let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let message = envelope?.error?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        let code = envelope?.error?.code ?? ""
        switch http.statusCode {
        case 401, 403: throw AssistantError.unauthorized(message)
        case 404:
            let mentionsModel = code == "model_not_found" || message.lowercased().contains("model")
            if !model.isEmpty, mentionsModel { throw AssistantError.modelNotFound(model) }
            throw AssistantError.server(status: 404, message: "Not found — check the server address (it usually ends in /v1).")
        case 429:
            if code == "insufficient_quota" || message.lowercased().contains("quota") {
                throw AssistantError.quotaExceeded(message)
            }
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw AssistantError.rateLimited(retryAfter: retry)
        case 400 where code == "model_not_found" || message.lowercased().contains("model") && message.lowercased().contains("does not exist"):
            throw AssistantError.modelNotFound(model)
        default:
            throw AssistantError.server(status: http.statusCode, message: message)
        }
    }
}
