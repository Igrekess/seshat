import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Hub

/// Service d'analyse linguistique utilisant Qwen2.5-7B-Instruct
/// Détecte les erreurs grammaticales, orthographiques et les faux-amis FR→EN
final class QwenAnalysisService: @unchecked Sendable {
    /// Singleton pour réutiliser le modèle préchargé
    static let shared = QwenAnalysisService()

    private var modelContainer: ModelContainer?
    private let modelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    /// Prompt système pour l'analyse des erreurs (avec few-shot examples)
    private static let errorAnalysisPrompt = """
    You are an English teacher correcting essays by French students. Find ONLY REAL ERRORS, not stylistic preferences.

    Categories: grammar, vocabulary, spelling, syntax

    WHAT IS AN ERROR (report these):
    - Spelling mistakes: "beautifull" → "beautiful"
    - Grammar mistakes: "I taked" → "I took", "he go" → "he goes", missing articles
    - False friends (faux-amis): "actually" used to mean "currently"
    - Wrong word completely: "deep charms" when meaning "deep chasms/divides"
    - Broken syntax: "Very interesting the book" → "The book is very interesting"
    - Subject-verb agreement: "he lull" → "he lulls" or "he lulled"

    WHAT IS NOT AN ERROR (do NOT report these):
    - Present vs past tense in commentary (both "he emphasizes" and "he emphasized" are valid)
    - Starting a sentence with "But" vs "However" (both are acceptable)
    - Stylistic word choices that are grammatically correct
    - Rephrasing that would sound "better" but original is not wrong
    - "a few days away from" vs "a few days before" (both valid)

    EXAMPLES:

    INPUT: "I taked the bus yesterday. The weather was very beautifull."
    OUTPUT: [{"text":"taked","correction":"took","explanation":"Verbe irrégulier: take-took-taken","category":"grammar"},{"text":"beautifull","correction":"beautiful","explanation":"Un seul 'l' à la fin","category":"spelling"}]

    INPUT: "Actually, I am student since 3 years."
    OUTPUT: [{"text":"Actually","correction":"Currently","explanation":"Faux-ami: 'actually' = 'en fait', pas 'actuellement'","category":"vocabulary"},{"text":"am student","correction":"am a student","explanation":"Article 'a' requis devant un métier/statut","category":"grammar"},{"text":"since 3 years","correction":"for 3 years","explanation":"'For' pour une durée, 'since' pour un point de départ","category":"grammar"}]

    INPUT: "He lull the masses. Deep charms remain in the US."
    OUTPUT: [{"text":"lull","correction":"lulled","explanation":"Accord sujet-verbe au passé: he lulled","category":"grammar"},{"text":"charms","correction":"chasms","explanation":"Mot incorrect: 'charms' (charmes) devrait être 'chasms' (gouffres)","category":"vocabulary"}]

    INPUT: "But he stresses that education is important."
    OUTPUT: [] (No errors - "But" at start of sentence is acceptable, present tense valid in commentary)

    CRITICAL: Only report genuine mistakes. If the text is grammatically correct, return an empty array [].
    """

    /// Prompt système pour le feedback global (professeur d'anglais en lycée français)
    private static let globalFeedbackPrompt = """
    Tu es un professeur d'anglais bienveillant dans un lycée français. Tu corriges la copie d'un élève.
    Donne un feedback constructif et encourageant en français.

    Retourne un JSON avec exactement ces champs:
    {
        "overall_assessment": "Appréciation générale de la copie (2-3 phrases)",
        "strengths": ["Point fort 1", "Point fort 2"],
        "areas_for_improvement": ["Axe d'amélioration 1", "Axe d'amélioration 2"],
        "suggested_grade": "Note sur 20 (ex: 14/20)",
        "encouragement": "Message d'encouragement personnalisé (1-2 phrases)"
    }

    Sois bienveillant mais honnête. Trouve toujours au moins un point positif.
    """

    /// Prompt pour l'analyse des erreurs
    private static func errorPrompt(for text: String) -> String {
        """
        Find ONLY REAL ERRORS in this text (spelling, grammar, wrong words, broken syntax).
        Do NOT report stylistic preferences or valid alternative phrasings.

        Return a JSON array with objects: text, correction, explanation, category (grammar/vocabulary/spelling/syntax).
        If no real errors, return [].

        TEXT: \(text)

        JSON:
        """
    }

