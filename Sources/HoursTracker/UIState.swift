import SwiftUI

enum Route: Hashable {
    case manage
    case sessions(UUID)
}

/// Pending destructive action shown in the in-popover confirmation dialog.
enum PendingDelete: Identifiable, Equatable {
    case project(UUID)
    case session(WorkSession)

    var id: String {
        switch self {
        case .project(let id): return "p-\(id)"
        case .session(let s): return "s-\(s.id)"
        }
    }
}

@MainActor
final class UIState: ObservableObject {
    @Published var path: [Route] = []
    @Published var isAdding = false
    @Published var renamingID: UUID?
    @Published var pendingDelete: PendingDelete?
    @Published var flashID: UUID?
    /// Set when a text field has focus, so Space doesn't toggle the timer.
    @Published var textFieldFocused = false
    /// True when the host panel itself is Liquid Glass (avoid glass-on-glass on the hero).
    @Published var hostIsGlass = false
    @Published var navForward = true

    var route: Route? { path.last }

    func push(_ r: Route) {
        navForward = true
        path.append(r)
    }

    func pop() {
        navForward = false
        if !path.isEmpty { path.removeLast() }
        renamingID = nil
    }

    func popToRoot() {
        navForward = false
        path = []
        renamingID = nil
    }

    var isEditingText: Bool { textFieldFocused || isAdding || renamingID != nil }
}
