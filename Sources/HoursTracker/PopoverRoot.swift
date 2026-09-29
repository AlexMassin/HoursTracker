import SwiftUI
import AppKit

struct PopoverRoot: View {
    @EnvironmentObject var store: Store
    @StateObject private var ui = UIState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch ui.route {
            case .none:
                MainPage()
                    .transition(pageTransition)
            case .some(.manage):
                ManageView()
                    .transition(pageTransition)
            case .some(.sessions(let id)):
                SessionsView(projectID: id)
                    .id(id)
                    .transition(pageTransition)
            }
        }
        .padding(HT.Space.m)
        .frame(width: HT.popoverWidth, alignment: .top)
        .frame(maxHeight: HT.maxHeight, alignment: .top)
        .clipped()
        .overlay {
            if let pending = ui.pendingDelete {
                ConfirmOverlay(pending: pending)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: ui.path)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: ui.pendingDelete)
        .environmentObject(ui)
        .background {
            KeyboardShortcuts()
                .environmentObject(ui)
        }
        .background {
            WindowProbe { window in
                store.refreshNow()
                let glass = WindowProbe.windowChromeIsGlass(window)
                if ui.hostIsGlass != glass { ui.hostIsGlass = glass }
                DebugHooks.dumpIfRequested(window: window, hostIsGlass: glass)
            }
            .frame(width: 0, height: 0)
        }
        .onExitCommand {
            if ui.pendingDelete != nil {
                ui.pendingDelete = nil
            } else if ui.renamingID != nil {
                ui.renamingID = nil
            } else if ui.isAdding {
                ui.isAdding = false
            } else if !ui.path.isEmpty {
                ui.pop()
            }
        }
        .onAppear {
            store.refreshNow()
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let edgeIn: Edge = ui.navForward ? .trailing : .leading
        let edgeOut: Edge = ui.navForward ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: edgeIn).combined(with: .opacity),
                           removal: .move(edge: edgeOut).combined(with: .opacity))
    }
}

/// Invisible buttons that carry shortcuts (macOS 13-safe).
private struct KeyboardShortcuts: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState

    var body: some View {
        ZStack {
            Button("New Project") { openAdd() }.keyboardShortcut("n")
            Button("Manage") { ui.path = [.manage]; ui.navForward = true }.keyboardShortcut(",")
            Button("Export") { store.exportCSV() }.keyboardShortcut("e")
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            Button("Start/Stop") { store.toggleSelected() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(ui.isEditingText || ui.pendingDelete != nil || ui.route != nil)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func openAdd() {
        if !ui.path.isEmpty { ui.popToRoot() }
        ui.isAdding = true
    }
}

// MARK: - Main page

struct MainPage: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: HT.Space.m) {
            HeroCard()
            ProjectsSection()
            Divider()
            FooterBar()
        }
    }
}

// MARK: - Hero

struct HeroCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let running = store.selectedIsRunning
        let name = store.selectedProject?.name ?? "project"
        VStack(alignment: .leading, spacing: HT.Space.s) {
            HStack {
                ProjectPicker()
                Spacer(minLength: HT.Space.s)
                StatusBadge(isRunning: running)
            }
            timer(running: running)
            HStack(alignment: .center) {
                Text(metaLine(running: running))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: HT.Space.s)
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { store.toggleSelected() }
                } label: {
                    Label(running ? "Stop" : "Start", systemImage: running ? "stop.fill" : "play.fill")
                        .fontWeight(.semibold)
                        .symbolReplace()
                }
                .primaryActionStyle()
                .controlSize(.large)
                .capsuleButton()
                .tint(running ? .red : .accentColor)
                .disabled(store.selectedProject == nil)
                .help(running ? "Stop timer (Space)" : "Start timer (Space)")
                .accessibilityLabel(running ? "Stop timer for \(name)" : "Start timer for \(name)")
            }
        }
        .padding(HT.Space.m)
        .glassOrMaterial(in: HT.cardShape, tint: running ? .green : nil, allowGlass: !ui.hostIsGlass)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: running)
    }

    @ViewBuilder
    private func timer(running: Bool) -> some View {
        if running, let session = store.running {
            TimelineView(.periodic(from: session.start, by: 1)) { ctx in
                let t = max(0, ctx.date.timeIntervalSince(session.start))
                Text(Fmt.hms(t))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .animation(reduceMotion ? nil : .default, value: Int(t))
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(Fmt.spoken(t))
            }
        } else {
            Text("0:00:00")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Timer not running")
        }
    }

    private func metaLine(running: Bool) -> String {
        guard let p = store.selectedProject else {
            return store.projects.isEmpty ? "Add a project to get started" : "Choose a project"
        }
        let t = store.totals(p.id)
        if running, let r = store.running {
            return "Started \(Fmt.time.string(from: r.start)) · Today \(Fmt.hm(t.today))"
        }
        if let other = store.runningProject {
            return "\(other.name) is running · Today \(Fmt.hm(t.today))"
        }
        return "Today \(Fmt.hm(t.today)) · This week \(Fmt.hm(t.week))"
    }
}

