import SwiftUI
import AppKit

enum HT {
    static let popoverWidth: CGFloat = 332
    static let maxHeight: CGFloat = 560
    enum Space { static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16 }
    enum Radius { static let card: CGFloat = 12, row: CGFloat = 8 }
    static let palette: [Color] = [.blue, .orange, .purple, .green, .pink, .teal, .indigo, .yellow, .red, .mint]
    static let paletteNames = ["Blue", "Orange", "Purple", "Green", "Pink", "Teal", "Indigo", "Yellow", "Red", "Mint"]

    static var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.card, style: .continuous) }
    static var rowShape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.row, style: .continuous) }
}

// MARK: - Glass / material

/// Liquid Glass on macOS 26+ (when built with the 26+ SDK), tinted fill on 13–25,
/// opaque when Reduce Transparency is on.
struct GlassOrMaterial<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var allowGlass = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    private var strokeWidth: CGFloat { contrast == .increased ? 1 : 0.5 }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(tint ?? Color(nsColor: .separatorColor), lineWidth: strokeWidth))
        } else if allowGlass && HT_glassAvailable {
            glass(content)
        } else {
            fallback(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let g: Glass = tint.map { Glass.regular.tint($0.opacity(scheme == .dark ? 0.24 : 0.20)) } ?? Glass.regular
            content
                .glassEffect(g, in: shape)
                .overlay {
                    if contrast == .increased, let tint {
                        shape.strokeBorder(tint, lineWidth: 1)
                    }
                }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        let fill: AnyShapeStyle = tint.map { AnyShapeStyle($0.opacity(scheme == .dark ? 0.24 : 0.14)) }
            ?? AnyShapeStyle(.quaternary)
        let strokeColor: Color = contrast == .increased
            ? (tint ?? Color(nsColor: .separatorColor))
            : (tint ?? .primary).opacity(tint == nil ? 0.08 : 0.45)
        return content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(strokeColor, lineWidth: strokeWidth))
    }
}

/// True when the binary was compiled with a Liquid Glass capable SDK AND runs on macOS 26+.
var HT_glassAvailable: Bool {
    #if compiler(>=6.2)
    if #available(macOS 26, *) { return true }
    return false
    #else
    return false
    #endif
}

extension View {
    func glassOrMaterial<S: InsettableShape>(in shape: S, tint: Color? = nil, allowGlass: Bool = true) -> some View {
        modifier(GlassOrMaterial(shape: shape, tint: tint, allowGlass: allowGlass))
    }

    func primaryActionStyle() -> some View { modifier(PrimaryActionStyle()) }

    func pulse(_ active: Bool) -> some View { modifier(PulseIfAvailable(active: active)) }

    func symbolReplace() -> some View { modifier(SymbolReplaceIfAvailable()) }
}

struct PrimaryActionStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }
}

struct PulseIfAvailable: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.symbolEffect(.pulse, options: .repeating, isActive: active && !reduceMotion)
        } else {
            content
        }
    }
}

struct SymbolReplaceIfAvailable: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.contentTransition(.symbolEffect(.replace))
        } else {
            content
        }
    }
}

/// Tertiary text that becomes secondary under Increase Contrast.
struct TertiaryText: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.foregroundStyle(contrast == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
    }
}

extension View {
    func tertiaryText() -> some View { modifier(TertiaryText()) }
}

struct ColorDot: View {
    var color: Color
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Small circular icon button with a hover fill (header "+", etc.).
struct HoverCircleButton: View {
    var systemImage: String
    var help: String
    var isActive: Bool = false
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(hovered || isActive ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Host window probe

/// Gives access to the MenuBarExtra panel: makes it key on show (text input fix for early
/// macOS 27 betas) and reports whether the system drew the panel background as Liquid Glass.
struct WindowProbe: NSViewRepresentable {
    var onShow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.onShow = onShow
        return v
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onShow = onShow
    }

    final class ProbeView: NSView {
        var onShow: ((NSWindow) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let w = window else { return }
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in
                guard let self, let w = self.window, w.occlusionState.contains(.visible) else { return }
                self.fire(w)
            })
            DispatchQueue.main.async { [weak self] in
                guard let self, let w = self.window else { return }
                self.fire(w)
            }
        }

        private func fire(_ w: NSWindow) {
            if !w.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                w.makeKey()
            }
            onShow?(w)
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }

    /// Looks for a system glass view in the window chrome, skipping SwiftUI hosting content
    /// (so our own hero glass never counts).
    static func windowChromeIsGlass(_ w: NSWindow) -> Bool {
        let root = w.contentView?.superview ?? w.contentView
        return containsGlass(root)
    }

    private static func containsGlass(_ view: NSView?) -> Bool {
        guard let view else { return false }
        let name = String(describing: type(of: view))
        if name.contains("Hosting") { return false }
        if name.contains("Glass") { return true }
        return view.subviews.contains { containsGlass($0) }
    }

    static func hierarchyDump(_ view: NSView?, depth: Int = 0) -> String {
        guard let view else { return "" }
        var out = String(repeating: "  ", count: depth) + String(describing: type(of: view)) + " \(view.frame)\n"
        if depth < 12 {
            for sub in view.subviews { out += hierarchyDump(sub, depth: depth + 1) }
        }
        return out
    }
}

/// `.buttonBorderShape(.capsule)` is macOS 14+; on 13 keep the default rounded shape.
struct CapsuleButtonShape: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.buttonBorderShape(.capsule)
        } else {
            content
        }
    }
}

extension View {
    func capsuleButton() -> some View { modifier(CapsuleButtonShape()) }
}
