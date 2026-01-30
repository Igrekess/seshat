import SwiftUI
import AppKit

struct TranscriptionView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedBoxId: UUID?
    @State private var showOverlay = true

    var body: some View {
        HSplitView {
            // Left: Image with overlay
            ImageWithOverlayView(
                selectedBoxId: $selectedBoxId,
                showOverlay: showOverlay
            )
            .frame(minWidth: 400)

            // Right: Transcription text
            TranscriptionTextView(selectedBoxId: $selectedBoxId)
                .frame(minWidth: 300)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: $showOverlay) {
                    Label("Overlay", systemImage: "square.on.square")
                }

                Divider()

                Button("Valider", systemImage: "checkmark.circle") {
                    appState.validateTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.transcriptionResult == nil)
            }
        }
    }
}

// MARK: - Image With Overlay View
struct ImageWithOverlayView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedBoxId: UUID?
    let showOverlay: Bool

    @State private var zoomScale: CGFloat = 1.0
    @State private var containerSize: CGSize = .zero

    /// Calculate the displayed image size based on container and aspect ratio
    private func displayedImageSize(for image: NSImage, in containerSize: CGSize) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            // Image is wider - fit to width
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Image is taller - fit to height
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let processedImage = appState.processedImage
            let baseSize = processedImage.map { displayedImageSize(for: $0, in: geometry.size) } ?? .zero
            let scaledSize = CGSize(width: baseSize.width * zoomScale, height: baseSize.height * zoomScale)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    if let processedImage = processedImage {
                        // Image with explicit frame (not scaleEffect)
                        Image(nsImage: processedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: scaledSize.width, height: scaledSize.height)

                        // Bounding box overlay - same size as image
                        if showOverlay, let transcription = appState.transcriptionResult {
                            BoundingBoxOverlay(
                                boxes: transcription.boundingBoxes,
                                selectedBoxId: $selectedBoxId,
                                sourceImageSize: CGSize(
                                    width: processedImage.size.width,
                                    height: processedImage.size.height
                                ),
                                displayedSize: scaledSize
                            )
                        }
                    }
                }
                .frame(
                    minWidth: max(geometry.size.width, scaledSize.width),
                    minHeight: max(geometry.size.height, scaledSize.height)
                )
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .onAppear { containerSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in containerSize = newSize }

            // Zoom controls
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZoomControls(scale: $zoomScale)
                        .padding()
                }
            }
        }
    }
}

// MARK: - Bounding Box Overlay
struct BoundingBoxOverlay: View {
    let boxes: [BoundingBox]
    @Binding var selectedBoxId: UUID?
    let sourceImageSize: CGSize   // Dimensions de l'image source en pixels
    let displayedSize: CGSize     // Dimensions affichées (avec zoom appliqué)

