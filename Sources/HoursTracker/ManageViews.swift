import SwiftUI
import AppKit

// MARK: - Compact nav header

struct NavHeader<Title: View>: View {
    var backTitle: String
    var onBack: () -> Void
    @ViewBuilder var title: () -> Title

    var body: some View {
        ZStack {
            title()
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 90)
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text(backTitle)
                    }
                }
                .buttonStyle(.bordered)
                .capsuleButton()
                .controlSize(.regular)
                .tint(.accentColor)
                .help("Back (Esc)")
                Spacer()
            }
        }
        .frame(height: 30)
    }
}

// MARK: - Manage Projects

struct ManageView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: HT.Space.m) {
            NavHeader(backTitle: "Back", onBack: { ui.pop() }) {
                Text("Manage Projects")
            }

            if store.projects.isEmpty {
                emptyState
            } else {
                let list = VStack(spacing: 0) {
                    ForEach(Array(store.projects.enumerated()), id: \.element.id) { idx, p in
                        if idx > 0 { Divider().padding(.leading, 30) }
                        ManageRow(project: p)
                    }
                }
                .padding(HT.Space.xs)
                .background(HT.cardShape.fill(.quaternary))

                if store.projects.count > 7 {
                    ScrollView { list }.frame(height: 7 * 48)
                } else {
                    list
                }

                Text("Double-click a name to rename · Right-click for more")
                    .font(.caption)
                    .tertiaryText()
                    .frame(maxWidth: .infinity)
            }

            Divider()

            HStack {
                Button {
                    ui.popToRoot()
                    ui.isAdding = true
                } label: {
                    HStack(spacing: 4) {
                        Label("New Project", systemImage: "plus")
                        Text("⌘N").font(.caption).tertiaryText()
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                Spacer()
                Button {
                    store.exportCSV()
                } label: {
                    Label("Export CSV…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
            }
            .font(.callout)
            .padding(.horizontal, HT.Space.xs)
        }
    }

    private var emptyState: some View {
        VStack(spacing: HT.Space.s) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("No projects yet").font(.headline)
            Button("New Project") {
                ui.popToRoot()
                ui.isAdding = true
            }
            .buttonStyle(.borderedProminent)
            .capsuleButton()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HT.Space.l)
    }
}

struct ManageRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let project: Project

    @State private var hovered = false
    @State private var text = ""
    @State private var error = false
    @FocusState private var focused: Bool

    private var isRenaming: Bool { ui.renamingID == project.id }