    /// Prompt pour le feedback global
    private static func feedbackPrompt(for text: String, errorCount: Int) -> String {
        """
        Voici la copie d'un élève de lycée français (rédaction en anglais).
        L'analyse a détecté \(errorCount) erreur(s).

        TEXTE DE L'ÉLÈVE:
        \(text)

        Donne ton feedback de professeur en JSON (en français):
        """
    }

    var isAvailable: Bool {
        let hubApi = HubApi()
        let repo = Hub.Repo(id: modelId)
        let modelDir = hubApi.localRepoLocation(repo)
        let configPath = modelDir.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configPath.path)
    }

    /// Charge le modèle en mémoire
    func loadModel() async throws {
        guard modelContainer == nil else { return }

        let configuration = ModelConfiguration(id: modelId)

        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        ) { _ in }
    }

    /// Décharge le modèle de la mémoire
    func unloadModel() {
        modelContainer = nil
    }

    /// Analyse le texte et retourne les erreurs détectées
    func analyze(_ text: String) async throws -> AnalysisResult {
        let startTime = Date()

        try await loadModel()

        guard let container = modelContainer else {
            throw QwenAnalysisError.modelNotLoaded
        }

        // Préparer le prompt pour la détection d'erreurs
        let messages: [Message] = [
            ["role": "system", "content": Self.errorAnalysisPrompt],
            ["role": "user", "content": Self.errorPrompt(for: text)]
        ]

        let userInput = UserInput(prompt: .messages(messages))
        let preparedInput = try await container.prepare(input: userInput)

        let generateParameters = GenerateParameters(
            maxTokens: 2048,
            temperature: 0.3
        )

        var generatedText = ""
        let stream = try await container.generate(
            input: preparedInput,
            parameters: generateParameters
        )

        for await generation in stream {
            switch generation {
            case .chunk(let chunk):
                generatedText += chunk
            default:
                continue
            }
        }

        // Parser la réponse JSON
        let errors = parseErrorsFromJSON(generatedText, originalText: text)

        // Générer le feedback global du professeur
        let globalFeedback = try await generateGlobalFeedback(for: text, errorCount: errors.count, container: container)

        let totalProcessingTime = Date().timeIntervalSince(startTime)

        return AnalysisResult(
            errors: errors,
            globalFeedback: globalFeedback,
            processingTime: totalProcessingTime
        )
    }

    /// Génère le feedback global du professeur
    private func generateGlobalFeedback(
        for text: String,
        errorCount: Int,
        container: ModelContainer
    ) async throws -> GlobalFeedback? {
        let messages: [Message] = [
            ["role": "system", "content": Self.globalFeedbackPrompt],
            ["role": "user", "content": Self.feedbackPrompt(for: text, errorCount: errorCount)]
        ]

        let userInput = UserInput(prompt: .messages(messages))
        let preparedInput = try await container.prepare(input: userInput)

        let generateParameters = GenerateParameters(
            maxTokens: 1024,
            temperature: 0.5  // Un peu plus créatif pour le feedback
        )

        var generatedText = ""
        let stream = try await container.generate(
            input: preparedInput,
            parameters: generateParameters
        )

        for await generation in stream {
            switch generation {
            case .chunk(let chunk):
                generatedText += chunk
            default:
                continue
            }
        }

        return parseFeedbackFromJSON(generatedText)
    }

    /// Parse le JSON du feedback global
    private func parseFeedbackFromJSON(_ json: String) -> GlobalFeedback? {
        let jsonPattern = #"\{[\s\S]*\}"#
        guard let range = json.range(of: jsonPattern, options: .regularExpression) else {
            return nil
        }

        let jsonString = String(json[range])

        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            let dto = try JSONDecoder().decode(FeedbackDTO.self, from: data)
            return GlobalFeedback(
                overallAssessment: dto.overallAssessment,
                strengths: dto.strengths,
                areasForImprovement: dto.areasForImprovement,
                suggestedGrade: dto.suggestedGrade,
                encouragement: dto.encouragement
            )
        } catch {
            return nil
        }
    }

    // MARK: - Private Methods

    private func parseErrorsFromJSON(_ json: String, originalText: String) -> [LinguisticError] {
        let jsonPattern = #"\[[\s\S]*\]"#
        guard let range = json.range(of: jsonPattern, options: .regularExpression) else {
            return []
        }

        let jsonString = String(json[range])

        guard let data = jsonString.data(using: .utf8) else {
            return []
        }

        do {
            let decoded = try JSONDecoder().decode([ErrorDTO].self, from: data)

            return decoded.compactMap { dto -> LinguisticError? in
                // Filtrer les faux positifs où text == correction
                guard dto.text.lowercased() != dto.correction.lowercased() else {
                    return nil
                }

                let category = inferCategory(from: dto)
                let position = findPosition(of: dto.text, in: originalText)

                return LinguisticError(
                    category: category,
                    text: dto.text,
                    correction: dto.correction,
                    explanation: dto.explanation,
                    position: position
                )
            }
        } catch {
            return []
        }
    }

    private func inferCategory(from dto: ErrorDTO) -> ErrorCategory {
        // Si la catégorie est fournie et valide, l'utiliser
        if let cat = dto.category, let category = ErrorCategory(rawValue: cat.lowercased()) {
            return category
        }

        // Sinon, inférer depuis l'explication
        let explanation = dto.explanation.lowercased()
        if explanation.contains("spelling") || explanation.contains("orthograph") {
            return .spelling
        } else if explanation.contains("syntax") || explanation.contains("word order") || explanation.contains("structure") {
            return .syntax
        } else if explanation.contains("vocabulary") || explanation.contains("faux-ami") || explanation.contains("false friend") {
            return .vocabulary
        } else {
            return .grammar // Default
        }
    }

    private func findPosition(of errorText: String, in fullText: String) -> ErrorPosition {
        if let range = fullText.range(of: errorText, options: .caseInsensitive) {
            let startIndex = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
            let endIndex = fullText.distance(from: fullText.startIndex, to: range.upperBound)
            return ErrorPosition(startIndex: startIndex, endIndex: endIndex, boundingBoxId: nil)
        }
        return ErrorPosition(startIndex: 0, endIndex: 0, boundingBoxId: nil)
    }
}

