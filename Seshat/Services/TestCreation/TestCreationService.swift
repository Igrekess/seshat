import Foundation

/// Service for managing test creation with AI assistance
@MainActor
@Observable
final class TestCreationService {
    /// Singleton instance
    static let shared = TestCreationService()

    /// Current session
    private(set) var currentSession: TestCreationSession?

    /// Whether AI is currently generating
    private(set) var isGenerating = false

    /// Current streaming content
    private(set) var streamingContent = ""

    /// Reference to Qwen service
    private let qwenService = QwenAnalysisService.shared

    /// Reference to DataStore for persistence
    private let dataStore = DataStore.shared

    /// Reference to DocumentContextService for OCR
    private let documentService = DocumentContextService.shared

    /// Maximum tokens for context documents (to avoid overloading Qwen)
    private static let maxContextTokens = 4000

    /// System prompt for question generation
    private static let systemPrompt = """
    You are an expert educational content creator helping teachers design assessments.
    You create well-structured questions that test student understanding effectively.

    When the user asks for questions, generate them using this EXACT format for EACH question:

    ---QUESTION---
    TYPE: [MCQ|OPEN|TF|SHORT]
    DIFFICULTY: [EASY|MEDIUM|HARD]
    POINTS: [number]
    TEXT: [the question text]
    OPTIONS: (for MCQ only, include 4 options)
    A) [option text]
    B) [option text] [CORRECT]
    C) [option text]
    D) [option text]
    EXPECTED: (for OPEN/SHORT, the expected answer or key points)
    [expected answer or key points to look for]
    RUBRIC: (for OPEN, grading guidelines)
    [grading criteria]
    ---END---

    IMPORTANT RULES:
    1. Use exactly ---QUESTION--- to start and ---END--- to finish each question
    2. For MCQ: Mark the correct answer with [CORRECT] after the option text
    3. For TRUE/FALSE (TF): Put "True" or "False" in the EXPECTED field
    4. Generate questions that are clear, unambiguous, and appropriate for the level
    5. Vary difficulty levels when generating multiple questions
    6. Write questions in the language specified by the user (French for French students, etc.)
    7. Be creative but pedagogically sound

    If the user asks you to modify existing questions, explain the changes you made.
    If the user provides context about the subject or topic, use it to create relevant questions.
    """

    private init() {}

    // MARK: - Session Management

    /// Start a new test creation session
    func startNewSession(configuration: TestConfiguration) {
        // Save current test before starting new one
        saveCurrentTest()

        let test = Test(
            title: configuration.title.isEmpty ? "Nouveau test" : configuration.title,
            description: configuration.description,
            subject: configuration.subject,
            gradeLevel: configuration.gradeLevel,
            totalPoints: configuration.totalPoints,
            duration: configuration.duration
        )

        currentSession = TestCreationSession(testDraft: test)

        // Add initial system context message (not shown to user)
        let contextMessage = buildContextMessage(from: configuration)
        currentSession?.conversationHistory.append(.system(contextMessage))

        // Save new test to DataStore
        dataStore.addTest(test)
    }

    /// Resume an existing session
    func resumeSession(_ session: TestCreationSession) {
        currentSession = session
    }

    /// Load a test from DataStore
    func loadTest(_ testId: UUID) {
        guard let test = dataStore.getTest(by: testId) else { return }

        // Save current test before loading another
        saveCurrentTest()

        // Create a new session with the loaded test
        currentSession = TestCreationSession(testDraft: test)
    }

    /// Get all saved tests
    func getSavedTests() -> [Test] {
        dataStore.getAllTests()
    }

    /// Delete a saved test
    func deleteSavedTest(_ testId: UUID) {
        dataStore.deleteTest(testId)
    }

    /// Clear the current session
    func clearSession() {
        saveCurrentTest()
        currentSession = nil
        streamingContent = ""
        isGenerating = false
    }

    /// Save the current test to DataStore
    private func saveCurrentTest() {
        guard let session = currentSession else { return }

        // Check if test already exists in DataStore
        if dataStore.getTest(by: session.testDraft.id) != nil {
            dataStore.updateTest(session.testDraft)
        } else {
            dataStore.addTest(session.testDraft)
        }
    }

    // MARK: - Message Handling

