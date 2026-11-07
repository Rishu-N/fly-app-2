import Foundation

/// Storage backend for the task store. Implementations must be safe to call from any task.
public protocol PlannerPersistence: Sendable {
    func availableMonths() async throws -> [MonthKey]
    func loadTasks(month: MonthKey) async throws -> [PlanTask]
    func saveTasks(_ tasks: [PlanTask], month: MonthKey) async throws
    func loadSeries() async throws -> [TaskSeries]
    func saveSeries(_ series: [TaskSeries]) async throws
}

/// Month-partitioned JSON files. A change only rewrites the touched month (typically a few
/// hundred tasks ≈ tens of KB), encoding happens off the main thread inside this actor, and
/// every write is atomic so a crash can never leave a half-written file.
///
///     <root>/tasks-2026-11.json
///     <root>/series.json
public actor JSONFilePersistence: PlannerPersistence {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.root = directory
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        self.encoder = e
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        self.decoder = d
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func url(for month: MonthKey) -> URL {
        root.appendingPathComponent("tasks-\(month).json")
    }

    public func availableMonths() async throws -> [MonthKey] {
        try ensureDirectory()
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        return names.compactMap { name -> MonthKey? in
            guard name.hasPrefix("tasks-"), name.hasSuffix(".json") else { return nil }
            return MonthKey(string: String(name.dropFirst(6).dropLast(5)))
        }.sorted()
    }

    public func loadTasks(month: MonthKey) async throws -> [PlanTask] {
        let url = url(for: month)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode(TaskFile.self, from: data).tasks
    }

    public func saveTasks(_ tasks: [PlanTask], month: MonthKey) async throws {
        try ensureDirectory()
        let url = url(for: month)
        if tasks.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let data = try encoder.encode(TaskFile(version: 1, tasks: tasks.sorted { $0.start < $1.start }))
        try data.write(to: url, options: [.atomic])
    }

    public func loadSeries() async throws -> [TaskSeries] {
        let url = root.appendingPathComponent("series.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode(SeriesFile.self, from: Data(contentsOf: url)).series
    }

    public func saveSeries(_ series: [TaskSeries]) async throws {
        try ensureDirectory()
        let data = try encoder.encode(SeriesFile(version: 1, series: series))
        try data.write(to: root.appendingPathComponent("series.json"), options: [.atomic])
    }

    private struct TaskFile: Codable {
        var version: Int
        var tasks: [PlanTask]
    }

    private struct SeriesFile: Codable {
        var version: Int
        var series: [TaskSeries]
    }
}

/// In-memory backend for previews and tests.
public actor InMemoryPersistence: PlannerPersistence {
    private var months: [MonthKey: [PlanTask]] = [:]
    private var series: [TaskSeries] = []
    public private(set) var saveCount = 0

    public init(tasks: [PlanTask] = [], calendar: Calendar = .current) {
        for task in tasks {
            months[MonthKey(task.start, calendar: calendar), default: []].append(task)
        }
    }

    public func availableMonths() async throws -> [MonthKey] { months.keys.sorted() }
    public func loadTasks(month: MonthKey) async throws -> [PlanTask] { months[month] ?? [] }
    public func saveTasks(_ tasks: [PlanTask], month: MonthKey) async throws {
        months[month] = tasks
        saveCount += 1
    }
    public func loadSeries() async throws -> [TaskSeries] { series }
    public func saveSeries(_ series: [TaskSeries]) async throws { self.series = series }
}
