import SwiftUI
import UniformTypeIdentifiers

struct ValidationView: View {
    @Environment(AppState.self) private var appState
    @State private var viewMode: ValidationViewMode = .sideBySide
    @State private var showExportSuccess = false
    @State private var exportedURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector toolbar
            HStack {
                Picker("Mode", selection: $viewMode) {
                    ForEach(ValidationViewMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { appState.undo() }) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!appState.canUndo)
                    .keyboardShortcut("z", modifiers: .command)

                    Button(action: { appState.redo() }) {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!appState.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])

                    Divider()
                        .frame(height: 20)

                    Button("Exporter TXT", systemImage: "doc.text") {
                        exportToTXT()
                    }
                    .buttonStyle(.bordered)

                    Button("Lancer l'analyse", systemImage: "magnifyingglass") {
                        Task {
                            await appState.startAnalysis()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.bar)
            .alert("Export réussi", isPresented: $showExportSuccess) {
                Button("Ouvrir le fichier") {
                    if let url = exportedURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Afficher dans le Finder") {
                    if let url = exportedURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                if let url = exportedURL {
                    Text("Le fichier TXT a été enregistré dans:\n\(url.path)")
                }
            }

            Divider()

            // Content based on view mode
            switch viewMode {
            case .sideBySide:
                SideBySideValidationView()
            case .textOnly:
                TextOnlyValidationView()
            }
        }
    }

    private func exportToTXT() {
        guard let copy = appState.currentCopy,
              let transcription = appState.transcriptionResult else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let baseName = (copy.originalFilename as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName)_transcription.txt"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try transcription.fullText.write(to: url, atomically: true, encoding: .utf8)
                exportedURL = url
                showExportSuccess = true
            } catch {
                appState.currentError = .exportFailed(path: error.localizedDescription)
                appState.showErrorAlert = true
            }
        }
    }
}

// MARK: - View Mode
enum ValidationViewMode: String, CaseIterable {
    case sideBySide
    case textOnly

    var title: String {
        switch self {
        case .sideBySide: return "Côte à côte"
        case .textOnly: return "Texte seul"
        }
    }

    var icon: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .textOnly: return "doc.text"
        }
    }
}

// MARK: - Side By Side View
struct SideBySideValidationView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedBoxId: UUID?

    var body: some View {
        HSplitView {
            // Image panel
            VStack(alignment: .leading, spacing: 0) {
                Text("Image traitée")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if let processedImage = appState.processedImage {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: processedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
            }
            .frame(minWidth: 300)

            // Text panel
            VStack(alignment: .leading, spacing: 0) {
                Text("Transcription validée")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if let transcription = appState.transcriptionResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(transcription.boundingBoxes) { box in
                                EditableTextSegment(
                                    box: box,
                                    isSelected: selectedBoxId == box.id,
                                    onSelect: { selectedBoxId = box.id },
                                    onEdit: { newText in
                                        let updated = transcription.updating(box: box, with: newText)
                                        appState.updateTranscription(updated)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(minWidth: 300)
        }
    }
}

// MARK: - Editable Text Segment
struct EditableTextSegment: View {
    let box: BoundingBox
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: (String) -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .onSubmit {
                    if editText != box.text {
                        onEdit(editText)
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused && editText != box.text {
                        onEdit(editText)
                    }
                }

            HStack(spacing: 8) {
                Circle()
                    .fill(colorForConfidence(box.confidence))
                    .frame(width: 6, height: 6)

                Text("\(Int(box.confidence * 100))% confiance")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if box.isEdited {
                    Text("• Modifié")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            onSelect()
            isFocused = true
        }
        .onAppear {
            editText = box.text
        }
    }

    private func colorForConfidence(_ confidence: Double) -> Color {
        switch confidence {
        case 0.7...: return .green
        case 0.5..<0.7: return .orange
        default: return .red
        }
    }
}

// MARK: - Text Only Validation View
struct TextOnlyValidationView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            if let transcription = appState.transcriptionResult {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Texte complet")
                        .font(.headline)

                    Text(transcription.fullText)
                        .font(.body)
                        .textSelection(.enabled)

                    Divider()

                    // Statistics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Statistiques")
                            .font(.headline)

                        LabeledContent("Segments", value: "\(transcription.boundingBoxes.count)")
                        LabeledContent("Confiance moyenne", value: "\(Int(transcription.overallConfidence * 100))%")
                        LabeledContent("Segments modifiés", value: "\(transcription.editedBoxes.count)")
                        LabeledContent("Segments faible confiance", value: "\(transcription.lowConfidenceBoxes.count)")
                    }
                }
                .padding()
            }
        }
    }
}

#Preview {
    ValidationView()
        .environment(AppState())
}
