import Foundation

/// A fill-in-the-blanks starter prompt. Placeholders look like `{must_dos}`; the UI renders one
/// field per placeholder (in order of appearance) pre-filled with `defaults`, then lets the user
/// edit the final text before sending.
public struct PromptTemplate: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var symbol: String
    public var subtitle: String
    public var body: String
    public var defaults: [String: String]
    public var hints: [String: String]

    public init(id: String, title: String, symbol: String, subtitle: String, body: String,
                defaults: [String: String] = [:], hints: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.body = body
        self.defaults = defaults
        self.hints = hints
    }

    /// Placeholder keys in order of first appearance.
    public var placeholders: [String] {
        var keys: [String] = []
        var current = ""
        var inside = false
        for ch in body {
            if ch == "{" { inside = true; current = ""; continue }
            if ch == "}", inside {
                inside = false
                if !current.isEmpty, !keys.contains(current) { keys.append(current) }
                continue
            }
            if inside { current.append(ch) }
        }
        return keys
    }

    public static func label(for key: String) -> String {
        let words = key.split(separator: "_").map(String.init)
        guard let first = words.first else { return key }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    /// Fills placeholders. Empty values collapse gracefully ("Must-dos: ." is avoided by
    /// substituting "none").
    public func render(_ values: [String: String]) -> String {
        var text = body
        for key in placeholders {
            let raw = (values[key] ?? defaults[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            text = text.replacingOccurrences(of: "{\(key)}", with: raw.isEmpty ? "none" : raw)
        }
        return text
    }

    public static let library: [PromptTemplate] = [
        PromptTemplate(
            id: "plan-day", title: "Plan my day", symbol: "sun.max", subtitle: "Build a minute-by-minute plan",
            body: "Plan {date} from {start_time} to {end_time}. Must-dos: {must_dos}. Nice-to-haves: {nice_to_haves}. Put my hardest work in my best focus time ({focus_time}), add {break_minutes}-min breaks between blocks, and keep tasks that are already scheduled.",
            defaults: ["date": "today", "start_time": "now", "end_time": "18:00", "focus_time": "the morning", "break_minutes": "10"],
            hints: ["must_dos": "Report, gym, call Sam", "nice_to_haves": "Inbox zero"]
        ),
        PromptTemplate(
            id: "running-late", title: "Running late", symbol: "clock.arrow.circlepath", subtitle: "Fix the rest of today",
            body: "I'm running {minutes_late} minutes late. Reschedule the rest of today from now. Don't move {keep_fixed}. If it won't all fit, shorten or drop the lowest-priority items and suggest moving them to {fallback_day}.",
            defaults: ["minutes_late": "15", "fallback_day": "tomorrow"],
            hints: ["keep_fixed": "meetings"]
        ),
        PromptTemplate(
            id: "quick-add", title: "Quick add", symbol: "plus.circle", subtitle: "Add tasks in plain words",
            body: "Add {tasks} on {date}. Use {duration} minutes if I didn't say, and remind me {lead_time} minutes before.",
            defaults: ["date": "today", "duration": "30", "lead_time": "5"],
            hints: ["tasks": "dentist at 3pm, groceries after work"]
        ),
        PromptTemplate(
            id: "break-down", title: "Break it down", symbol: "list.bullet.indent", subtitle: "Split a big task into blocks",
            body: "Break '{task}' into focused blocks of about {block_minutes} minutes with {break_minutes}-min breaks. Total time is about {total_time}. Schedule them {when} and remove or shorten the original block.",
            defaults: ["block_minutes": "25", "break_minutes": "5", "total_time": "2 hours", "when": "in my next free time today"],
            hints: ["task": "Write launch report"]
        ),
        PromptTemplate(
            id: "free-time", title: "Find free time", symbol: "calendar.badge.clock", subtitle: "Locate open slots",
            body: "Find {count} free slots of {duration} for {activity} between {range_start} and {range_end}, preferably {time_preference}. Show the options and ask me which one to add.",
            defaults: ["count": "3", "duration": "1 hour", "range_start": "today", "range_end": "end of this week", "time_preference": "in the afternoon"],
            hints: ["activity": "deep work"]
        ),
        PromptTemplate(
            id: "move-tasks", title: "Move tasks", symbol: "arrow.left.arrow.right", subtitle: "Batch move by keyword or category",
            body: "Move all {keyword_or_category} tasks from {from_day} to {to_day}. Keep the same times if they're free; otherwise use the nearest free slot.",
            defaults: ["from_day": "today", "to_day": "tomorrow"],
            hints: ["keyword_or_category": "admin"]
        ),
        PromptTemplate(
            id: "clear-block", title: "Clear a block", symbol: "eraser", subtitle: "Free up part of a day",
            body: "Clear {time_range} on {date}. Move everything there to the next free slots {move_window}, and keep {exceptions} where they are.",
            defaults: ["date": "today", "move_window": "later today"],
            hints: ["time_range": "14:00–16:00", "exceptions": "meetings"]
        ),
        PromptTemplate(
            id: "daily-review", title: "Daily review", symbol: "checkmark.seal", subtitle: "Reflect and roll over",
            body: "Review today: what I completed, what overran and what I skipped. Give me 3 short observations, then move unfinished tasks to {target_day} at sensible times.",
            defaults: ["target_day": "tomorrow"]
        ),
        PromptTemplate(
            id: "weekly-plan", title: "Weekly planning", symbol: "calendar", subtitle: "Plan the week around goals",
            body: "Plan the week of {week_start}. Goals: {goals}. Fixed commitments: {fixed_commitments}. Work hours {work_start}–{work_end}, at most {max_focus_hours} hours of deep work per day, and keep {free_day} free.",
            defaults: ["week_start": "next Monday", "work_start": "09:00", "work_end": "17:30", "max_focus_hours": "4", "free_day": "Sunday"],
            hints: ["goals": "ship v1, run 3x", "fixed_commitments": "standup 9:30 daily"]
        ),
        PromptTemplate(
            id: "routine", title: "Build a routine", symbol: "repeat", subtitle: "Create a recurring routine",
            body: "Create a recurring '{routine_name}' routine every {days} starting at {start_time}: {steps_with_durations}. Start on {start_date}.",
            defaults: ["days": "weekday", "start_time": "07:00", "start_date": "tomorrow"],
            hints: ["routine_name": "Morning", "steps_with_durations": "stretch 10m, journal 10m, plan day 5m"]
        ),
        PromptTemplate(
            id: "sprints", title: "Focus sprints", symbol: "timer", subtitle: "Pomodoro-style blocks",
            body: "Schedule {cycles} focus sprints for {project}: {work_minutes} min work + {break_minutes} min break, starting {start_time} on {date}, with a {long_break}-min break after every 4.",
            defaults: ["cycles": "4", "work_minutes": "25", "break_minutes": "5", "start_time": "now", "date": "today", "long_break": "20"],
            hints: ["project": "thesis chapter 2"]
        ),
        PromptTemplate(
            id: "prep-event", title: "Prep for an event", symbol: "briefcase", subtitle: "Add prep and travel before something",
            body: "I have {event} at {event_time} on {date}. Add prep blocks before it ({prep_items}), {travel_minutes} min of travel, and a {buffer_minutes}-min buffer.",
            defaults: ["date": "today", "travel_minutes": "20", "buffer_minutes": "10"],
            hints: ["event": "client pitch", "event_time": "16:00", "prep_items": "rehearse 30m, print deck 10m"]
        ),
    ]
}
