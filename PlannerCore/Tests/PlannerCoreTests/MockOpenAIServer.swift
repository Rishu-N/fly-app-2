import Foundation
@testable import PlannerCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A tiny OpenAI-compatible HTTP/1.1 server on 127.0.0.1 (random free port) for end-to-end tests
/// of `OpenAIHTTPTransport`. Written with POSIX sockets because the swift Docker image has no
/// python3. Serves `GET /v1/models` and scripted responses for `POST /v1/chat/completions`
/// (SSE, optionally chunked so Darwin's incremental byte stream sees separate deliveries),
/// records every request, and closes each connection after one response.
final class MockOpenAIServer: @unchecked Sendable {
    struct Request: Sendable {
        var method: String
        var path: String
        /// Header names lowercased.
        var headers: [String: String]
        var body: Data
        var json: JSONValue? { JSONValue.parse(String(decoding: body, as: UTF8.self)) }
    }

    enum Response: Sendable {
        case json(status: Int, body: String, headers: [String: String] = [:])
        case text(status: Int, body: String)
        /// Raw SSE body. `chunked` sends each event as its own HTTP chunk (with a short pause).
        case sse(String, chunked: Bool = true)
    }

    let port: UInt16
    private let listenFD: Int32
    private let lock = NSLock()
    private var _requests: [Request] = []
    private var chatQueue: [Response] = []
    private var stopped = false
    var modelsResponse: Response = .json(status: 200, body: #"{"object":"list","data":[{"id":"gpt-6-luna","object":"model","created":1,"owned_by":"system"}]}"#)

    var baseURL: String { "http://127.0.0.1:\(port)/v1" }
    var requests: [Request] { lock.withLock { _requests } }
    var chatRequests: [Request] { requests.filter { $0.path.hasSuffix("/chat/completions") } }

    func enqueueChat(_ responses: Response...) { lock.withLock { chatQueue += responses } }

    init() throws {
        signal(SIGPIPE, SIG_IGN)
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 32) == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        port = UInt16(bigEndian: actual.sin_port)
        listenFD = fd
        Thread { [self] in acceptLoop() }.start()
    }

    func stop() {
        let alreadyStopped = lock.withLock { () -> Bool in
            defer { stopped = true }
            return stopped
        }
        guard !alreadyStopped else { return }
        // Wake the blocking accept() with a throwaway connection, then close the socket.
        if let poke = try? Self.connectLocal(port: port) { close(poke) }
        close(listenFD)
    }

    deinit { stop() }

    // MARK: Accept / handle

    private func acceptLoop() {
        while true {
            let client = accept(listenFD, nil, nil)
            if lock.withLock({ stopped }) {
                if client >= 0 { close(client) }
                return
            }
            guard client >= 0 else {
                if errno == EINTR { continue }
                return
            }
            #if canImport(Darwin)
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            #endif
            var timeout = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            Thread { [self] in handle(client) }.start()
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        var buffer = [UInt8]()
        var headerEnd: Int?
        while headerEnd == nil {
            guard let more = receive(fd) else { return }
            buffer += more
            headerEnd = Self.find([13, 10, 13, 10], in: buffer)
        }
        let head = String(decoding: buffer[..<headerEnd!], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["expect"]?.lowercased() == "100-continue" { send(fd, "HTTP/1.1 100 Continue\r\n\r\n") }
        var body = Array(buffer[(headerEnd! + 4)...])
        if let length = headers["content-length"].flatMap(Int.init) {
            while body.count < length {
                guard let more = receive(fd) else { break }
                body += more
            }
            body = Array(body.prefix(length))
        } else if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            while Self.find([48, 13, 10, 13, 10], in: body) == nil {  // "0\r\n\r\n"
                guard let more = receive(fd) else { break }
                body += more
            }
            body = Self.dechunk(body)
        }
        let request = Request(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: Data(body))
        let response: Response = lock.withLock {
            _requests.append(request)
            if request.method == "GET", request.path.hasSuffix("/v1/models") { return modelsResponse }
            if request.method == "POST", request.path.hasSuffix("/v1/chat/completions") {
                return chatQueue.isEmpty
                    ? .json(status: 500, body: #"{"error":{"message":"no scripted response","type":"server_error"}}"#)
                    : chatQueue.removeFirst()
            }
            return .text(status: 404, body: "404 page not found")
        }
        write(response, to: fd)
    }

    private func write(_ response: Response, to fd: Int32) {
        switch response {
        case .json(let status, let body, let extra):
            var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n"
            for (k, v) in extra { head += "\(k): \(v)\r\n" }
            send(fd, head + "\r\n" + body)
        case .text(let status, let body):
            send(fd, "HTTP/1.1 \(status) \(Self.reason(status))\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body)
        case .sse(let body, let chunked):
            guard chunked else {
                send(fd, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body)
                return
            }
            send(fd, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
            for event in Self.events(body) {
                send(fd, String(event.utf8.count, radix: 16) + "\r\n" + event + "\r\n")
                usleep(2_000)
            }
            send(fd, "0\r\n\r\n")
        }
    }

    // MARK: Socket helpers

    private func receive(_ fd: Int32) -> [UInt8]? {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let n = recv(fd, &chunk, chunk.count, 0)
        return n > 0 ? Array(chunk[0..<n]) : nil
    }

    private func send(_ fd: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            #if canImport(Glibc)
            let n = bytes[offset...].withUnsafeBufferPointer { Glibc.send(fd, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL)) }
            #else
            let n = bytes[offset...].withUnsafeBufferPointer { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            #endif
            guard n > 0 else { return }
            offset += n
        }
    }

    static func connectLocal(port: UInt16) throws -> Int32 {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0 else { close(fd); throw POSIXError(.ECONNREFUSED) }
        return fd
    }

    static func find(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) where haystack[i..<(i + needle.count)].elementsEqual(needle) { return i }
        return nil
    }

    static func dechunk(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while let lineEnd = find([13, 10], in: Array(bytes[i...])) {
            let size = Int(String(decoding: bytes[i..<(i + lineEnd)], as: UTF8.self), radix: 16) ?? 0
            i += lineEnd + 2
            if size == 0 || i + size > bytes.count { break }
            out += bytes[i..<(i + size)]
            i += size + 2
        }
        return out
    }

    /// Splits an SSE body after each blank line (LF or CRLF), keeping the separators.
    static func events(_ body: String) -> [String] {
        var events: [String] = []
        var current = ""
        for line in body.components(separatedBy: "\n") {
            current += line + "\n"
            if line.isEmpty || line == "\r" {
                events.append(current)
                current = ""
            }
        }
        let rest = String(current.dropLast())
        if !rest.isEmpty { events.append(rest) }
        return events.filter { !$0.isEmpty }
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Status"
        }
    }

    // MARK: SSE body builder

    /// `data: <payload>` events (+ `data: [DONE]`), with `lineEnding` "\n" or "\r\n".
    static func sse(_ payloads: [String], done: Bool = true, lineEnding: String = "\n", extraLines: [String] = []) -> String {
        var out = extraLines.map { $0 + lineEnding + lineEnding }.joined()
        for p in payloads { out += "data: \(p)\(lineEnding)\(lineEnding)" }
        if done { out += "data: [DONE]\(lineEnding)\(lineEnding)" }
        return out
    }
}