    /// Send a user message and get AI response
    func sendMessage(_ userMessage: String) async throws {
        guard var session = currentSession else {
            throw TestCreationError.noActiveSession
        }

        // Add user message
        let userChatMessage = ChatMessage.user(userMessage)
        session.conversationHistory.append(userChatMessage)
        currentSession = session

        // Start generating
        isGenerating = true
        streamingContent = ""

        // Create streaming assistant message
        var assistantMessage = ChatMessage.assistant("", isStreaming: true)
        session.conversationHistory.append(assistantMessage)
        currentSession = session

        do {
            // Build messages for API
            let messages = buildMessagesForAPI(session.conversationHistory)

            // Generate with streaming
            let fullResponse = try await qwenService.generateWithHistory(
                messages: messages,
                onToken: { @Sendable token in
                    Task { @MainActor [weak self] in
                        self?.streamingContent += token
                        self?.updateStreamingMessage()
                    }
                }
            )

            // Finalize the message
            assistantMessage.content = fullResponse
            assistantMessage.isStreaming = false

            // Parse any questions from the response (but don't add them yet - wait for user confirmation)
            if QuestionParser.containsQuestions(in: fullResponse) {
                let startingOrder = session.testDraft.questions.count
                let parsedQuestions = QuestionParser.parseQuestions(from: fullResponse, startingOrder: startingOrder)
                assistantMessage.parsedQuestions = parsedQuestions
                // Note: Questions are NOT added automatically - user must click "Ajouter au test"
            }

            // Update session with final message
            if let lastIndex = session.conversationHistory.indices.last {
                session.conversationHistory[lastIndex] = assistantMessage
            }
            session.updatedAt = Date()
            currentSession = session

        } catch {
            // Remove the streaming message on error
            session.conversationHistory.removeLast()
            currentSession = session
            isGenerating = false
            streamingContent = ""
            throw error
        }

        isGenerating = false
        streamingContent = ""
    }

    /// Update the streaming message in the session
    private func updateStreamingMessage() {
        guard var session = currentSession,
              let lastIndex = session.conversationHistory.indices.last else {
            return
        }

        session.conversationHistory[lastIndex].content = streamingContent
        currentSession = session
    }

    // MARK: - Question Management

    /// Add a question manually
    func addQuestion(_ question: Question) {
        guard var session = currentSession else { return }

        var newQuestion = question
        newQuestion.order = session.testDraft.questions.count
        session.testDraft.questions.append(newQuestion)
        session.testDraft.updatedAt = Date()
        currentSession = session
        saveCurrentTest()
    }

    /// Update an existing question
    func updateQuestion(_ question: Question) {
        guard var session = currentSession else { return }

        if let index = session.testDraft.questions.firstIndex(where: { $0.id == question.id }) {
            session.testDraft.questions[index] = question
            session.testDraft.updatedAt = Date()
            currentSession = session
            saveCurrentTest()
        }
    }

    /// Delete a question
    func deleteQuestion(_ questionId: UUID) {
        guard var session = currentSession else { return }

        session.testDraft.questions.removeAll { $0.id == questionId }

        // Reorder remaining questions
        for index in session.testDraft.questions.indices {
            session.testDraft.questions[index].order = index
        }

        session.testDraft.updatedAt = Date()
        currentSession = session
        saveCurrentTest()
    }

    /// Move a question to a new position
    func moveQuestion(from source: IndexSet, to destination: Int) {
        guard var session = currentSession else { return }

        session.testDraft.questions.move(fromOffsets: source, toOffset: destination)

        // Update order values
        for index in session.testDraft.questions.indices {
            session.testDraft.questions[index].order = index
        }

        session.testDraft.updatedAt = Date()
        currentSession = session
        saveCurrentTest()
    }

    // MARK: - Context Document Management

    /// Add a text document to context
    func addTextDocument(from url: URL) throws {
        guard var session = currentSession else { return }

        let doc = try documentService.extractText(from: url)
        session.contextDocuments.append(doc)
        session.updatedAt = Date()
        currentSession = session
    }

    /// Add an image document with OCR (async)
    func addImageDocument(from url: URL) async throws {
        guard var session = currentSession else { return }

        let filename = url.lastPathComponent
        let imageData = try Data(contentsOf: url)

        // Add a placeholder while processing
        let placeholder = DocumentContext.processingPlaceholder(filename: filename, imageData: imageData)
        let placeholderId = placeholder.id
        session.contextDocuments.append(placeholder)
        session.updatedAt = Date()
        currentSession = session

        do {
            // Perform OCR
            let doc = try await documentService.extractTextFromImage(url: url)

            // Replace placeholder with result
            if var updatedSession = currentSession,
               let index = updatedSession.contextDocuments.firstIndex(where: { $0.id == placeholderId }) {
                var updatedDoc = doc
                // Preserve the original ID
                updatedDoc = DocumentContext(
                    id: placeholderId,
                    filename: doc.filename,
                    content: doc.content,
                    wordCount: doc.wordCount,
                    estimatedTokens: doc.estimatedTokens,
                    sourceType: .image,
                    originalImageData: imageData,
                    isProcessing: false
                )
                updatedSession.contextDocuments[index] = updatedDoc
                updatedSession.updatedAt = Date()
                currentSession = updatedSession
            }
        } catch {
            // Remove placeholder on error
            if var updatedSession = currentSession {
                updatedSession.contextDocuments.removeAll { $0.id == placeholderId }
                currentSession = updatedSession
            }
            throw error
        }
    }

