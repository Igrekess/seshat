import Foundation

// MARK: - Question Types

/// Types of questions that can be created in a test
enum QuestionType: String, Codable, CaseIterable, Identifiable {
    case multipleChoice = "MCQ"
    case openEnded = "OPEN"
    case trueFalse = "TF"
    case shortAnswer = "SHORT"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .multipleChoice: return "QCM"
        case .openEnded: return "Question ouverte"
        case .trueFalse: return "Vrai/Faux"
        case .shortAnswer: return "Réponse courte"
        }
    }

    var icon: String {
        switch self {
        case .multipleChoice: return "list.bullet.circle"
        case .openEnded: return "text.alignleft"
        case .trueFalse: return "checkmark.circle"
        case .shortAnswer: return "text.cursor"
        }
    }
}

// MARK: - Difficulty Level

/// Difficulty level for questions
enum DifficultyLevel: String, Codable, CaseIterable, Identifiable {
    case easy = "EASY"
    case medium = "MEDIUM"
    case hard = "HARD"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Facile"
        case .medium: return "Moyen"
        case .hard: return "Difficile"
        }
    }

    var color: String {
        switch self {
        case .easy: return "#4CAF50"    // Green
        case .medium: return "#FF9800"  // Orange
        case .hard: return "#F44336"    // Red
        }
    }
}

// MARK: - MCQ Option

/// A single option for a multiple choice question
struct MCQOption: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var isCorrect: Bool

    init(id: UUID = UUID(), text: String, isCorrect: Bool = false) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
    }
}

// MARK: - Question

/// A single question in a test
struct Question: Identifiable, Codable, Hashable {
    let id: UUID
    var type: QuestionType
    var text: String
    var points: Double
    var options: [MCQOption]?           // For MCQ
    var correctAnswer: Bool?            // For True/False
    var expectedAnswer: String?         // For open-ended/short answer
    var rubricGuidelines: String?       // Grading criteria for open-ended
    var difficultyLevel: DifficultyLevel?
    var order: Int

    init(
        id: UUID = UUID(),
        type: QuestionType,
        text: String,
        points: Double = 1.0,
        options: [MCQOption]? = nil,
        correctAnswer: Bool? = nil,
        expectedAnswer: String? = nil,
        rubricGuidelines: String? = nil,
        difficultyLevel: DifficultyLevel? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.points = points
        self.options = options
        self.correctAnswer = correctAnswer
        self.expectedAnswer = expectedAnswer
        self.rubricGuidelines = rubricGuidelines
        self.difficultyLevel = difficultyLevel
        self.order = order
    }

    /// Creates an empty question of the given type
    static func empty(type: QuestionType, order: Int) -> Question {
        var question = Question(type: type, text: "", order: order)
        if type == .multipleChoice {
            question.options = [
                MCQOption(text: ""),
                MCQOption(text: ""),
                MCQOption(text: ""),
                MCQOption(text: "")
            ]
        } else if type == .trueFalse {
            question.correctAnswer = true
        }
        return question
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Question, rhs: Question) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Test Status

/// Status of a test
enum TestStatus: String, Codable, CaseIterable {
    case draft = "draft"
    case ready = "ready"
    case archived = "archived"

    var displayName: String {
        switch self {
        case .draft: return "Brouillon"
        case .ready: return "Prêt"
        case .archived: return "Archivé"
        }
    }

    var icon: String {
        switch self {
        case .draft: return "pencil"
        case .ready: return "checkmark.seal"
        case .archived: return "archivebox"
        }
    }
}

// MARK: - Test

/// A complete test with questions
struct Test: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var subject: String
    var gradeLevel: String
    var questions: [Question]
    var status: TestStatus
    var totalPoints: Double
    var duration: Int?           // Duration in minutes (optional)
    var assignmentId: UUID?      // Optional link to Assignment
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        subject: String = "",
        gradeLevel: String = "",
        questions: [Question] = [],
        status: TestStatus = .draft,
        totalPoints: Double = 20.0,
        duration: Int? = nil,
        assignmentId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.subject = subject
        self.gradeLevel = gradeLevel
        self.questions = questions
        self.status = status
        self.totalPoints = totalPoints
        self.duration = duration
        self.assignmentId = assignmentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Calculated total points from questions
    var calculatedTotalPoints: Double {
        questions.reduce(0) { $0 + $1.points }
    }

    /// Questions sorted by order
    var sortedQuestions: [Question] {
        questions.sorted { $0.order < $1.order }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Test, rhs: Test) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Chat Message

/// Role of a message in the chat
enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

/// A message in the chat interface
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var content: String
    var parsedQuestions: [Question]?   // Questions extracted from this message
    var isStreaming: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        parsedQuestions: [Question]? = nil,
        isStreaming: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.parsedQuestions = parsedQuestions
        self.isStreaming = isStreaming
        self.timestamp = timestamp
    }

    /// Creates a user message
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    /// Creates an assistant message (optionally streaming)
    static func assistant(_ content: String, isStreaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, isStreaming: isStreaming)
    }

    /// Creates a system message
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
}

