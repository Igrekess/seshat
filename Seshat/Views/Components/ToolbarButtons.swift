import SwiftUI

struct ToolbarButtons: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            // Undo/Redo
            Button(action: { appState.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!appState.canUndo)
            .help("Annuler (⌘Z)")

            Button(action: { appState.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!appState.canRedo)
            .help("Rétablir (⌘⇧Z)")

            Divider()

            // Delete current copy
            if appState.currentCopy != nil {
                Button(action: { appState.deleteCopy() }) {
                    Image(systemName: "trash")
                }
                .help("Supprimer la copie")
            }
        }
    }
}

#Preview {
    ToolbarButtons()
        .environment(AppState())
}
