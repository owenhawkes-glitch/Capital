import SwiftUI
import UniformTypeIdentifiers

// Copied from DuoNotch's Notch/Reorder.swift; adds a commit callback so a
// drop can trigger the real move in the menu bar.

extension UTType {
    /// Private drag type so reordering never collides with file drops.
    static let menuBentoReorder = UTType(exportedAs: "com.hawkes.menubento.reorder")
}

/// What is being dragged for reordering, by id.
@MainActor
final class ReorderState: ObservableObject {
    static let shared = ReorderState()
    @Published var draggingID: String?
}

extension View {
    /// Makes this view draggable for reordering among its siblings.
    func reorderSource(id: String) -> some View {
        onDrag {
            ReorderState.shared.draggingID = id
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.menuBentoReorder.identifier, visibility: .ownProcess) { done in
                done(Data(id.utf8), nil)
                return nil
            }
            return provider
        }
    }

    /// Moves the dragged item to this position as the pointer passes over
    /// it, and calls `commit` when it is dropped.
    func reorderTarget(id: String, move: @escaping (_ dragged: String, _ target: String) -> Void,
                       commit: @escaping () -> Void = {}) -> some View {
        onDrop(of: [.menuBentoReorder], delegate: ReorderDelegate(targetID: id, move: move, commit: commit))
    }
}

struct ReorderDelegate: DropDelegate {
    let targetID: String
    let move: (String, String) -> Void
    var commit: () -> Void = {}

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let dragged = ReorderState.shared.draggingID, dragged != targetID else { return }
            withAnimation(.easeOut(duration: 0.15)) { move(dragged, targetID) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { ReorderState.shared.draggingID = nil }
        commit()
        return true
    }
}