struct ProjectPicker: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState

    var body: some View {
        Menu {
            ForEach(store.projects) { p in
                Button {
                    store.selectedID = p.id
                } label: {
                    if p.id == store.selectedID {
                        Label(p.name, systemImage: "checkmark")
                    } else {
                        Text(p.name)
                    }
                }
            }
            if !store.projects.isEmpty { Divider() }
            Button("New Project…") { ui.isAdding = true }
        } label: {
            HStack(spacing: 6) {
                ColorDot(color: store.color(for: store.selectedProject))
                Text(store.selectedProject?.name ?? "Choose Project")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose project")
        .accessibilityLabel("Project")
        .accessibilityValue(store.selectedProject?.name ?? "None")
    }
}

struct StatusBadge: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isRunning {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.green)
                    .pulse(true)
            }
            Text(isRunning ? "Recording" : "Not running")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isRunning ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Projects section

struct ProjectsSection: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rowHeight: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: HT.Space.s) {
            HStack {
                Text("Projects")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                HoverCircleButton(systemImage: "plus", help: "New Project (⌘N)", isActive: ui.isAdding) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { ui.isAdding.toggle() }
                }
            }
            .padding(.horizontal, HT.Space.xs)

            if ui.isAdding {
                AddProjectField()
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if store.projects.isEmpty {
                if !ui.isAdding { emptyState }
            } else {
                list
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: ui.isAdding)
    }

    private var emptyState: some View {
        VStack(spacing: HT.Space.s) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("No projects yet").font(.headline)
            Button("New Project") { ui.isAdding = true }
                .buttonStyle(.borderedProminent)
                .capsuleButton()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HT.Space.l)
    }

    @ViewBuilder
    private var list: some View {
        let rows = VStack(spacing: HT.Space.xxs) {
            ForEach(store.projects) { p in
                ProjectRow(project: p)
                    .id(p.id)
            }
        }
        if store.projects.count > 6 {
            ScrollViewReader { proxy in
                ScrollView {
                    rows
                }
                .frame(height: rowHeight * 6.5)
                .onChange(of: ui.flashID) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        } else {
            rows
        }
    }
}

struct AddProjectField: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HT.Space.xs) {
            HStack(spacing: HT.Space.s) {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(add)
                    .onExitCommand { close() }
                    .onChange(of: name) { _ in error = nil }
                Button(action: add) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .capsuleButton()
                .controlSize(.small)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Group {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Return to add · Esc to cancel").tertiaryText()
                }
            }
            .font(.caption)
            .padding(.leading, HT.Space.xs)
        }
        .onAppear {
            ui.textFieldFocused = true
            DispatchQueue.main.async { focused = true }
            // Second attempt in case the panel only just became key.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
        .onDisappear { ui.textFieldFocused = false }
        .onChange(of: focused) { f in ui.textFieldFocused = f }
    }

    private func add() {
        switch store.addProject(named: name) {
        case .added(let p):
            name = ""
            error = nil
            ui.flashID = p.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if ui.flashID == p.id { ui.flashID = nil }
            }
            focused = true
        case .duplicate(let p):
            error = "A project named “\(p.name)” already exists."
        case .invalid:
            break
        }
    }

    private func close() {
        name = ""
        error = nil
        ui.isAdding = false
    }
}

