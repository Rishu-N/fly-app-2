import Foundation

/// Eight semantic categories. Each maps to one slot of the 8-colour category palette in the
/// app's design system (`paletteIndex`) and to an SF Symbol. Raw values are stable on disk and
/// are also the enum the assistant uses in tool calls.
public enum TaskCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case focus
    case meeting
    case admin
    case health
    case learning
    case personal
    case social
    case rest

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .focus: "Focus"
        case .meeting: "Meeting"
        case .admin: "Admin"
        case .health: "Health"
        case .learning: "Learning"
        case .personal: "Personal"
        case .social: "Social"
        case .rest: "Break"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .focus: "scope"
        case .meeting: "person.2.fill"
        case .admin: "tray.full.fill"
        case .health: "figure.run"
        case .learning: "book.fill"
        case .personal: "house.fill"
        case .social: "bubble.left.and.bubble.right.fill"
        case .rest: "cup.and.saucer.fill"
        }
    }

    public var paletteIndex: Int { TaskCategory.allCases.firstIndex(of: self) ?? 0 }

    /// Lenient mapping used by the quick-add parser and the assistant.
    public init?(loose raw: String) {
        let s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = TaskCategory(rawValue: s) { self = exact; return }
        switch s {
        case "work", "deep", "deep work", "deepwork", "code", "coding", "write", "writing": self = .focus
        case "call", "meet", "sync", "standup", "1:1", "interview": self = .meeting
        case "email", "emails", "errand", "errands", "chores", "admin work": self = .admin
        case "gym", "run", "workout", "exercise", "yoga", "walk", "fitness", "sport": self = .health
        case "study", "read", "reading", "course", "class", "learn": self = .learning
        case "home", "family", "life": self = .personal
        case "friends", "party", "dinner", "lunch", "date": self = .social
        case "break", "nap", "lunch break", "coffee", "relax", "pause": self = .rest
        default: return nil
        }
    }

    /// Best-effort guess from a task title (used when the user doesn't pick a category).
    public static func guess(fromTitle title: String) -> TaskCategory {
        let words = title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != ":" })
            .map(String.init)
        for word in words {
            if let match = TaskCategory(loose: word) { return match }
        }
        return .focus
    }
}
