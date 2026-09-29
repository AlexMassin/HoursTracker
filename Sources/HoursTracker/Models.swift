import Foundation

struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Index into HT.palette. Optional so data.json files written by v1 (without it) still decode.
    var colorIndex: Int? = nil
}

struct WorkSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var projectID: UUID
    var start: Date
    var end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct RunningSession: Codable, Hashable {
    var projectID: UUID
    var start: Date
}

struct AppData: Codable {
    var projects: [Project] = []
    var sessions: [WorkSession] = []
    var running: RunningSession? = nil
}

struct Totals {
    var today: TimeInterval
    var week: TimeInterval
    var all: TimeInterval
}

enum Fmt {
    /// "1:24:07" (always shows hours so width is stable in in-app UI)
    static func hms(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    /// Menu bar: always zero-padded "00:00:00" (fixed character count) so the
    /// status-item title cannot change width as hours/minutes/seconds tick.
    static func hmsPadded(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    /// "142:10"
    static func hm(_ t: TimeInterval) -> String {
        let m = max(0, Int(t) / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// "1 hour, 24 minutes" for VoiceOver
    static func spoken(_ t: TimeInterval) -> String {
        let secs = max(0, Int(t))
        if secs < 60 { return "less than a minute" }
        return Duration.seconds(secs).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f
    }()

    static func range(_ start: Date, _ end: Date?) -> String {
        "\(time.string(from: start)) – \(end.map { time.string(from: $0) } ?? "now")"
    }

    static func dayTitle(_ day: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let base = dayHeader.string(from: day)
        if cal.isDate(day, inSameDayAs: now) { return "Today · \(base)" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(day, inSameDayAs: y) {
            return "Yesterday · \(base)"
        }
        return base
    }
}
