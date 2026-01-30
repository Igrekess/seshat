import SwiftUI

/// Sidebar showing the structure of the test with drag-to-reorder
struct TestStructureSidebar: View {
    @Bindable var service: TestCreationService
    @Binding var selectedQuestionId: UUID?
    @Binding var selectedMode: ContentView.AppMode

    @State private var isEditingTitle = false
    @State private var editedTitle = ""

    @State private var showingSavedTests = true
    @State private var showingContextDocuments = true  // Expanded by default

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector
            Picker("Mode", selection: $selectedMode) {
                ForEach(ContentView.AppMode.allCases, id: \.self) { mode in
                    Label(mode.shortName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Saved tests section (at top)
            SavedTestsSectionView(service: service, showingSavedTests: $showingSavedTests)

            Divider()

            // Context documents section (only when session active)
            if service.currentSession != nil {
                ContextDocumentsSectionView(
                    service: service,
                    isExpanded: $showingContextDocuments
                )

                Divider()
            }

            // Test header
            if let session = service.currentSession {
                TestHeaderView(
                    test: session.testDraft,
                    isEditingTitle: $isEditingTitle,
                    editedTitle: $editedTitle,
                    onTitleChanged: { newTitle in
                        service.updateTestMetadata(title: newTitle)
                    },
                    onDurationChanged: { newDuration in
                        service.updateTestMetadata(duration: newDuration)
                    }
                )
                .padding()

                Divider()

                // Questions list
                if session.testDraft.questions.isEmpty {
                    EmptyQuestionsView()
                } else {
                    QuestionsList(
                        questions: session.testDraft.sortedQuestions,
                        selectedQuestionId: $selectedQuestionId,
                        onMove: service.moveQuestion,
                        onDelete: { id in
                            service.deleteQuestion(id)
                            if selectedQuestionId == id {
                                selectedQuestionId = nil
                            }
                        }
                    )
                }
            } else {
                // No session
                NoSessionView()
            }

            Spacer()

            Divider()

            // Bottom actions
            BottomActionsView(service: service)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    }
}

// MARK: - Test Header View

struct TestHeaderView: View {
    let test: Test
    @Binding var isEditingTitle: Bool
    @Binding var editedTitle: String
    var onTitleChanged: (String) -> Void
    var onDurationChanged: (Int?) -> Void

    @State private var isEditingDuration = false
    @State private var editedDuration: Int = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title (editable)
            if isEditingTitle {
                TextField("Titre", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        onTitleChanged(editedTitle)
                        isEditingTitle = false
                    }
            } else {
                HStack {
                    Text(test.title.isEmpty ? "Sans titre" : test.title)
                        .font(.headline)
                        .lineLimit(2)

                    Button {
                        editedTitle = test.title
                        isEditingTitle = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            // Metadata
            HStack(spacing: 8) {
                if !test.subject.isEmpty {
                    Label(test.subject, systemImage: "book")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !test.gradeLevel.isEmpty {
                    Label(test.gradeLevel, systemImage: "graduationcap")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Stats row
            HStack(spacing: 12) {
                Label("\(test.questions.count)", systemImage: "list.number")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label(String(format: "%.1f pts", test.calculatedTotalPoints), systemImage: "star")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Status badge
                TestStatusBadge(status: test.status)
            }

            // Duration row (editable)
            DurationEditorRow(
                duration: test.duration,
                isEditing: $isEditingDuration,
                editedDuration: $editedDuration,
                onDurationChanged: onDurationChanged
            )
        }
    }
}

// MARK: - Duration Editor Row

struct DurationEditorRow: View {
    let duration: Int?
    @Binding var isEditing: Bool
    @Binding var editedDuration: Int
    var onDurationChanged: (Int?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundColor(.secondary)

            if isEditing {
                Stepper(
                    "\(editedDuration) min",
                    value: $editedDuration,
                    in: 5...240,
                    step: 5
                )
                .font(.caption)
                .frame(maxWidth: 120)

                Button {
                    onDurationChanged(editedDuration)
                    isEditing = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                Button {
                    onDurationChanged(nil)
                    isEditing = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Supprimer la durée")
            } else {
                if let duration = duration {
                    Text("\(duration) min")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        editedDuration = duration
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                } else {
                    Button {
                        editedDuration = 60
                        isEditing = true
                    } label: {
                        Text("Ajouter durée")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
    }
}

struct TestStatusBadge: View {
    let status: TestStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
            Text(status.displayName)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(status == .ready ? Color.green.opacity(0.2) : Color.secondary.opacity(0.2))
        )
        .foregroundColor(status == .ready ? .green : .secondary)
    }
}

// MARK: - Questions List

struct QuestionsList: View {
    let questions: [Question]
    @Binding var selectedQuestionId: UUID?
    var onMove: (IndexSet, Int) -> Void
    var onDelete: (UUID) -> Void

    var body: some View {
        List(selection: $selectedQuestionId) {
            ForEach(questions) { question in
                QuestionRow(question: question)
                    .tag(question.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(question.id)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
            }
            .onMove { source, destination in
                onMove(source, destination)
            }
        }
        .listStyle(.sidebar)
    }
}

struct QuestionRow: View {
    let question: Question

    var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: question.type.icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)

            // Question preview
            VStack(alignment: .leading, spacing: 2) {
                Text(question.text.isEmpty ? "Question vide" : question.text)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundColor(question.text.isEmpty ? .secondary : .primary)

                HStack(spacing: 8) {
                    // Difficulty
                    if let difficulty = question.difficultyLevel {
                        Text(difficulty.displayName)
                            .font(.caption2)
                            .foregroundColor(Color(hex: difficulty.color) ?? .gray)
                    }

                    // Points
                    Text("\(String(format: "%.1f", question.points)) pt")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty States

struct EmptyQuestionsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("Aucune question")
                .font(.callout)
                .foregroundColor(.secondary)

            Text("Utilisez le chat pour\ngénérer des questions")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct NoSessionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("Pas de test en cours")
                .font(.callout)
                .foregroundColor(.secondary)

            Text("Créez un nouveau test\npour commencer")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Bottom Actions

struct BottomActionsView: View {
    @Bindable var service: TestCreationService
    @State private var showingExportOptions = false

    var body: some View {
        VStack(spacing: 8) {
            if service.currentSession != nil {
                HStack(spacing: 8) {
                    Button {
                        service.finalizeTest()
                    } label: {
                        Label("Prêt", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.currentSession?.testDraft.questions.isEmpty ?? true)

                    Button {
                        showingExportOptions = true
                    } label: {
                        Image(systemName: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                    .help("Exporter en PDF")
                    .disabled(service.currentSession?.testDraft.questions.isEmpty ?? true)
                }
            }

            Button {
                service.clearSession()
            } label: {
                Label("Nouveau test", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .sheet(isPresented: $showingExportOptions) {
            if let test = service.currentSession?.testDraft {
                PDFExportOptionsSheet(test: test, isPresented: $showingExportOptions)
            }
        }
    }
}

// MARK: - Saved Tests Section (Top of Sidebar)

struct SavedTestsSectionView: View {
    @Bindable var service: TestCreationService
    @Binding var showingSavedTests: Bool
    @State private var savedTests: [Test] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header with toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSavedTests.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                    Text("Tests sauvegardés")
                        .font(.caption)
                        .fontWeight(.medium)

                    if !savedTests.isEmpty {
                        Text("(\(savedTests.count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: showingSavedTests ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if showingSavedTests {
                if savedTests.isEmpty {
                    Text("Aucun test sauvegardé")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 2) {
                        ForEach(savedTests.prefix(8)) { test in
                            SavedTestRow(
                                test: test,
                                isCurrentTest: service.currentSession?.testDraft.id == test.id,
                                onLoad: {
                                    service.loadTest(test.id)
                                },
                                onDelete: {
                                    service.deleteSavedTest(test.id)
                                    refreshTests()
                                },
                                onExport: {
                                    TestPDFExportService.shared.exportWithSavePanel(test)
                                }
                            )
                        }

                        if savedTests.count > 8 {
                            Text("+ \(savedTests.count - 8) autres tests")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .onAppear {
            refreshTests()
        }
    }

    private func refreshTests() {
        savedTests = service.getSavedTests()
    }
}

// MARK: - PDF Export Options Sheet

struct PDFExportOptionsSheet: View {
    let test: Test
    @Binding var isPresented: Bool
    @State private var includeStudentFields = true
    @State private var includePoints = true
    @State private var includeAnswers = false
    @State private var includeRubric = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Options d'export PDF")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Champs élève (nom, prénom, classe, date)", isOn: $includeStudentFields)
                Toggle("Afficher les points par question", isOn: $includePoints)

                Divider()

                Text("Version corrigée")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Inclure les réponses correctes", isOn: $includeAnswers)
                Toggle("Inclure les critères de notation", isOn: $includeRubric)
                    .disabled(!includeAnswers)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )

            HStack {
                Button("Annuler") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Exporter") {
                    TestPDFExportService.shared.exportWithSavePanel(
                        test,
                        options: PDFExportOptions(
                            includeAnswers: includeAnswers,
                            includePoints: includePoints,
                            includeRubric: includeRubric,
                            includeStudentFields: includeStudentFields
                        )
                    )
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 380)
    }
}


struct SavedTestRow: View {
    let test: Test
    let isCurrentTest: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            if !isCurrentTest {
                onLoad()
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(test.title.isEmpty ? "Sans titre" : test.title)
                        .font(.caption)
                        .fontWeight(isCurrentTest ? .semibold : .regular)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if !test.subject.isEmpty {
                            Text(test.subject)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }

                        if !test.gradeLevel.isEmpty {
                            Text(test.gradeLevel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("\(test.questions.count) Q")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if test.status == .ready {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                if isCurrentTest {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrentTest ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if !isCurrentTest {
                Button {
                    onLoad()
                } label: {
                    Label("Charger ce test", systemImage: "arrow.up.doc")
                }

                Divider()
            }

            Button {
                onExport()
            } label: {
                Label("Exporter en PDF", systemImage: "arrow.down.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}

#Preview {
    TestStructureSidebar(
        service: TestCreationService.shared,
        selectedQuestionId: .constant(nil),
        selectedMode: .constant(.createTest)
    )
}
