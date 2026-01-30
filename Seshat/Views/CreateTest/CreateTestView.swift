import SwiftUI

/// Main container view for the Create Test mode
struct CreateTestView: View {
    @Bindable private var service = TestCreationService.shared
    @Binding var modeBinding: ContentView.AppMode

    @State private var selectedQuestionId: UUID?
    @State private var showingSetupSheet = false
    @State private var configuration = TestConfiguration()
    @State private var rightPanelMode: RightPanelMode = .chat

    enum RightPanelMode {
        case chat
        case editor
        case preview
    }

    var body: some View {
        NavigationSplitView {
            // Left sidebar - Test structure
            TestStructureSidebar(
                service: service,
                selectedQuestionId: $selectedQuestionId,
                selectedMode: $modeBinding
            )
        } content: {
            // Center - Chat interface
            VStack(spacing: 0) {
                // Panel mode selector
                Picker("Panneau", selection: $rightPanelMode) {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                        .tag(RightPanelMode.chat)
                    Label("Éditeur", systemImage: "pencil")
                        .tag(RightPanelMode.editor)
                    Label("Aperçu", systemImage: "eye")
                        .tag(RightPanelMode.preview)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Content based on mode
                Group {
                    switch rightPanelMode {
                    case .chat:
                        if service.currentSession != nil {
                            ChatInterfaceView(service: service)
                        } else {
                            NoSessionChatView(onNewTest: { showingSetupSheet = true })
                        }

                    case .editor:
                        if let questionId = selectedQuestionId,
                           let question = service.currentSession?.testDraft.questions.first(where: { $0.id == questionId }) {
                            QuestionEditorView(
                                question: Binding(
                                    get: {
                                        service.currentSession?.testDraft.questions.first(where: { $0.id == questionId }) ?? question
                                    },
                                    set: { service.updateQuestion($0) }
                                ),
                                onDelete: {
                                    service.deleteQuestion(questionId)
                                    selectedQuestionId = nil
                                    rightPanelMode = .chat
                                },
                                onDuplicate: {
                                    if let idx = service.currentSession?.testDraft.questions.firstIndex(where: { $0.id == questionId }) {
                                        duplicateQuestion(at: idx)
                                    }
                                }
                            )
                        } else {
                            NoQuestionSelectedView()
                        }

                    case .preview:
                        if let session = service.currentSession {
                            TestPreviewView(test: session.testDraft)
                        } else {
                            NoSessionPreviewView()
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 500, max: .infinity)
        } detail: {
            // Right panel - Question editor or preview (when in chat mode)
            if rightPanelMode == .chat {
                if let questionId = selectedQuestionId,
                   let question = service.currentSession?.testDraft.questions.first(where: { $0.id == questionId }) {
                    QuestionEditorView(
                        question: Binding(
                            get: {
                                service.currentSession?.testDraft.questions.first(where: { $0.id == questionId }) ?? question
                            },
                            set: { service.updateQuestion($0) }
                        ),
                        onDelete: {
                            service.deleteQuestion(questionId)
                            selectedQuestionId = nil
                        },
                        onDuplicate: {
                            if let idx = service.currentSession?.testDraft.questions.firstIndex(where: { $0.id == questionId }) {
                                duplicateQuestion(at: idx)
                            }
                        }
                    )
                } else if let session = service.currentSession, !session.testDraft.questions.isEmpty {
                    // Show preview when no question selected but test has questions
                    TestPreviewView(test: session.testDraft)
                } else {
                    // Empty state
                    RightPanelEmptyState()
                }
            }
        }
        .navigationTitle("Créer un test")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Add manual question button
                Menu {
                    ForEach(QuestionType.allCases) { type in
                        Button {
                            addManualQuestion(type: type)
                        } label: {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                } label: {
                    Label("Ajouter une question", systemImage: "plus")
                }
                .disabled(service.currentSession == nil)

                Button {
                    showingSetupSheet = true
                } label: {
                    Label("Nouveau test", systemImage: "doc.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingSetupSheet) {
            NewTestSetupSheet(
                configuration: $configuration,
                onStart: {
                    service.startNewSession(configuration: configuration)
                    configuration = TestConfiguration() // Reset for next time
                },
                onQuickStart: {
                    service.startNewSession(configuration: TestConfiguration())
                }
            )
        }
        .onChange(of: selectedQuestionId) { _, newValue in
            // Switch to editor mode when a question is selected
            if newValue != nil && rightPanelMode == .preview {
                rightPanelMode = .editor
            }
        }
    }

    private func addManualQuestion(type: QuestionType) {
        let order = service.currentSession?.testDraft.questions.count ?? 0
        let question = Question.empty(type: type, order: order)
        service.addQuestion(question)
        selectedQuestionId = question.id
        rightPanelMode = .editor
    }

    private func duplicateQuestion(at index: Int) {
        guard let session = service.currentSession else { return }
        var newQuestion = session.testDraft.questions[index]
        newQuestion = Question(
            type: newQuestion.type,
            text: newQuestion.text,
            points: newQuestion.points,
            options: newQuestion.options,
            correctAnswer: newQuestion.correctAnswer,
            expectedAnswer: newQuestion.expectedAnswer,
            rubricGuidelines: newQuestion.rubricGuidelines,
            difficultyLevel: newQuestion.difficultyLevel,
            order: session.testDraft.questions.count
        )
        service.addQuestion(newQuestion)
        selectedQuestionId = newQuestion.id
    }
}

// MARK: - Empty States

struct NoSessionChatView: View {
    var onNewTest: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Aucun test en cours")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Créez un nouveau test pour commencer\nà générer des questions avec l'IA")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onNewTest()
            } label: {
                Label("Nouveau test", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoQuestionSelectedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.tap")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Sélectionnez une question")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Cliquez sur une question dans la liste\npour la modifier")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoSessionPreviewView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Aucun test à afficher")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Créez un test et ajoutez des questions\npour voir l'aperçu")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RightPanelEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Panneau de détail")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Sélectionnez une question pour la modifier\nou visualisez l'aperçu du test")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CreateTestView(modeBinding: .constant(.createTest))
}
