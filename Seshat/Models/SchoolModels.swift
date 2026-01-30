import Foundation
import CoreGraphics

// MARK: - Crop Info

/// Stores crop settings for a single image (normalized 0-1 coordinates)
struct CropInfo: Codable, Equatable {
    let imageIndex: Int
    let rect: CGRect // Normalized (0-1)
}

// MARK: - School Class

struct SchoolClass: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var year: String  // e.g., "2025-2026"
    var level: String  // e.g., "Terminale", "Première", "Seconde"
    var studentIds: [UUID]
    var assignmentIds: [UUID]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        year: String = "",
        level: String = "",
        studentIds: [UUID] = [],
        assignmentIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.year = year
        self.level = level
        self.studentIds = studentIds
        self.assignmentIds = assignmentIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SchoolClass, rhs: SchoolClass) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Student

struct Student: Identifiable, Codable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var email: String?
    var classId: UUID
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        email: String? = nil,
        classId: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.classId = classId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var sortableName: String {
        "\(lastName) \(firstName)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Student, rhs: Student) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Assignment

struct Assignment: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var classId: UUID
    var dueDate: Date?
    var rubricId: UUID?
    var testId: UUID?       // Optional link to a Test created in "Create Test" mode
    var maxScore: Double
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        classId: UUID,
        dueDate: Date? = nil,
        rubricId: UUID? = nil,
        testId: UUID? = nil,
        maxScore: Double = 20.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.classId = classId
        self.dueDate = dueDate
        self.rubricId = rubricId
        self.testId = testId
        self.maxScore = maxScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Assignment, rhs: Assignment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Grading Rubric

struct GradingRubric: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var criteria: [RubricCriterion]
    var maxScore: Double
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        criteria: [RubricCriterion] = [],
        maxScore: Double = 20.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.criteria = criteria
        self.maxScore = maxScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: GradingRubric, rhs: GradingRubric) -> Bool {
        lhs.id == rhs.id
    }

    /// Calculate suggested grade based on error counts
    func calculateGrade(
        grammarErrors: Int,
        spellingErrors: Int,
        vocabularyErrors: Int,
        syntaxErrors: Int
    ) -> Double {
        var deductions = 0.0

        for criterion in criteria {
            let errorCount: Int
            switch criterion.category {
            case .grammar:
                errorCount = grammarErrors
            case .spelling:
                errorCount = spellingErrors
            case .vocabulary:
                errorCount = vocabularyErrors
            case .syntax:
                errorCount = syntaxErrors
            }

            let categoryDeduction = Double(errorCount) * criterion.pointsPerError
            deductions += min(categoryDeduction, criterion.maxDeduction)
        }

        return max(0, maxScore - deductions)
    }
}

struct RubricCriterion: Identifiable, Codable, Hashable {
    let id: UUID
    var category: ErrorCategory
    var pointsPerError: Double
    var maxDeduction: Double
    var description: String

    init(
        id: UUID = UUID(),
        category: ErrorCategory,
        pointsPerError: Double = 0.5,
        maxDeduction: Double = 5.0,
        description: String = ""
    ) {
        self.id = id
        self.category = category
        self.pointsPerError = pointsPerError
        self.maxDeduction = maxDeduction
        self.description = description
    }
}

// MARK: - Student Submission

struct StudentSubmission: Identifiable, Codable, Hashable {
    let id: UUID
    var studentId: UUID
    var assignmentId: UUID
    var imagePaths: [String]  // Relative paths to images
    var cropSettings: [CropInfo]?  // Optional crop settings per image
    var transcription: TranscriptionResult?
    var analysis: AnalysisResult?
    var grade: Double?
    var teacherGrade: Double?  // Manual override
    var teacherNotes: String
    var status: SubmissionStatus
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        studentId: UUID,
        assignmentId: UUID,
        imagePaths: [String] = [],
        cropSettings: [CropInfo]? = nil,
        transcription: TranscriptionResult? = nil,
        analysis: AnalysisResult? = nil,
        grade: Double? = nil,
        teacherGrade: Double? = nil,
        teacherNotes: String = "",
        status: SubmissionStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.studentId = studentId
        self.assignmentId = assignmentId
        self.imagePaths = imagePaths
        self.cropSettings = cropSettings
        self.transcription = transcription
        self.analysis = analysis
        self.grade = grade
        self.teacherGrade = teacherGrade
        self.teacherNotes = teacherNotes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Final grade (teacher override takes precedence)
    var finalGrade: Double? {
        teacherGrade ?? grade
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: StudentSubmission, rhs: StudentSubmission) -> Bool {
        lhs.id == rhs.id
    }
}

enum SubmissionStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case transcribed = "transcribed"
    case analyzed = "analyzed"
    case graded = "graded"

    var displayName: String {
        switch self {
        case .pending: return "En attente"
        case .transcribed: return "Transcrit"
        case .analyzed: return "Analysé"
        case .graded: return "Noté"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .transcribed: return "doc.text"
        case .analyzed: return "checkmark.circle"
        case .graded: return "star.fill"
        }
    }

    var color: String {
        switch self {
        case .pending: return "#9E9E9E"
        case .transcribed: return "#2196F3"
        case .analyzed: return "#4CAF50"
        case .graded: return "#FF9800"
        }
    }
}

// MARK: - Statistics

struct StudentStatistics {
    let student: Student
    let totalSubmissions: Int
    let gradedSubmissions: Int
    let averageGrade: Double?
    let totalErrors: Int
    let errorsByCategory: [ErrorCategory: Int]
    let gradeHistory: [(date: Date, grade: Double)]

    var grammarErrors: Int { errorsByCategory[.grammar] ?? 0 }
    var spellingErrors: Int { errorsByCategory[.spelling] ?? 0 }
    var vocabularyErrors: Int { errorsByCategory[.vocabulary] ?? 0 }
    var syntaxErrors: Int { errorsByCategory[.syntax] ?? 0 }
}

struct ClassStatistics {
    let schoolClass: SchoolClass
    let totalStudents: Int
    let totalAssignments: Int
    let totalSubmissions: Int
    let gradedSubmissions: Int
    let classAverage: Double?
    let gradeDistribution: [String: Int]  // e.g., "0-5": 2, "5-10": 5, etc.
    let commonErrors: [(category: ErrorCategory, count: Int)]
}

struct AssignmentStatistics {
    let assignment: Assignment
    let totalSubmissions: Int
    let gradedSubmissions: Int
    let averageGrade: Double?
    let highestGrade: Double?
    let lowestGrade: Double?
    let medianGrade: Double?
    let gradeDistribution: [String: Int]
    let commonErrors: [(text: String, count: Int)]
}
