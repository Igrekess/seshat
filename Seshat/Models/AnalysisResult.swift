import Foundation

struct AnalysisResult: Identifiable, Codable, Sendable {
    let id: UUID
    let errors: [LinguisticError]
    let globalFeedback: GlobalFeedback?
    let timestamp: Date
    let processingTime: TimeInterval

    enum CodingKeys: String, CodingKey {
        case id
        case errors
        case globalFeedback = "global_feedback"
        case timestamp
        case processingTime = "processing_time"
    }

    init(
        id: UUID = UUID(),
        errors: [LinguisticError],
        globalFeedback: GlobalFeedback? = nil,
        timestamp: Date = Date(),
        processingTime: TimeInterval = 0
    ) {
        self.id = id
        self.errors = errors
        self.globalFeedback = globalFeedback
        self.timestamp = timestamp
        self.processingTime = processingTime
    }

    // MARK: - Statistics

    var errorsByCategory: [ErrorCategory: [LinguisticError]] {
        Dictionary(grouping: errors, by: { $0.category })
    }

    var totalErrors: Int {
        errors.count
    }

    func errorCount(for category: ErrorCategory) -> Int {
        errors.filter { $0.category == category }.count
    }

    var summary: String {
        let counts = ErrorCategory.allCases.compactMap { category -> String? in
            let count = errorCount(for: category)
            guard count > 0 else { return nil }
            return "\(count) \(category.displayName.lowercased())"
        }
        return counts.joined(separator: ", ")
    }

    // MARK: - Mutation Helpers

    func removing(error: LinguisticError) -> AnalysisResult {
        let newErrors = errors.filter { $0.id != error.id }
        return AnalysisResult(
            id: id,
            errors: newErrors,
            globalFeedback: globalFeedback,
            timestamp: timestamp,
            processingTime: processingTime
        )
    }

    func adding(error: LinguisticError) -> AnalysisResult {
        var newErrors = errors
        newErrors.append(error)
        return AnalysisResult(
            id: id,
            errors: newErrors,
            globalFeedback: globalFeedback,
            timestamp: timestamp,
            processingTime: processingTime
        )
    }

    func updating(error: LinguisticError) -> AnalysisResult {
        var newErrors = errors
        if let index = newErrors.firstIndex(where: { $0.id == error.id }) {
            newErrors[index] = error
        }
        return AnalysisResult(
            id: id,
            errors: newErrors,
            globalFeedback: globalFeedback,
            timestamp: timestamp,
            processingTime: processingTime
        )
    }
}

struct LinguisticError: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let category: ErrorCategory
    let text: String
    let correction: String?
    let explanation: String
    let position: ErrorPosition

    init(
        id: UUID = UUID(),
        category: ErrorCategory,
        text: String,
        correction: String?,
        explanation: String,
        position: ErrorPosition
    ) {
        self.id = id
        self.category = category
        self.text = text
        self.correction = correction
        self.explanation = explanation
        self.position = position
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ErrorPosition: Codable, Equatable, Hashable, Sendable {
    let startIndex: Int
    let endIndex: Int
    let boundingBoxId: UUID?

    enum CodingKeys: String, CodingKey {
        case startIndex = "start_index"
        case endIndex = "end_index"
        case boundingBoxId = "bounding_box_id"
    }
}

/// Feedback global du professeur sur la copie
struct GlobalFeedback: Codable, Sendable {
    let overallAssessment: String      // Appréciation générale
    let strengths: [String]            // Points forts
    let areasForImprovement: [String]  // Axes d'amélioration
    let suggestedGrade: String?        // Note suggérée (optionnel)
    let encouragement: String          // Message d'encouragement

    enum CodingKeys: String, CodingKey {
        case overallAssessment = "overall_assessment"
        case strengths
        case areasForImprovement = "areas_for_improvement"
        case suggestedGrade = "suggested_grade"
        case encouragement
    }
}

enum ErrorCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case grammar = "grammar"
    case vocabulary = "vocabulary"
    case syntax = "syntax"
    case spelling = "spelling"

    var displayName: String {
        switch self {
        case .grammar: return "Grammaire"
        case .vocabulary: return "Vocabulaire"
        case .syntax: return "Syntaxe"
        case .spelling: return "Orthographe"
        }
    }

    var defaultColor: String {
        switch self {
        case .grammar: return "#E53935"      // Red
        case .vocabulary: return "#1E88E5"   // Blue
        case .syntax: return "#43A047"       // Green
        case .spelling: return "#FB8C00"     // Orange
        }
    }

    var icon: String {
        switch self {
        case .grammar: return "textformat.abc"
        case .vocabulary: return "character.book.closed"
        case .syntax: return "arrow.left.arrow.right"
        case .spelling: return "pencil"
        }
    }
}