// MARK: - Test Creation Session

/// A session for creating a test with conversation history
struct TestCreationSession: Identifiable, Codable {
    let id: UUID
    var testDraft: Test
    var conversationHistory: [ChatMessage]
    var contextDocuments: [DocumentContext]  // Documents de contexte pour guider la génération
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        testDraft: Test,
        conversationHistory: [ChatMessage] = [],
        contextDocuments: [DocumentContext] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.testDraft = testDraft
        self.conversationHistory = conversationHistory
        self.contextDocuments = contextDocuments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Creates a new session with an empty test draft
    static func new(title: String = "Nouveau test", subject: String = "", gradeLevel: String = "") -> TestCreationSession {
        let test = Test(title: title, subject: subject, gradeLevel: gradeLevel)
        return TestCreationSession(testDraft: test)
    }

    /// Total estimated tokens for all context documents
    var totalContextTokens: Int {
        contextDocuments.reduce(0) { $0 + $1.estimatedTokens }
    }

    /// Check if any document is still processing (OCR in progress)
    var hasProcessingDocuments: Bool {
        contextDocuments.contains { $0.isProcessing }
    }
}

// MARK: - Document Context Model

/// Type of context document source
enum DocumentSourceType: String, Codable {
    case textFile       // .txt, .md, .pdf, .docx, .rtf
    case image          // Image with OCR extraction
}

/// Context document for test creation (text or image with OCR)
struct DocumentContext: Identifiable, Codable {
    let id: UUID
    let filename: String
    let content: String
    let wordCount: Int
    let estimatedTokens: Int
    let addedAt: Date
    var sourceURL: URL?
    var sourceType: DocumentSourceType
    var originalImageData: Data?  // For images, store the original for preview
    var isProcessing: Bool  // True while OCR is in progress

    init(
        id: UUID = UUID(),
        filename: String,
        content: String,
        wordCount: Int,
        estimatedTokens: Int,
        sourceURL: URL? = nil,
        sourceType: DocumentSourceType = .textFile,
        originalImageData: Data? = nil,
        isProcessing: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.content = content
        self.wordCount = wordCount
        self.estimatedTokens = estimatedTokens
        self.addedAt = Date()
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        self.originalImageData = originalImageData
        self.isProcessing = isProcessing
    }

    /// Create a placeholder for an image being processed
    static func processingPlaceholder(filename: String, imageData: Data) -> DocumentContext {
        DocumentContext(
            filename: filename,
            content: "",
            wordCount: 0,
            estimatedTokens: 0,
            sourceType: .image,
            originalImageData: imageData,
            isProcessing: true
        )
    }

    /// Truncate content to fit within token limit
    func truncated(maxTokens: Int) -> DocumentContext {
        guard estimatedTokens > maxTokens else { return self }

        let ratio = Double(maxTokens) / Double(estimatedTokens)
        let targetChars = Int(Double(content.count) * ratio * 0.9) // 10% safety margin

        let truncatedContent = String(content.prefix(targetChars)) + "\n\n[... document tronqué pour respecter la limite de contexte ...]"
        let newWordCount = truncatedContent.split(separator: " ").count

        return DocumentContext(
            id: id,
            filename: filename,
            content: truncatedContent,
            wordCount: newWordCount,
            estimatedTokens: maxTokens,
            sourceURL: sourceURL,
            sourceType: sourceType,
            originalImageData: originalImageData,
            isProcessing: false
        )
    }
}

// MARK: - Test Configuration

/// Configuration for a new test (used in setup sheet)
struct TestConfiguration {
    var title: String = ""
    var subject: String = ""
    var gradeLevel: String = ""
    var questionTypes: Set<QuestionType> = [.multipleChoice, .openEnded]
    var targetQuestionCount: Int = 10
    var totalPoints: Double = 20.0
    var duration: Int? = nil     // Duration in minutes (optional)
    var description: String = ""

    /// Common subjects
    static let commonSubjects = [
        "Anglais",
        "Français",
        "Mathématiques",
        "Histoire-Géographie",
        "Sciences",
        "Physique-Chimie",
        "SVT",
        "Philosophie",
        "Espagnol",
        "Allemand"
    ]

    /// Common grade levels
    static let gradeLevels = [
        "6ème",
        "5ème",
        "4ème",
        "3ème",
        "Seconde",
        "Première",
        "Terminale"
    ]
}
