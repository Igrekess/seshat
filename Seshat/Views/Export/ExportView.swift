import SwiftUI
import PDFKit

struct ExportView: View {
    @Environment(AppState.self) private var appState
    @State private var exportOptions = ExportOptions()
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var showExportSuccess = false
    @State private var exportedFormat: String = "PDF"

    var body: some View {
        HSplitView {
            // Left: PDF Preview
            PDFPreviewView()
                .frame(minWidth: 400)

            // Right: Export options
            ExportOptionsPanel(
                options: $exportOptions,
                isExporting: $isExporting,
                onExportPDF: performExport,
                onExportTXT: performTXTExport
            )
            .frame(width: 300)
        }
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
                Text("Le fichier \(exportedFormat) a été enregistré dans:\n\(url.path)")
            }
        }
    }

    private func performExport() {
        guard let copy = appState.currentCopy,
              let transcription = appState.transcriptionResult,
              let analysis = appState.analysisResult else {
            return
        }

        isExporting = true

        Task {
            do {
                // Show save panel
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = "\(copy.originalFilename)_corrected.pdf"

                if panel.runModal() == .OK, let url = panel.url {
                    var options = exportOptions
                    options.destinationURL = url

                    let resultURL = try await appState.pdfExportService.exportToPDF(
                        copy: copy,
                        transcription: transcription,
                        analysis: analysis,
                        options: options,
                        processedImage: appState.processedImage
                    )

                    await MainActor.run {
                        exportedURL = resultURL
                        exportedFormat = "PDF"
                        showExportSuccess = true
                        isExporting = false
                    }
                } else {
                    await MainActor.run {
                        isExporting = false
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    appState.currentError = .exportFailed(path: error.localizedDescription)
                    appState.showErrorAlert = true
                }
            }
        }
    }

    private func performTXTExport() {
        guard let copy = appState.currentCopy,
              let transcription = appState.transcriptionResult else {
            return
        }

        isExporting = true

        // Show save panel
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let baseName = (copy.originalFilename as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName)_transcription.txt"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try transcription.fullText.write(to: url, atomically: true, encoding: .utf8)
                exportedURL = url
                exportedFormat = "TXT"
                showExportSuccess = true
            } catch {
                appState.currentError = .exportFailed(path: error.localizedDescription)
                appState.showErrorAlert = true
            }
        }

        isExporting = false
    }
}

// MARK: - PDF Preview View
struct PDFPreviewView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            Text("Aperçu du PDF")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)

            Divider()

            // Preview content
            ScrollView {
                VStack(spacing: 20) {
                    // Page 1: Image preview
                    PreviewPageView(pageNumber: 1, title: "Copie annotée") {
                        if let processedImage = appState.processedImage {
                            Image(nsImage: processedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .overlay(
                                    // Simulated annotations
                                    AnnotationOverlayPreview()
                                )
                        }
                    }

                    // Page 2: Statistics preview
                    PreviewPageView(pageNumber: 2, title: "Récapitulatif") {
                        StatisticsPreview()
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - Preview Page View
struct PreviewPageView<Content: View>: View {
    let pageNumber: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            Text("Page \(pageNumber) - \(title)")
                .font(.caption)
                .foregroundColor(.secondary)

            content
                .frame(maxWidth: 400, maxHeight: 500)
                .background(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Annotation Overlay Preview
struct AnnotationOverlayPreview: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { geometry in
            if let analysis = appState.analysisResult {
                ForEach(analysis.errors.prefix(5)) { error in
                    Rectangle()
                        .fill(Color(nsColor: NSColor(hex: error.category.defaultColor) ?? .red).opacity(0.3))
                        .frame(width: 80, height: 20)
                        .position(
                            x: CGFloat.random(in: 50...geometry.size.width - 50),
                            y: CGFloat.random(in: 50...geometry.size.height - 50)
                        )
                }
            }
        }
    }
}

// MARK: - Statistics Preview
struct StatisticsPreview: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Récapitulatif de la correction")
                .font(.headline)

            if let transcription = appState.transcriptionResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(transcription.fullText)
                        .font(.caption)
                        .lineLimit(5)
                }
            }

            Divider()

            if let analysis = appState.analysisResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Erreurs détectées")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(ErrorCategory.allCases, id: \.self) { category in
                        let count = analysis.errorCount(for: category)
                        HStack {
                            Circle()
                                .fill(Color(nsColor: NSColor(hex: category.defaultColor) ?? .gray))
                                .frame(width: 8, height: 8)
                            Text(category.displayName)
                            Spacer()
                            Text("\(count)")
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                    }

                    Divider()

                    HStack {
                        Text("Total")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(analysis.totalErrors)")
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Text("Généré par Seshat")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Export Options Panel
struct ExportOptionsPanel: View {
    @Binding var options: ExportOptions
    @Binding var isExporting: Bool
    let onExportPDF: () -> Void
    let onExportTXT: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Options d'export")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)

            Divider()

            Form {
                Section("Contenu PDF") {
                    Toggle("Image originale annotée", isOn: $options.includeOriginalImage)
                    Toggle("Transcription", isOn: $options.includeTranscription)
                    Toggle("Statistiques des erreurs", isOn: $options.includeStatistics)
                    Toggle("Légende des couleurs", isOn: $options.includeLegend)
                }
            }
            .formStyle(.grouped)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onExportPDF) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "doc.richtext")
                        }
                        Text(isExporting ? "Export en cours..." : "Exporter en PDF")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isExporting)

                Button(action: onExportTXT) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Exporter le texte (TXT)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isExporting)

                Text("Les fichiers seront enregistrés à l'emplacement de votre choix")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

#Preview {
    ExportView()
        .environment(AppState())
}
