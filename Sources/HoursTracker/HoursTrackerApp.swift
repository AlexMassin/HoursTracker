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

    /// Fits "99:59:59" in the menu-bar monospaced-digit face so the status-item
    /// pill width stays fixed as seconds (and hour digits) change.
    private static let timeSlotMinWidth: CGFloat = {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        return ceil(("99:59:59" as NSString).size(withAttributes: [.font: font]).width)
    }()

    var body: some View {
        // Menu bar labels only honour Image + Text; keep it simple.
        if store.isRunning {
            Image(systemName: "timer")
                .accessibilityLabel("HoursTracker")
            Text(Fmt.hms(store.currentElapsed))
                .monospacedDigit()
                .frame(minWidth: Self.timeSlotMinWidth, alignment: .center)
                .accessibilityValue("Tracking \(store.runningProject?.name ?? "a project"), \(Fmt.spoken(store.currentElapsed))")
        } else {
            Image(systemName: "clock")
                .accessibilityLabel("HoursTracker")
                .accessibilityValue("Not tracking")
        }
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