    var body: some View {
        HStack(spacing: 10) {
            ColorDot(color: store.color(for: project))
            if isRenaming {
                renameEditor
            } else {
                display
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background {
            if hovered && !isRenaming { HT.rowShape.fill(Color.primary.opacity(0.06)) }
        }
        .contentShape(HT.rowShape)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .contextMenu {
            Button("Rename…") { beginRename() }
            Button("Show Sessions") { ui.push(.sessions(project.id)) }
            Divider()
            Button("Delete…", role: .destructive) { ui.pendingDelete = .project(project.id) }
        }
        .onAppear {
            if isRenaming { beginRename() }
        }
    }

    private var display: some View {
        let count = store.sessionCount(for: project.id) + (store.isRunning(project.id) ? 1 : 0)
        let all = store.total(for: project.id, from: nil)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { beginRename() }
                Text("\(count) session\(count == 1 ? "" : "s") · \(Fmt.hm(all)) total")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: HT.Space.s)
            if hovered {
                Button { beginRename() } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Rename")
                    .accessibilityLabel("Rename \(project.name)")
                Button { ui.pendingDelete = .project(project.id) } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Delete")
                .accessibilityLabel("Delete \(project.name)")
            }
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .tertiaryText()
        }
        .contentShape(Rectangle())
        .onTapGesture { ui.push(.sessions(project.id)) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows sessions")
        .accessibilityAction(named: "Rename") { beginRename() }
        .accessibilityAction(named: "Delete") { ui.pendingDelete = .project(project.id) }
    }

    private var renameEditor: some View {
        HStack(spacing: HT.Space.s) {
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
                .onExitCommand { cancel() }
                .onChange(of: text) { _ in error = false }
                .onChange(of: focused) { f in
                    ui.textFieldFocused = f
                    // Focus loss saves if valid.
                    if !f && isRenaming { save(silently: true) }
                }
                .overlay {
                    if error {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.red, lineWidth: 1)
                    }
                }
                .help(error ? "Name is empty or already used" : "")
            Button("Cancel", action: cancel)
                .buttonStyle(.bordered)
                .capsuleButton()
                .controlSize(.small)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .capsuleButton()
                .controlSize(.small)
        }
        .onAppear {
            if text.isEmpty { text = project.name }
            DispatchQueue.main.async { focused = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
    }

    private func beginRename() {
        text = project.name
        error = false
        ui.renamingID = project.id
        DispatchQueue.main.async { focused = true }
    }

    private func save() { save(silently: false) }

    private func save(silently: Bool) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == project.name {
            ui.renamingID = nil
            return
        }
        if store.rename(project.id, to: text) {
            ui.renamingID = nil
        } else if silently {
            ui.renamingID = nil
        } else {
            error = true
            NSSound.beep()
        }
    }

    private func cancel() {
        ui.renamingID = nil
        ui.textFieldFocused = false
    }
}

// MARK: - Sessions drill-in

private struct DayGroup: Identifiable {
    var day: Date
    var items: [SessionItem]
    var id: Date { day }
    var total: TimeInterval { items.reduce(0) { $0 + $1.duration } }
}

private struct SessionItem: Identifiable {
    var session: WorkSession
    var isRunning: Bool
    var id: UUID { session.id }
    var duration: TimeInterval { session.duration }
}

struct SessionsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let projectID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: HT.Space.m) {
            NavHeader(backTitle: "Manage", onBack: { ui.pop() }) {
                HStack(spacing: 6) {
                    ColorDot(color: store.color(for: store.project(projectID)))
                    Text(store.project(projectID)?.name ?? "Project")
                }
            }

            if store.project(projectID) == nil {
                Text("This project no longer exists.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HT.Space.l)
            } else {
                let t = store.totals(projectID)
                HStack(spacing: HT.Space.s) {
                    StatTile(label: "Today", value: Fmt.hm(t.today))
                    StatTile(label: "This Week", value: Fmt.hm(t.week))
                    StatTile(label: "All Time", value: Fmt.hm(t.all))
                }

                let groups = dayGroups()
                if groups.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: HT.Space.m) {
                            ForEach(groups) { g in
                                daySection(g)
                            }
                        }
                    }
                    .frame(maxHeight: 380)
                    .fixedSize(horizontal: false, vertical: groups.reduce(0) { $0 + $1.items.count } <= 6)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: HT.Space.s) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("No sessions yet").font(.headline)
            Text("Start the timer to record time for \(store.project(projectID)?.name ?? "this project").")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HT.Space.l)
    }

    private func daySection(_ g: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: HT.Space.xs) {
            HStack {
                Text(Fmt.dayTitle(g.day, now: store.now))
                    .textCase(.uppercase)
                Spacer()
                Text(Fmt.hm(g.total)).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, HT.Space.xs)

            VStack(spacing: 0) {
                ForEach(Array(g.items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Divider().padding(.horizontal, HT.Space.s) }
                    SessionRow(item: item, projectName: store.project(projectID)?.name ?? "")
                }
            }
            .padding(HT.Space.xs)
            .background(HT.cardShape.fill(.quaternary))
        }
    }

    private func dayGroups() -> [DayGroup] {
        var items = store.sessions(for: projectID).map { SessionItem(session: $0, isRunning: false) }
        if let r = store.running, r.projectID == projectID {
            items.insert(SessionItem(session: WorkSession(id: runningSessionID, projectID: projectID,
                                                          start: r.start, end: max(store.now, r.start)),
                                     isRunning: true), at: 0)
        }
        let cal = Calendar.current
        let dict = Dictionary(grouping: items) { cal.startOfDay(for: $0.session.start) }
        return dict.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: dict[day]!.sorted { $0.session.start > $1.session.start })
        }
    }
}