struct ProjectRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let project: Project
    @State private var hovered = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let running = store.isRunning(project.id)
        let totals = store.totals(project.id)
        let flashing = ui.flashID == project.id

        HStack(spacing: 10) {
            ColorDot(color: store.color(for: project))
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Week \(Fmt.hm(totals.week)) · All \(Fmt.hm(totals.all))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: HT.Space.s)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.hm(totals.today))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text("today").font(.caption2).tertiaryText()
            }
            Button {
                store.toggle(project.id)
            } label: {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .symbolReplace()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(running || hovered ? Color.white : Color.secondary)
                    .background(Circle().fill(running ? AnyShapeStyle(Color.red)
                                              : hovered ? AnyShapeStyle(Color.accentColor)
                                              : AnyShapeStyle(.quaternary)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(running ? "Stop" : (store.isRunning ? "Switch to \(project.name)" : "Start"))
            .accessibilityLabel(running ? "Stop \(project.name)" : "Start \(project.name)")
        }
        .padding(.vertical, 7)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .background {
            if running {
                HT.rowShape.fill(Color.green.opacity(0.12))
            } else if flashing {
                HT.rowShape.fill(Color.accentColor.opacity(0.18))
            } else if hovered {
                HT.rowShape.fill(Color.primary.opacity(reduceTransparency ? 0.1 : 0.06))
            } else if project.id == store.selectedID && store.projects.count > 1 {
                HT.rowShape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .contentShape(HT.rowShape)
        .onTapGesture(count: 2) { store.start(project.id) }
        .onTapGesture { store.selectedID = project.id }
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.3), value: flashing)
        .contextMenu { contextMenu(running: running) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(project.name)
        .accessibilityValue("\(running ? "Recording. " : "")Today \(Fmt.spoken(totals.today)), this week \(Fmt.spoken(totals.week)), all time \(Fmt.spoken(totals.all))")
        .accessibilityAddTraits(running ? .isSelected : [])
        .accessibilityAction(named: running ? "Stop" : "Start") { store.toggle(project.id) }
        .accessibilityAction(named: "Rename") { rename() }
        .accessibilityAction(named: "Delete") { ui.pendingDelete = .project(project.id) }
    }

    @ViewBuilder
    private func contextMenu(running: Bool) -> some View {
        Button(running ? "Stop" : "Start") { store.toggle(project.id) }
        Button("Rename…") { rename() }
        Menu("Color") {
            ForEach(HT.palette.indices, id: \.self) { i in
                Button {
                    store.setColor(project.id, index: i)
                } label: {
                    if store.colorIndex(for: project) == i {
                        Label(HT.paletteNames[i], systemImage: "checkmark")
                    } else {
                        Text(HT.paletteNames[i])
                    }
                }
            }
        }
        Button("Show Sessions") {
            ui.navForward = true
            ui.path = [.manage, .sessions(project.id)]
        }
        Divider()
        Button("Delete…", role: .destructive) { ui.pendingDelete = .project(project.id) }
    }

    private func rename() {
        ui.navForward = true
        ui.path = [.manage]
        ui.renamingID = project.id
    }
}

// MARK: - Footer

struct FooterBar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState

    var body: some View {
        HStack(spacing: HT.Space.xs) {
            Button {
                ui.push(.manage)
            } label: {
                Label("Manage", systemImage: "slider.horizontal.3")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .help("Manage projects (⌘,)")
            Text("⌘,").font(.caption).tertiaryText()
            Spacer()
            GearMenu()
        }
        .padding(.horizontal, HT.Space.xs)
    }
}

struct GearMenu: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Menu {
            Button("Export CSV…") { store.exportCSV() }
                .keyboardShortcut("e")
            Button("Export This Week…") { store.exportCSV(thisWeekOnly: true) }
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            Divider()
            Button("About HoursTracker") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Button("Quit HoursTracker") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}
