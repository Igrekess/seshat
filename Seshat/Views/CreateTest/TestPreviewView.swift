import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Preview of the complete test
struct TestPreviewView: View {
    let test: Test

    @State private var showingExportOptions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                TestPreviewHeader(test: test)

                Divider()

                // Questions
                ForEach(Array(test.sortedQuestions.enumerated()), id: \.element.id) { index, question in
                    QuestionPreviewCard(question: question, number: index + 1)
                }

                // Summary
                TestSummaryCard(test: test)
            }
            .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingExportOptions = true
                } label: {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }

                Button {
                    printTest()
                } label: {
                    Label("Imprimer", systemImage: "printer")
                }
            }
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsSheet(test: test)
        }
    }

    private func printTest() {
        // Create temporary PDF using the export service
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seshat_print_\(UUID().uuidString).pdf")

        do {
            try TestPDFExportService.shared.exportToPDF(test, to: tempURL, options: .default)

            guard let pdfDoc = PDFDocument(url: tempURL) else { return }

            let printInfo = NSPrintInfo.shared
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .fit
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = true

            let printOp = pdfDoc.printOperation(for: printInfo, scalingMode: .pageScaleDownToFit, autoRotate: true)
            printOp?.showsPrintPanel = true
            printOp?.run()

            // Clean up temp file after printing
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            // Silently fail
        }
    }
}

// MARK: - Preview Header

struct TestPreviewHeader: View {
    let test: Test

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(test.title.isEmpty ? "Sans titre" : test.title)
                .font(.largeTitle)
                .fontWeight(.bold)

            // Metadata row
            HStack(spacing: 16) {
                if !test.subject.isEmpty {
                    Label(test.subject, systemImage: "book.fill")
                        .foregroundColor(.secondary)
                }

                if !test.gradeLevel.isEmpty {
                    Label(test.gradeLevel, systemImage: "graduationcap.fill")
                        .foregroundColor(.secondary)
                }

                Label(
                    "\(test.questions.count) question\(test.questions.count > 1 ? "s" : "")",
                    systemImage: "list.number"
                )
                .foregroundColor(.secondary)

                Label(
                    String(format: "%.1f points", test.calculatedTotalPoints),
                    systemImage: "star.fill"
                )
                .foregroundColor(.secondary)
            }
            .font(.callout)

            // Description
            if !test.description.isEmpty {
                Text(test.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.1))
        )
    }
}

// MARK: - Question Preview Card

struct QuestionPreviewCard: View {
    let question: Question
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Question \(number)")
                    .font(.headline)

                Spacer()

                // Type badge
                Label(question.type.displayName, systemImage: question.type.icon)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.2))
                    )

                // Difficulty badge
                if let difficulty = question.difficultyLevel {
                    let diffColor = Color(hex: difficulty.color) ?? .gray
                    Text(difficulty.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(diffColor.opacity(0.2))
                        )
                        .foregroundColor(diffColor)
                }

                // Points
                Text("\(String(format: "%.1f", question.points)) pt")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Question text
            Text(question.text)
                .font(.body)

            // Type-specific content
            switch question.type {
            case .multipleChoice:
                MCQPreview(options: question.options ?? [])

            case .trueFalse:
                TrueFalsePreview(correctAnswer: question.correctAnswer ?? true)

            case .openEnded:
                OpenEndedPreview(
                    expectedAnswer: question.expectedAnswer,
                    rubric: question.rubricGuidelines
                )

            case .shortAnswer:
                ShortAnswerPreview(expectedAnswer: question.expectedAnswer)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Type-Specific Previews

struct MCQPreview: View {
    let options: [MCQOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                HStack(spacing: 8) {
                    Text("\(String(UnicodeScalar(65 + index)!)).")
                        .fontWeight(.medium)
                        .frame(width: 20)

                    Text(option.text)

                    if option.isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(option.isCorrect ? Color.green.opacity(0.1) : Color.clear)
                )
            }
        }
    }
}

struct TrueFalsePreview: View {
    let correctAnswer: Bool