// MARK: - Supporting Types

private struct ErrorDTO: Codable {
    let text: String
    let correction: String
    let explanation: String
    let category: String?  // Optionnel car le modèle peut l'oublier
}

private struct FeedbackDTO: Codable {
    let overallAssessment: String
    let strengths: [String]
    let areasForImprovement: [String]
    let suggestedGrade: String?
    let encouragement: String

    enum CodingKeys: String, CodingKey {
        case overallAssessment = "overall_assessment"
        case strengths
        case areasForImprovement = "areas_for_improvement"
        case suggestedGrade = "suggested_grade"
        case encouragement
    }
}

// MARK: - Multi-Turn Generation

extension QwenAnalysisService {
    /// Generate a response with conversation history (multi-turn chat)
    /// - Parameters:
    ///   - messages: Array of messages with "role" and "content" keys
    ///   - onToken: Callback for each generated token (for streaming)
    /// - Returns: The complete generated response
    func generateWithHistory(
        messages: [[String: String]],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        // Load model if needed
        try await loadModel()

        guard let container = modelContainer else {
            throw QwenAnalysisError.modelNotLoaded
        }

        // Convert to Message format
        let formattedMessages: [Message] = messages.map { msg in
            ["role": msg["role"] ?? "user", "content": msg["content"] ?? ""]
        }

        // Create input
        let userInput = UserInput(prompt: .messages(formattedMessages))
        let preparedInput = try await container.prepare(input: userInput)

        // Generation parameters
        let generateParameters = GenerateParameters(
            maxTokens: 4096,
            temperature: 0.7
        )

        // Generate with streaming
        var fullResponse = ""
        let stream = try await container.generate(
            input: preparedInput,
            parameters: generateParameters
        )

        for await generation in stream {
            switch generation {
            case .chunk(let chunk):
                fullResponse += chunk
                onToken(chunk)
            default:
                continue
            }
        }

        return fullResponse
    }
}

enum QwenAnalysisError: LocalizedError {
    case modelNotLoaded
    case analysisError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Le modèle Qwen n'est pas chargé"
        case .analysisError(let message):
            return "Erreur d'analyse: \(message)"
        }
    }
}
