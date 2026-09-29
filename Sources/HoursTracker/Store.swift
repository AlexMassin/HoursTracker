import Foundation
import SwiftUI
import AppKit
import ServiceManagement

enum AddResult {
    case added(Project)
    case duplicate(Project)
    case invalid
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var now = Date()
    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedProjectID") }
    }

    private var tickTask: Task<Void, Never>?
    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("HoursTracker", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")
        load()
        if let s = UserDefaults.standard.string(forKey: "selectedProjectID"), let id = UUID(uuidString: s),
           data.projects.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = data.running?.projectID ?? data.projects.first?.id
        }
        if let r = data.running { selectedID = r.projectID }
        updateTicker()
    }

    // MARK: - Persistence (format unchanged from v1; colorIndex is an optional extra key)

    private func load() {
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(AppData.self, from: raw) {
            data = decoded
        } else {
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("HoursTracker: failed to save: \(error)")
        }
    }

    // MARK: - Ticking (only while running, aligned to whole seconds)

    private func updateTicker() {
        tickTask?.cancel()
        tickTask = nil
        now = Date()
        guard data.running != nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let t = Date().timeIntervalSince1970
                let wait = (t.rounded(.down) + 1) - t
                try? await Task.sleep(nanoseconds: UInt64(max(0.01, wait) * 1_000_000_000))
                if Task.isCancelled { break }
                self?.now = Date()
            }
        }
    }

    /// Call when the popover appears so idle totals (Today/Week boundaries) are fresh.
    func refreshNow() { now = Date() }

    // MARK: - Accessors

    var projects: [Project] { data.projects }
    var running: RunningSession? { data.running }
    var isRunning: Bool { data.running != nil }

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return data.projects.first { $0.id == id }
    }

    var selectedProject: Project? { project(selectedID) }
    var runningProject: Project? { project(data.running?.projectID) }
    var selectedIsRunning: Bool { data.running != nil && data.running?.projectID == selectedID }

    func isRunning(_ id: UUID) -> Bool { data.running?.projectID == id }

    func colorIndex(for p: Project) -> Int {
        if let c = p.colorIndex { return ((c % HT.palette.count) + HT.palette.count) % HT.palette.count }
        let pos = data.projects.firstIndex(where: { $0.id == p.id }) ?? 0
        return pos % HT.palette.count
    }

    func color(for p: Project?) -> Color {
        guard let p else { return .secondary }
        return HT.palette[colorIndex(for: p)]
    }

    var currentElapsed: TimeInterval {
        guard let r = data.running else { return 0 }
        return max(0, now.timeIntervalSince(r.start))
    }

    /// Completed sessions, newest first.
    func sessions(for projectID: UUID) -> [WorkSession] {
        data.sessions.filter { $0.projectID == projectID }.sorted { $0.start > $1.start }
    }

    func sessionCount(for projectID: UUID) -> Int {
        data.sessions.reduce(0) { $0 + ($1.projectID == projectID ? 1 : 0) }
    }

    func total(for projectID: UUID, from: Date?, to: Date? = nil) -> TimeInterval {
        var all = data.sessions.filter { $0.projectID == projectID }
        if let r = data.running, r.projectID == projectID {
            all.append(WorkSession(projectID: projectID, start: r.start, end: max(now, r.start)))
        }
        let lower = from ?? .distantPast
        let upper = to ?? .distantFuture
        return all.reduce(0) { acc, s in
            acc + max(0, min(s.end, upper).timeIntervalSince(max(s.start, lower)))
        }
    }

    var startOfToday: Date { Calendar.current.startOfDay(for: now) }
    var startOfWeek: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
    }

    func totals(_ id: UUID) -> Totals {
        Totals(today: total(for: id, from: startOfToday),
               week: total(for: id, from: startOfWeek),
               all: total(for: id, from: nil))
    }

    // MARK: - Mutations

    func addProject(named name: String) -> AddResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }
        if let existing = data.projects.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .duplicate(existing)
        }
        let used = data.projects.map { colorIndex(for: $0) }
        let next = (0..<HT.palette.count).first { !used.contains($0) } ?? (data.projects.count % HT.palette.count)
        let p = Project(name: trimmed, colorIndex: next)
        data.projects.append(p)
        if selectedID == nil || !isRunning { selectedID = p.id }
        save()
        return .added(p)
    }

    /// Returns false if the name is empty or taken by another project.
    @discardableResult
    func rename(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = data.projects.firstIndex(where: { $0.id == id }) else { return false }
        if data.projects.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return false
        }
        data.projects[i].name = trimmed
        save()
        return true
    }

    func setColor(_ id: UUID, index: Int) {
        guard let i = data.projects.firstIndex(where: { $0.id == id }) else { return }
        data.projects[i].colorIndex = index
        save()
    }

    func deleteProject(_ id: UUID) {
        if data.running?.projectID == id {
            data.running = nil
            updateTicker()
        }
        data.projects.removeAll { $0.id == id }
        data.sessions.removeAll { $0.projectID == id }
        if selectedID == id { selectedID = data.projects.first?.id }
        save()
    }

    func deleteSession(_ id: UUID) {
        data.sessions.removeAll { $0.id == id }
        save()
    }

    func start(_ projectID: UUID) {
        selectedID = projectID
        if let r = data.running {
            if r.projectID == projectID { return }
            finishRunning()
        }
        data.running = RunningSession(projectID: projectID, start: Date())
        save()
        updateTicker()
    }

    func stop() {
        finishRunning()
        save()
        updateTicker()
    }

    func toggle(_ projectID: UUID) {
        if isRunning(projectID) { stop() } else { start(projectID) }
    }

    func toggleSelected() {
        if selectedIsRunning {
            stop()
        } else if let id = selectedID, project(id) != nil {
            start(id)
        }
    }

    private func finishRunning() {
        guard let r = data.running else { return }
        let end = Date()
        if end.timeIntervalSince(r.start) >= 1 {
            data.sessions.append(WorkSession(projectID: r.projectID, start: r.start, end: end))
        }
        data.running = nil
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        objectWillChange.send()
    }

    // MARK: - Export

    func csvString(from: Date? = nil) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone.current
        func esc(_ s: String) -> String {
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        var rows = data.sessions
        if let r = data.running {
            rows.append(WorkSession(projectID: r.projectID, start: r.start, end: Date()))
        }
        if let from { rows = rows.filter { $0.end > from } }
        var lines = ["project,start,end,duration_hours"]
        for s in rows.sorted(by: { $0.start < $1.start }) {
            let name = project(s.projectID)?.name ?? "Unknown"
            lines.append("\(esc(name)),\(iso.string(from: s.start)),\(iso.string(from: s.end)),\(String(format: "%.4f", s.duration / 3600))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func exportCSV(thisWeekOnly: Bool = false) {
        let panel = NSSavePanel()
        panel.title = thisWeekOnly ? "Export This Week" : "Export Hours"
        panel.allowedContentTypes = [.commaSeparatedText]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = thisWeekOnly
            ? "hours-week-of-\(df.string(from: startOfWeek)).csv"
            : "hours-\(df.string(from: Date())).csv"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .floating
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try csvString(from: thisWeekOnly ? startOfWeek : nil).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