    /// Add documents from file URLs (auto-detects type)
    func addDocuments(from urls: [URL]) async throws {
        for url in urls {
            if documentService.isImageFile(url) {
                try await addImageDocument(from: url)
            } else {
                try addTextDocument(from: url)
            }
        }
    }

    /// Remove a context document
    func removeContextDocument(_ documentId: UUID) {
        guard var session = currentSession else { return }

        session.contextDocuments.removeAll { $0.id == documentId }
        session.updatedAt = Date()
        currentSession = session
    }

    /// Clear all context documents
    func clearContextDocuments() {
        guard var session = currentSession else { return }

        session.contextDocuments.removeAll()
        session.updatedAt = Date()
        currentSession = session
    }

    /// Get total context token count
    var totalContextTokens: Int {
        currentSession?.totalContextTokens ?? 0
    }

    /// Check if context is within limit
    var isContextWithinLimit: Bool {
        totalContextTokens <= Self.maxContextTokens
    }

    /// Update test metadata
    func updateTestMetadata(title: String? = nil, description: String? = nil, subject: String? = nil, gradeLevel: String? = nil, duration: Int?? = nil) {
        guard var session = currentSession else { return }

        if let title = title {
            session.testDraft.title = title
        }
        if let description = description {
            session.testDraft.description = description
        }
        if let subject = subject {
            session.testDraft.subject = subject
        }
        if let gradeLevel = gradeLevel {
            session.testDraft.gradeLevel = gradeLevel
        }
        // duration is Int?? to distinguish between "not provided" (nil) and "set to nil" (.some(nil))
        if let duration = duration {
            session.testDraft.duration = duration
        }

        session.testDraft.updatedAt = Date()
        currentSession = session
        saveCurrentTest()
    }

    /// Finalize the test (mark as ready)
    func finalizeTest() {
        guard var session = currentSession else { return }

        session.testDraft.status = .ready
        session.testDraft.updatedAt = Date()
        currentSession = session
        saveCurrentTest()
    }

    // MARK: - Private Helpers

    /// Build context message from configuration
    private func buildContextMessage(from config: TestConfiguration) -> String {
        var context = "Context for test creation:\n"

        if !config.subject.isEmpty {
            context += "- Subject: \(config.subject)\n"
        }
        if !config.gradeLevel.isEmpty {
            context += "- Grade Level: \(config.gradeLevel)\n"
        }
        if !config.questionTypes.isEmpty {
            let types = config.questionTypes.map { $0.displayName }.joined(separator: ", ")
            context += "- Preferred question types: \(types)\n"
        }
        context += "- Target number of questions: \(config.targetQuestionCount)\n"
        context += "- Total points: \(config.totalPoints)\n"

        if !config.description.isEmpty {
            context += "- Additional context: \(config.description)\n"
        }

        return context
    }

    /// Build messages array for API call
    private func buildMessagesForAPI(_ history: [ChatMessage]) -> [[String: String]] {
        var messages: [[String: String]] = [
            ["role": "system", "content": Self.systemPrompt]
        ]

        // Add context documents if present
        if let session = currentSession, !session.contextDocuments.isEmpty {
            let contextMessage = buildContextDocumentsMessage(session.contextDocuments)
            messages.append(["role": "user", "content": contextMessage])
        }

        for message in history {
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .assistant:
                role = "assistant"
            case .system:
                // Include system messages as user messages with context prefix
                role = "user"
            }

            if !message.content.isEmpty {
                messages.append(["role": role, "content": message.content])
            }
        }

        return messages
    }

    /// Build context message from documents
    private func buildContextDocumentsMessage(_ documents: [DocumentContext]) -> String {
        // Filter out documents still processing
        let readyDocuments = documents.filter { !$0.isProcessing }
        guard !readyDocuments.isEmpty else { return "" }

        var contextParts: [String] = []
        var totalTokens = 0
        let maxTokensPerDoc = Self.maxContextTokens / max(readyDocuments.count, 1)

        for doc in readyDocuments {
            let truncatedDoc = doc.truncated(maxTokens: maxTokensPerDoc)
            totalTokens += truncatedDoc.estimatedTokens

            let sourceLabel = doc.sourceType == .image ? "[Image OCR]" : "[Document]"
            contextParts.append("""
            --- \(sourceLabel) \(truncatedDoc.filename) ---
            \(truncatedDoc.content)
            """)

            // Stop if we're approaching the limit
            if totalTokens >= Self.maxContextTokens {
                break
            }
        }

        return """
        Voici le contexte du cours pour générer les questions. Utilise ce contenu pour créer des questions pertinentes et adaptées au niveau des élèves:

        \(contextParts.joined(separator: "\n\n"))
        """
    }
}

// MARK: - Errors

enum TestCreationError: LocalizedError {
    case noActiveSession
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "Aucune session de création active"
        case .generationFailed(let message):
            return "Échec de la génération: \(message)"
        }
    }
}