    var body: some View {
        // Calculer le ratio entre l'image source et l'image affichée
        let scaleX: CGFloat = displayedSize.width / max(sourceImageSize.width, 1)
        let scaleY: CGFloat = displayedSize.height / max(sourceImageSize.height, 1)

        Canvas { context, size in
            for box in boxes {
                let isSelected = selectedBoxId == box.id
                let color = colorForConfidence(box.confidence)

                // Convertir les coordonnées pixels vers les coordonnées d'affichage
                let displayRect = CGRect(
                    x: box.rect.origin.x * scaleX,
                    y: box.rect.origin.y * scaleY,
                    width: box.rect.width * scaleX,
                    height: box.rect.height * scaleY
                )

                // Dessiner le fond
                context.fill(
                    Path(displayRect),
                    with: .color(color.opacity(isSelected ? 0.3 : 0.15))
                )

                // Dessiner le contour
                context.stroke(
                    Path(displayRect),
                    with: .color(isSelected ? Color.accentColor : color),
                    lineWidth: isSelected ? 3 : 2
                )
            }
        }
        .frame(width: displayedSize.width, height: displayedSize.height)
        .contentShape(Rectangle())
        .onTapGesture { location in
            // Trouver quelle box a été cliquée
            let scaleX: CGFloat = displayedSize.width / max(sourceImageSize.width, 1)
            let scaleY: CGFloat = displayedSize.height / max(sourceImageSize.height, 1)

            for box in boxes {
                let displayRect = CGRect(
                    x: box.rect.origin.x * scaleX,
                    y: box.rect.origin.y * scaleY,
                    width: box.rect.width * scaleX,
                    height: box.rect.height * scaleY
                )
                if displayRect.contains(location) {
                    selectedBoxId = box.id
                    return
                }
            }
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

// MARK: - Transcription Text View
struct TranscriptionTextView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedBoxId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Transcription")
                    .font(.headline)

                Spacer()

                if let transcription = appState.transcriptionResult {
                    ConfidenceBadge(confidence: transcription.overallConfidence)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            // Text segments
            if let transcription = appState.transcriptionResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(transcription.boundingBoxes) { box in
                            TranscriptionSegmentRow(
                                box: box,
                                isSelected: selectedBoxId == box.id,
                                onSelect: { selectedBoxId = box.id },
                                onEdit: { newText in
                                    let updated = transcription.updating(box: box, with: newText)
                                    appState.updateTranscription(updated)
                                },
                                onDelete: {
                                    let updated = transcription.removing(box: box)
                                    appState.updateTranscription(updated)
                                    if selectedBoxId == box.id {
                                        selectedBoxId = nil
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Pas de transcription",
                    systemImage: "text.viewfinder",
                    description: Text("Lancez la transcription depuis l'écran d'import")
                )
            }
        }
    }
}

// MARK: - Native macOS Text View
struct NativeTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        textView.string = text

        // Force first responder after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }

        // Ensure the text view can become first responder
        if let window = nsView.window, window.firstResponder != textView {
            DispatchQueue.main.async {
                window.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextView

        init(_ parent: NativeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Transcription Segment Row
struct TranscriptionSegmentRow: View {
    let box: BoundingBox
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText: String = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Confidence indicator
            Circle()
                .fill(colorForConfidence(box.confidence))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    VStack(alignment: .leading, spacing: 8) {
                        NativeTextView(text: $editText)
                            .frame(minHeight: 60, maxHeight: 150)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )

                        HStack(spacing: 8) {
                            Button("Annuler") {
                                isEditing = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Valider") {
                                onEdit(editText)
                                isEditing = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                } else {
                    Text(box.text)
                        .foregroundColor(box.isEdited ? .orange : .primary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("\(Int(box.confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if box.isEdited {
                        Text("• Modifié")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            if !isEditing {
                HStack(spacing: 4) {
                    Button(action: {
                        editText = box.text
                        isEditing = true
                        onSelect()
                    }) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onSelect()
            }
        }
        .alert("Supprimer cette zone ?", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Cette zone de texte sera supprimée de la transcription.")
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

// MARK: - Edit Text Sheet
struct EditTextSheet: View {
    let initialText: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editText: String

    init(initialText: String, onSave: @escaping (String) -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self._editText = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Modifier le texte")
                .font(.headline)

            NativeTextView(text: $editText)
                .frame(minWidth: 400, minHeight: 150)
                .border(Color.secondary.opacity(0.3), width: 1)

            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Enregistrer") {
                    onSave(editText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500, height: 280)
    }
}

// MARK: - Confidence Badge
struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForConfidence(confidence))
                .frame(width: 8, height: 8)

            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorForConfidence(confidence).opacity(0.1))
        .cornerRadius(8)
    }

    private func colorForConfidence(_ confidence: Double) -> Color {
        switch confidence {
        case 0.7...: return .green
        case 0.5..<0.7: return .orange
        default: return .red
        }
    }
}

// MARK: - Zoom Controls
struct ZoomControls: View {
    @Binding var scale: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { scale = max(0.5, scale - 0.25) }) {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)

            Text("\(Int(scale * 100))%")
                .monospacedDigit()
                .frame(width: 50)

            Button(action: { scale = min(3.0, scale + 0.25) }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

#Preview {
    TranscriptionView()
        .environment(AppState())
}
