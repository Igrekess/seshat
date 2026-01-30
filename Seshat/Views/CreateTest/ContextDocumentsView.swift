import SwiftUI
import AppKit

/// Section for managing context documents (text and images with OCR)
struct ContextDocumentsSectionView: View {
    @Bindable var service: TestCreationService
    @Binding var isExpanded: Bool

    @State private var isLoadingDocument = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var documents: [DocumentContext] {
        service.currentSession?.contextDocuments ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "doc.text.image")
                        .foregroundColor(.secondary)
                    Text("Contexte")
                        .font(.caption)
                        .fontWeight(.medium)

                    if !documents.isEmpty {
                        Text("(\(documents.count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if service.currentSession?.hasProcessingDocuments == true {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(spacing: 8) {
                    if documents.isEmpty {
                        EmptyContextView(onAddDocument: addDocuments)
                    } else {
                        // Token usage indicator
                        TokenUsageIndicator(
                            currentTokens: service.totalContextTokens,
                            maxTokens: 4000
                        )
                        .padding(.horizontal, 8)

                        // Document list
                        VStack(spacing: 4) {
                            ForEach(documents) { doc in
                                ContextDocumentRow(
                                    document: doc,
                                    onDelete: {
                                        service.removeContextDocument(doc.id)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 8)

                        // Add more button
                        AddContextButton(
                            onAddDocument: addDocuments,
                            isLoading: isLoadingDocument
                        )
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .alert("Erreur", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Une erreur est survenue")
        }
    }

    private func addDocuments() {
        guard let urls = DocumentContextService.shared.showAllFilesPicker() else {
            return
        }

        isLoadingDocument = true

        Task {
            do {
                try await service.addDocuments(from: urls)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            await MainActor.run {
                isLoadingDocument = false
            }
        }
    }
}

// MARK: - Empty Context View

struct EmptyContextView: View {
    let onAddDocument: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Ajoutez des documents de cours")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Photos, PDF, textes...")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button {
                onAddDocument()
            } label: {
                Label("Ajouter", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Token Usage Indicator

struct TokenUsageIndicator: View {
    let currentTokens: Int
    let maxTokens: Int

    private var usageRatio: Double {
        min(Double(currentTokens) / Double(maxTokens), 1.0)
    }

    private var color: Color {
        if usageRatio > 0.9 {
            return .red
        } else if usageRatio > 0.7 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Contexte")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(currentTokens) / \(maxTokens) tokens")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * usageRatio, height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Context Document Row

struct ContextDocumentRow: View {
    let document: DocumentContext
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showingPreview = false

    var body: some View {
        HStack(spacing: 8) {
            // Icon based on type
            Group {
                if document.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: document.sourceType == .image ? "photo" : "doc.text")
                        .font(.caption)
                        .foregroundColor(document.sourceType == .image ? .purple : .blue)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.filename)
                    .font(.caption)
                    .lineLimit(1)

                if document.isProcessing {
                    Text("OCR en cours...")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    HStack(spacing: 4) {
                        Text("\(document.wordCount) mots")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if document.sourceType == .image {
                            Text("(OCR)")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    }
                }
            }

            Spacer()

            // Preview button for images
            if document.sourceType == .image && document.originalImageData != nil && !document.isProcessing {
                Button {
                    showingPreview = true
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            // Delete button (visible on hover)
            if isHovered {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .sheet(isPresented: $showingPreview) {
            ContextDocumentPreview(document: document)
        }
    }
}

// MARK: - Add Context Button

struct AddContextButton: View {
    let onAddDocument: () -> Void
    let isLoading: Bool

    var body: some View {
        Button {
            onAddDocument()
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "plus.circle")
                }
                Text("Ajouter document")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isLoading)
    }
}

// MARK: - Context Document Preview

struct ContextDocumentPreview: View {
    let document: DocumentContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(document.filename)
                        .font(.headline)
                    Text("\(document.wordCount) mots extraits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Fermer") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Content
            HSplitView {
                // Image preview (if available)
                if let imageData = document.originalImageData,
                   let nsImage = NSImage(data: imageData) {
                    VStack {
                        Text("Image originale")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(0.1))
                    }
                    .frame(minWidth: 300)
                }

                // Extracted text
                VStack(alignment: .leading) {
                    Text("Texte extrait (OCR)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(document.content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
                .frame(minWidth: 300)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

#Preview {
    ContextDocumentsSectionView(
        service: TestCreationService.shared,
        isExpanded: .constant(true)
    )
    .frame(width: 280)
}
