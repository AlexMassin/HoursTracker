import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DebugHooks.openPopoverIfRequested()
    }
}

@main
struct HoursTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PopoverRoot()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: Store

    /// Menu-bar point size; used for both the measured slot and the Text font so
    /// SwiftUI/AppKit agree on advance widths.
    private static let menuBarPointSize: CGFloat = NSFont.menuBarFont(ofSize: 0).pointSize

    /// Fully monospaced face (fixed advance for every glyph, not just digits).
    private static let monoFont: Font = .system(size: menuBarPointSize, weight: .regular, design: .monospaced)

    private static let monoNSFont: NSFont = .monospacedSystemFont(ofSize: menuBarPointSize, weight: .regular)

    /// Explicit width of the padded time string "99:59:59" in `monoNSFont`.
    private static let timeSlotWidth: CGFloat = {
        ceil(("99:59:59" as NSString).size(withAttributes: [.font: monoNSFont]).width)
    }()

    /// Icon + small gap + time slot. Locked onto NSStatusItem.length while running
    /// because MenuBarExtra often ignores SwiftUI `.frame` for status-item sizing.
    fileprivate static let runningStatusLength: CGFloat = {
        // SF Symbol in the menu bar is roughly the menu-bar font size; +10 for
        // image/title padding that AppKit inserts between image and title.
        ceil(menuBarPointSize + 10 + timeSlotWidth)
    }()

    var body: some View {
        // Menu bar labels only honour Image + Text as direct label children;
        // do not wrap them in Group/HStack or AppKit will not pick up both.
        if store.isRunning {
            Image(systemName: "timer")
                .accessibilityLabel("HoursTracker")
            Text(Fmt.hmsPadded(store.currentElapsed))
                .font(Self.monoFont)
                .monospacedDigit()
                .frame(width: Self.timeSlotWidth, alignment: .center)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityValue("Tracking \(store.runningProject?.name ?? "a project"), \(Fmt.spoken(store.currentElapsed))")
                .onAppear { MenuBarStatusItemLock.sync(isRunning: true) }
                // Re-assert length every tick: SwiftUI may reset NSStatusItem.length
                // when the title string updates.
                .onChange(of: store.currentElapsed) { _ in
                    MenuBarStatusItemLock.sync(isRunning: true)
                }
        } else {
            Image(systemName: "clock")
                .accessibilityLabel("HoursTracker")
                .accessibilityValue("Not tracking")
                .onAppear { MenuBarStatusItemLock.sync(isRunning: false) }
        }
    }
}

/// Pins the MenuBarExtra `NSStatusItem` to a constant length while the timer runs
/// so the menu-bar pill cannot shift left/right as digits change.
enum MenuBarStatusItemLock {
    static func sync(isRunning: Bool) {
        guard let item = findStatusItem() else { return }
        if isRunning {
            item.length = MenuBarLabel.runningStatusLength
        } else {
            item.length = NSStatusItem.variableLength
        }
    }

    private static func findStatusItem() -> NSStatusItem? {
        for w in NSApp.windows {
            if let button = findStatusButton(w.contentView) {
                if let item = button.value(forKey: "statusItem") as? NSStatusItem {
                    return item
                }
                if let item = button.value(forKey: "_statusItem") as? NSStatusItem {
                    return item
                }
            }
        }
        return nil
    }

    private static func findStatusButton(_ v: NSView?) -> NSStatusBarButton? {
        guard let v else { return nil }
        if let b = v as? NSStatusBarButton { return b }
        for s in v.subviews {
            if let b = findStatusButton(s) { return b }
        }
        return nil
    }
}

/// Env-gated helpers used only for automated verification:
///   HT_DEBUG_OPEN=1        -> clicks the status item shortly after launch to show the popover
///   HT_DEBUG_DUMP=<path>   -> writes the popover window's view hierarchy + window number there
enum DebugHooks {
    private static var dumped = false

    static func openPopoverIfRequested() {
        guard ProcessInfo.processInfo.environment["HT_DEBUG_OPEN"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for w in NSApp.windows {
                if let button = findStatusButton(w.contentView) {
                    button.performClick(nil)
                    return
                }
            }
        }
    }

    private static func findStatusButton(_ v: NSView?) -> NSStatusBarButton? {
        guard let v else { return nil }
        if let b = v as? NSStatusBarButton { return b }
        for s in v.subviews { if let b = findStatusButton(s) { return b } }
        return nil
    }

    @MainActor
    static func dumpIfRequested(window: NSWindow, hostIsGlass: Bool) {
        guard !dumped, let path = ProcessInfo.processInfo.environment["HT_DEBUG_DUMP"], !path.isEmpty else { return }
        dumped = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            var out = "windowNumber=\(window.windowNumber)\n"
            out += "windowClass=\(type(of: window)) isKey=\(window.isKeyWindow) canBecomeKey=\(window.canBecomeKey) frame=\(window.frame)\n"
            out += "hostIsGlass=\(hostIsGlass) glassCompiled=\(HT_glassAvailable)\n"
            out += WindowProbe.hierarchyDump(window.contentView?.superview ?? window.contentView)
            try? out.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
