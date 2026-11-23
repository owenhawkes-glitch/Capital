import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Private drag type so reordering never collides with file drops.
    static let duoNotchReorder = UTType(exportedAs: "com.hawkes.duonotch.reorder")
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
            provider.registerDataRepresentation(forTypeIdentifier: UTType.duoNotchReorder.identifier, visibility: .ownProcess) { done in
                done(Data(id.utf8), nil)
                return nil
            }
            return provider
        }
    }

    /// Moves the dragged item to this position as the pointer passes over it.
    func reorderTarget(id: String, move: @escaping (_ dragged: String, _ target: String) -> Void) -> some View {
        onDrop(of: [.duoNotchReorder], delegate: ReorderDelegate(targetID: id, move: move))
    }
}

struct ReorderDelegate: DropDelegate {
    let targetID: String
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let dragged = ReorderState.shared.draggingID, dragged != targetID else { return }
            withAnimation(.easeOut(duration: 0.15)) { move(dragged, targetID) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { ReorderState.shared.draggingID = nil }
        return true
    }
}
