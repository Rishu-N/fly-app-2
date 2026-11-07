import Foundation

/// An atomic, undoable batch of edits. Every multi-task operation (assistant proposals,
/// "shift rest of day", bulk delete) goes through one of these so a single Undo reverts it.
public struct ChangeSet: Equatable, Sendable {
    public var label: String
    public var upserts: [PlanTask]
    public var deletions: [UUID]

    public init(label: String, upserts: [PlanTask] = [], deletions: [UUID] = []) {
        self.label = label
        self.upserts = upserts
        self.deletions = deletions
    }

    public var isEmpty: Bool { upserts.isEmpty && deletions.isEmpty }
}

public struct UndoEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let date: Date
    let inverse: ChangeSet

    init(label: String, date: Date, inverse: ChangeSet) {
        self.id = UUID()
        self.label = label
        self.date = date
        self.inverse = inverse
    }
}

/// What changed, so app-side services (notifications, Live Activity, widgets) can react
/// proportionally instead of resyncing everything.
public struct StoreChange: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Plan edits (create/update/delete).
        case schedule
        /// A timer action on a task (start/pause/resume/complete/cancel/extend).
        case timer(TaskAction)
        /// Bulk load/bootstrap.
        case reload
    }

    public var kind: Kind
    public var taskIDs: [UUID]
}