    var body: some View {
        HStack(spacing: 16) {
            Label("Vrai", systemImage: correctAnswer ? "checkmark.circle.fill" : "circle")
                .foregroundColor(correctAnswer ? .green : .secondary)

            Label("Faux", systemImage: !correctAnswer ? "checkmark.circle.fill" : "circle")
                .foregroundColor(!correctAnswer ? .green : .secondary)
        }
        .padding(.vertical, 4)
    }
}

struct OpenEndedPreview: View {
    let expectedAnswer: String?
    let rubric: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let expected = expectedAnswer, !expected.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Réponse attendue:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(expected)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
            }

            if let rubric = rubric, !rubric.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Critères de notation:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(rubric)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
    }
}

struct ShortAnswerPreview: View {
    let expectedAnswer: String?

    var body: some View {
        if let expected = expectedAnswer, !expected.isEmpty {
            HStack {
                Text("Réponse attendue:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(expected)
                    .font(.callout)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
    }
}

// MARK: - Summary Card

struct TestSummaryCard: View {
    let test: Test

    private var mcqCount: Int {
        test.questions.filter { $0.type == .multipleChoice }.count
    }

    private var openEndedCount: Int {
        test.questions.filter { $0.type == .openEnded }.count
    }

    private var trueFalseCount: Int {
        test.questions.filter { $0.type == .trueFalse }.count
    }

    private var shortAnswerCount: Int {
        test.questions.filter { $0.type == .shortAnswer }.count
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Résumé")
                .font(.headline)

            statsGrid

            difficultyDistribution
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var statsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            TestStatItem(
                label: "Questions",
                value: "\(test.questions.count)",
                icon: "list.number"
            )

            TestStatItem(
                label: "Points totaux",
                value: String(format: "%.1f", test.calculatedTotalPoints),
                icon: "star.fill"
            )

            TestStatItem(
                label: "QCM",
                value: "\(mcqCount)",
                icon: "list.bullet.circle"
            )

            TestStatItem(
                label: "Questions ouvertes",
                value: "\(openEndedCount)",
                icon: "text.alignleft"
            )

            TestStatItem(
                label: "Vrai/Faux",
                value: "\(trueFalseCount)",
                icon: "checkmark.circle"
            )

            TestStatItem(
                label: "Réponses courtes",
                value: "\(shortAnswerCount)",
                icon: "text.cursor"
            )
        }
    }

    @ViewBuilder
    private var difficultyDistribution: some View {
        if !test.questions.isEmpty {
            Divider()

            Text("Distribution des difficultés")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                ForEach(DifficultyLevel.allCases) { level in
                    DifficultyCountLabel(
                        level: level,
                        count: test.questions.filter { $0.difficultyLevel == level }.count
                    )
                }
            }
        }
    }
}

struct DifficultyCountLabel: View {
    let level: DifficultyLevel
    let count: Int

    private var levelColor: Color {
        Color(hex: level.color) ?? .gray
    }

    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Circle()
                    .fill(levelColor)
                    .frame(width: 8, height: 8)
                Text("\(level.displayName): \(count)")
                    .font(.caption)
            }
        }
    }
}

