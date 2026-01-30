import SwiftUI

struct AnalysisView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedCategory: ErrorCategory?
    @State private var selectedError: LinguisticError?

    var body: some View {
        HSplitView {
            // Left: Image with error highlights
            AnalysisImageView(selectedError: $selectedError)
                .frame(minWidth: 400)

            // Right: Error list and details
            VStack(spacing: 0) {
                // Category filter
                CategoryFilterBar(selectedCategory: $selectedCategory)

                Divider()

                // Error list
                ErrorListView(
                    selectedCategory: selectedCategory,
                    selectedError: $selectedError
                )

                // Global feedback from teacher
                if appState.analysisResult?.globalFeedback != nil {
                    Divider()
                    GlobalFeedbackView()
                }

                Divider()

                // Summary footer
                AnalysisSummaryFooter()
            }
            .frame(minWidth: 350)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Exporter en PDF", systemImage: "square.and.arrow.up") {
                    appState.currentStep = .export
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.analysisResult == nil)
            }
        }
    }
}

// MARK: - Analysis Image View
struct AnalysisImageView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedError: LinguisticError?
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            if let processedImage = appState.processedImage {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            let imageSize = calculateImageSize(processedImage.size, in: geometry.size)

                            Image(nsImage: processedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: imageSize.width * zoomScale, height: imageSize.height * zoomScale)

                            // Error highlights on bounding boxes
                            ErrorHighlightsOverlay(
                                imageSize: imageSize,
                                zoomScale: zoomScale,
                                selectedError: selectedError
                            )
                        }
                    }
                }
            }

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
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func calculateImageSize(_ imageSize: NSSize, in containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }
}

// MARK: - Error Highlights Overlay
struct ErrorHighlightsOverlay: View {
    @Environment(AppState.self) private var appState
    let imageSize: CGSize
    let zoomScale: CGFloat
    let selectedError: LinguisticError?

    var body: some View {
        if let transcription = appState.transcriptionResult,
           let analysis = appState.analysisResult,
           let processedImage = appState.processedImage {

            let originalSize = processedImage.size
            let scaleX = (imageSize.width * zoomScale) / originalSize.width
            let scaleY = (imageSize.height * zoomScale) / originalSize.height

            ForEach(transcription.boundingBoxes) { box in
                let boxErrors = findErrors(in: box.text, from: analysis.errors)
                if !boxErrors.isEmpty {
                    let scaledRect = CGRect(
                        x: box.rect.origin.x * scaleX,
                        y: box.rect.origin.y * scaleY,
                        width: box.rect.width * scaleX,
                        height: box.rect.height * scaleY
                    )

                    // Get dominant error category color
                    let dominantCategory = boxErrors.first?.category ?? .grammar
                    let isSelected = boxErrors.contains { $0.id == selectedError?.id }

                    Rectangle()
                        .fill(Color(nsColor: NSColor(hex: dominantCategory.defaultColor) ?? .red)
                            .opacity(isSelected ? 0.4 : 0.2))
                        .overlay(
                            Rectangle()
                                .strokeBorder(
                                    Color(nsColor: NSColor(hex: dominantCategory.defaultColor) ?? .red),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        )
                        .frame(width: scaledRect.width, height: scaledRect.height)
                        .position(x: scaledRect.midX, y: scaledRect.midY)
                }
            }
        }
    }

    private func findErrors(in boxText: String, from errors: [LinguisticError]) -> [LinguisticError] {
        errors.filter { error in
            boxText.localizedCaseInsensitiveContains(error.text)
        }
    }
}

// MARK: - Category Filter Bar
struct CategoryFilterBar: View {
    @Binding var selectedCategory: ErrorCategory?
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryFilterChip(
                    title: "Toutes",
                    count: appState.analysisResult?.totalErrors ?? 0,
                    color: .gray,
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }

                ForEach(ErrorCategory.allCases, id: \.self) { category in
                    let count = appState.analysisResult?.errorCount(for: category) ?? 0
                    CategoryFilterChip(
                        title: category.displayName,
                        count: count,
                        color: Color(nsColor: NSColor(hex: category.defaultColor) ?? .gray),
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

// MARK: - Category Filter Chip
struct CategoryFilterChip: View {
    let title: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.caption)

                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.15) : Color.clear)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Error List View
struct ErrorListView: View {
    @Environment(AppState.self) private var appState
    let selectedCategory: ErrorCategory?
    @Binding var selectedError: LinguisticError?

    var filteredErrors: [LinguisticError] {
        guard let analysis = appState.analysisResult else { return [] }
        if let category = selectedCategory {
            return analysis.errors.filter { $0.category == category }
        }
        return analysis.errors
    }

    var body: some View {
        if filteredErrors.isEmpty {
            ContentUnavailableView(
                "Aucune erreur",
                systemImage: "checkmark.circle",
                description: Text(selectedCategory != nil ? "Aucune erreur dans cette catégorie" : "Le texte ne contient pas d'erreurs détectées")
            )
        } else {
            List(filteredErrors, selection: $selectedError) { error in
                ErrorRowView(error: error, isSelected: selectedError?.id == error.id)
                    .tag(error)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Error Row View
struct ErrorRowView: View {
    let error: LinguisticError
    let isSelected: Bool

    var categoryColor: Color {
        Color(nsColor: NSColor(hex: error.category.defaultColor) ?? .gray)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Category badge
                HStack(spacing: 4) {
                    Image(systemName: error.category.icon)
                        .font(.caption)
                    Text(error.category.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(categoryColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(categoryColor.opacity(0.1))
                .cornerRadius(6)

                Spacer()
            }

            // Error text
            HStack(spacing: 8) {
                Text(error.text)
                    .strikethrough()
                    .foregroundColor(.red)

                if let correction = error.correction {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(correction)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
            }

            // Explanation
            Text(error.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Global Feedback View
struct GlobalFeedbackView: View {
    @Environment(AppState.self) private var appState
    @State private var isExpanded = true

    var body: some View {
        if let feedback = appState.analysisResult?.globalFeedback {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    // Overall assessment
                    Text(feedback.overallAssessment)
                        .font(.body)
                        .foregroundColor(.primary)

                    // Strengths
                    if !feedback.strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Points forts", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)

                            ForEach(feedback.strengths, id: \.self) { strength in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(.green)
                                    Text(strength)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    // Areas for improvement
                    if !feedback.areasForImprovement.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Axes d'amélioration", systemImage: "arrow.up.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)

                            ForEach(feedback.areasForImprovement, id: \.self) { area in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(.orange)
                                    Text(area)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    // Encouragement
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text(feedback.encouragement)
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
            } label: {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.blue)
                    Text("Appréciation du professeur")
                        .font(.headline)

                    Spacer()

                    if let grade = feedback.suggestedGrade {
                        Text(grade)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// MARK: - Analysis Summary Footer
struct AnalysisSummaryFooter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let analysis = appState.analysisResult {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Résumé")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(analysis.totalErrors) erreur(s) détectée(s)")
                        .font(.headline)
                }

                Spacer()

                // Mini stats
                HStack(spacing: 16) {
                    ForEach(ErrorCategory.allCases, id: \.self) { category in
                        let count = analysis.errorCount(for: category)
                        if count > 0 {
                            VStack {
                                Text("\(count)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(nsColor: NSColor(hex: category.defaultColor) ?? .gray))

                                Text(category.displayName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(.bar)
        }
    }
}

#Preview {
    AnalysisView()
        .environment(AppState())
}