/// Stable id for the synthetic running-session row.
private let runningSessionID = UUID()

private struct StatTile: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, HT.Space.s)
        .background(HT.cardShape.fill(.quaternary))
        .accessibilityElement(children: .combine)
    }
}

private struct SessionRow: View {
    @EnvironmentObject var ui: UIState
    let item: SessionItem
    let projectName: String
    @State private var hovered = false

    var body: some View {
        HStack(spacing: HT.Space.s) {
            Text(Fmt.range(item.session.start, item.isRunning ? nil : item.session.end))
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: HT.Space.s)
            Text(Fmt.hms(item.duration))
                .fontWeight(.semibold)
                .monospacedDigit()
            ZStack {
                if item.isRunning {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                        .pulse(true)
                        .accessibilityLabel("Recording")
                } else if hovered {
                    Button {
                        ui.pendingDelete = .session(item.session)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete session")
                    .accessibilityLabel("Delete session")
                }
            }
            .frame(width: 20)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background {
            if hovered && !item.isRunning { HT.rowShape.fill(Color.primary.opacity(0.06)) }
        }
        .contentShape(HT.rowShape)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .contextMenu {
            if !item.isRunning {
                Button("Delete Session", role: .destructive) { ui.pendingDelete = .session(item.session) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Fmt.spoken(item.duration))
        .accessibilityAction(named: "Delete") {
            if !item.isRunning { ui.pendingDelete = .session(item.session) }
        }
    }
}

// MARK: - Confirmation overlay (in-panel replacement for confirmationDialog)

struct ConfirmOverlay: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let pending: PendingDelete

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { ui.pendingDelete = nil }
            VStack(spacing: HT.Space.s) {
                Image(systemName: "clock")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.gradient))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: HT.Space.s) {
                    Button(role: .destructive, action: confirm) {
                        Text(confirmTitle).fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .capsuleButton()
                    .tint(.red)
                    .controlSize(.large)
                    Button {
                        ui.pendingDelete = nil
                    } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .capsuleButton()
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, HT.Space.xs)
            }
            .padding(HT.Space.l)
            .frame(width: 260)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private var title: String {
        switch pending {
        case .project(let id): return "Delete “\(store.project(id)?.name ?? "project")”?"
        case .session: return "Delete this session?"
        }
    }

    private var confirmTitle: String {
        switch pending {
        case .project: return "Delete Project"
        case .session: return "Delete Session"
        }
    }

    private var message: String {
        switch pending {
        case .project(let id):
            let n = store.sessionCount(for: id)
            let total = store.total(for: id, from: nil)
            var msg = "This deletes \(n) session\(n == 1 ? "" : "s") (\(Fmt.hm(total))). This can’t be undone."
            if store.isRunning(id) { msg = "The running timer will be stopped. " + msg }
            return msg
        case .session(let s):
            let name = store.project(s.projectID)?.name ?? "this project"
            return "\(Fmt.range(s.start, s.end)) (\(Fmt.hms(s.duration))) will be removed from \(name). This can’t be undone."
        }
    }

    private func confirm() {
        switch pending {
        case .project(let id):
            store.deleteProject(id)
            if case .sessions(let sid) = ui.route, sid == id { ui.pop() }
            if ui.renamingID == id { ui.renamingID = nil }
        case .session(let s):
            store.deleteSession(s.id)
        }
        ui.pendingDelete = nil
    }
}