struct TestStatItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
        )
    }
}

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    let test: Test
    @Environment(\.dismiss) private var dismiss

    @State private var includeStudentFields = true
    @State private var includePoints = true
    @State private var includeAnswers = false
    @State private var includeRubric = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Format d'export") {
                    Button {
                        exportAsPDF()
                    } label: {
                        Label("PDF (pour impression)", systemImage: "doc.fill")
                    }

                    Button {
                        exportAsJSON()
                    } label: {
                        Label("JSON (sauvegarde)", systemImage: "doc.text.fill")
                    }

                    Button {
                        exportAsMarkdown()
                    } label: {
                        Label("Markdown", systemImage: "text.document")
                    }
                }

                Section {
                    Toggle("Champs élève (nom, prénom, classe, date)", isOn: $includeStudentFields)
                    Toggle("Afficher les points", isOn: $includePoints)
                } header: {
                    Text("Options PDF")
                }

                Section {
                    Toggle("Inclure les réponses", isOn: $includeAnswers)
                    Toggle("Inclure les critères de notation", isOn: $includeRubric)
                        .disabled(!includeAnswers)
                } header: {
                    Text("Version corrigée")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Exporter le test")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }

    private func exportAsPDF() {
        let options = PDFExportOptions(
            includeAnswers: includeAnswers,
            includePoints: includePoints,
            includeRubric: includeRubric,
            includeStudentFields: includeStudentFields
        )
        TestPDFExportService.shared.exportWithSavePanel(test, options: options)
        dismiss()
    }

    private func exportAsJSON() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = test.title.sanitizedForFilename + ".json"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(test)
                try data.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                // Silently fail
            }
        }
        dismiss()
    }

    private func exportAsMarkdown() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = test.title.sanitizedForFilename + ".md"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let markdown = generateMarkdown()
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            } catch {
                // Silently fail
            }
        }
        dismiss()
    }

    private func generateMarkdown() -> String {
        var md = "# \(test.title.isEmpty ? "Sans titre" : test.title)\n\n"

        if !test.subject.isEmpty || !test.gradeLevel.isEmpty {
            var meta: [String] = []
            if !test.subject.isEmpty { meta.append("**Matière:** \(test.subject)") }
            if !test.gradeLevel.isEmpty { meta.append("**Niveau:** \(test.gradeLevel)") }
            md += meta.joined(separator: " | ") + "\n\n"
        }

        if !test.description.isEmpty {
            md += "> \(test.description)\n\n"
        }

        md += "---\n\n"

        for (index, question) in test.sortedQuestions.enumerated() {
            let num = index + 1
            if includePoints {
                md += "## Question \(num) (\(String(format: "%.1f", question.points)) pt)\n\n"
            } else {
                md += "## Question \(num)\n\n"
            }

            md += "\(question.text)\n\n"

            switch question.type {
            case .multipleChoice:
                if let options = question.options {
                    let labels = ["A", "B", "C", "D", "E", "F"]
                    for (i, option) in options.enumerated() {
                        let label = i < labels.count ? labels[i] : "\(i + 1)"
                        let marker = (includeAnswers && option.isCorrect) ? "- [x]" : "- [ ]"
                        md += "\(marker) **\(label).** \(option.text)\n"
                    }
                }

            case .trueFalse:
                if includeAnswers, let correct = question.correctAnswer {
                    md += "- [\(correct ? "x" : " ")] Vrai\n"
                    md += "- [\(!correct ? "x" : " ")] Faux\n"
                } else {
                    md += "- [ ] Vrai\n- [ ] Faux\n"
                }

            case .shortAnswer, .openEnded:
                if includeAnswers, let expected = question.expectedAnswer, !expected.isEmpty {
                    md += "*Réponse attendue:* \(expected)\n"
                } else {
                    md += "_____________________________\n"
                }

                if includeRubric, let rubric = question.rubricGuidelines, !rubric.isEmpty {
                    md += "\n*Critères:* \(rubric)\n"
                }
            }

            md += "\n"
        }

        if includePoints {
            md += "---\n\n**Total: \(String(format: "%.1f", test.calculatedTotalPoints)) points**\n"
        }

        return md
    }

}

#Preview {
    TestPreviewView(test: Test(
        title: "Test d'anglais - Verbes irréguliers",
        description: "Évaluation sur les 50 verbes irréguliers les plus courants",
        subject: "Anglais",
        gradeLevel: "Seconde",
        questions: [
            Question(
                type: .multipleChoice,
                text: "Quelle est la forme au passé simple de 'go'?",
                points: 1,
                options: [
                    MCQOption(text: "goed", isCorrect: false),
                    MCQOption(text: "went", isCorrect: true),
                    MCQOption(text: "gone", isCorrect: false),
                    MCQOption(text: "going", isCorrect: false)
                ],
                difficultyLevel: .easy,
                order: 0
            ),
            Question(
                type: .trueFalse,
                text: "'Bought' est le participe passé de 'buy'.",
                points: 1,
                correctAnswer: true,
                difficultyLevel: .easy,
                order: 1
            ),
            Question(
                type: .openEnded,
                text: "Conjuguez le verbe 'to be' au passé simple pour tous les pronoms personnels.",
                points: 3,
                expectedAnswer: "I was, you were, he/she/it was, we were, they were",
                rubricGuidelines: "1 point par forme correcte, -0.5 pour les fautes d'orthographe",
                difficultyLevel: .medium,
                order: 2
            )
        ]
    ))
}
