import Foundation

/// Parser for extracting questions from LLM responses
final class QuestionParser {

    /// Pattern markers for question blocks
    private static let questionStartMarker = "---QUESTION---"
    private static let questionEndMarker = "---END---"

    /// Parse LLM response and extract questions
    /// - Parameters:
    ///   - response: The raw LLM response text
    ///   - startingOrder: The order number to start from for new questions
    /// - Returns: Array of parsed questions
    static func parseQuestions(from response: String, startingOrder: Int = 0) -> [Question] {
        var questions: [Question] = []
        var currentOrder = startingOrder

        // Find all question blocks
        let blocks = extractQuestionBlocks(from: response)

        for block in blocks {
            if let question = parseQuestionBlock(block, order: currentOrder) {
                questions.append(question)
                currentOrder += 1
            }
        }

        return questions
    }

    /// Extract question blocks from the response
    private static func extractQuestionBlocks(from response: String) -> [String] {
        var blocks: [String] = []

        // Split by question markers
        let components = response.components(separatedBy: questionStartMarker)

        for component in components.dropFirst() {
            // Find the end marker
            if let endRange = component.range(of: questionEndMarker) {
                let blockContent = String(component[..<endRange.lowerBound])
                blocks.append(blockContent.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                // If no end marker, try to parse until end of component
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(trimmed)
                }
            }
        }

        return blocks
    }

    /// Parse a single question block
    private static func parseQuestionBlock(_ block: String, order: Int) -> Question? {
        // Parse TYPE
        guard let typeString = extractField("TYPE", from: block),
              let type = parseQuestionType(typeString) else {
            return nil
        }

        // Parse TEXT (required)
        guard let text = extractField("TEXT", from: block), !text.isEmpty else {
            return nil
        }

        // Parse optional fields
        let difficultyString = extractField("DIFFICULTY", from: block)
        let difficulty = difficultyString.flatMap { parseDifficulty($0) }

        let pointsString = extractField("POINTS", from: block)
        let points = pointsString.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 1.0

        let expected = extractField("EXPECTED", from: block)
        let rubric = extractField("RUBRIC", from: block)

        // Create question based on type
        var question = Question(
            type: type,
            text: text,
            points: points,
            difficultyLevel: difficulty,
            order: order
        )

        switch type {
        case .multipleChoice:
            question.options = parseOptions(from: block)
        case .trueFalse:
            // For T/F, check EXPECTED for the answer
            if let expectedAnswer = expected?.lowercased() {
                question.correctAnswer = expectedAnswer.contains("true") || expectedAnswer.contains("vrai")
            } else {
                question.correctAnswer = true
            }
        case .openEnded, .shortAnswer:
            question.expectedAnswer = expected
            question.rubricGuidelines = rubric
        }

        return question
    }

    /// Parse question type from string
    private static func parseQuestionType(_ typeString: String) -> QuestionType? {
        let normalized = typeString.uppercased().trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "MCQ", "QCM", "MULTIPLE_CHOICE", "MULTIPLECHOICE":
            return .multipleChoice
        case "OPEN", "OPEN_ENDED", "OPENENDED", "ESSAY":
            return .openEnded
        case "TF", "TRUE_FALSE", "TRUEFALSE", "VRAI_FAUX":
            return .trueFalse
        case "SHORT", "SHORT_ANSWER", "SHORTANSWER":
            return .shortAnswer
        default:
            return nil
        }
    }

    /// Parse difficulty level from string
    private static func parseDifficulty(_ difficultyString: String) -> DifficultyLevel? {
        let normalized = difficultyString.uppercased().trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "EASY", "FACILE", "1":
            return .easy
        case "MEDIUM", "MOYEN", "MODERATE", "2":
            return .medium
        case "HARD", "DIFFICILE", "DIFFICULT", "3":
            return .hard
        default:
            return nil
        }
    }

    /// Extract a field value from the block
    private static func extractField(_ fieldName: String, from block: String) -> String? {
        // Pattern: FIELDNAME: value (until next field or end)
        // Known field names to stop at
        let knownFields = ["TYPE", "DIFFICULTY", "POINTS", "TEXT", "OPTIONS", "EXPECTED", "RUBRIC"]
        let fieldPattern = knownFields.joined(separator: "|")
        let pattern = #"(?:^|\n)\s*"# + fieldName + #"\s*:\s*(.+?)(?=\n\s*(?:"# + fieldPattern + #")\s*:|$)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return nil
        }

        let range = NSRange(block.startIndex..., in: block)
        guard let match = regex.firstMatch(in: block, options: [], range: range) else {
            return nil
        }

        if let captureRange = Range(match.range(at: 1), in: block) {
            var value = String(block[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // For TEXT field, also stop at option patterns (A), B), etc.)
            if fieldName == "TEXT" {
                // Remove any trailing options that might have been captured
                if let optionStart = value.range(of: #"\n\s*[A-D]\s*[\.\)]"#, options: .regularExpression) {
                    value = String(value[..<optionStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            return value
        }

        return nil
    }

    /// Parse MCQ options from the block
    private static func parseOptions(from block: String) -> [MCQOption] {
        // Find OPTIONS section
        guard let optionsSection = extractField("OPTIONS", from: block) else {
            // Try to find options directly with A), B), etc.
            return parseOptionsDirectly(from: block)
        }

        return parseOptionsDirectly(from: optionsSection)
    }

    /// Parse options from text with A), B), C), D) format
    private static func parseOptionsDirectly(from text: String) -> [MCQOption] {
        var options: [MCQOption] = []

        // Pattern: A) text [CORRECT] or A. text [CORRECT]
        let pattern = #"([A-D])\s*[\.\)]\s*(.+?)(?=\s*[A-D]\s*[\.\)]|\s*$)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return options
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            if let contentRange = Range(match.range(at: 2), in: text) {
                var optionText = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Check if this option is marked as correct and remove markers
                let isCorrect = optionText.containsAnswerMarker
                optionText = optionText.withoutAnswerMarkers

                if !optionText.isEmpty {
                    options.append(MCQOption(text: optionText, isCorrect: isCorrect))
                }
            }
        }

        // If no options found with the pattern, try line-by-line
        if options.isEmpty {
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let firstChar = trimmed.first,
                   ["A", "B", "C", "D", "a", "b", "c", "d"].contains(String(firstChar)) {
                    // Remove the letter prefix
                    var optionText = String(trimmed.dropFirst())
                    if optionText.hasPrefix(")") || optionText.hasPrefix(".") {
                        optionText = String(optionText.dropFirst())
                    }
                    optionText = optionText.trimmingCharacters(in: .whitespaces)

                    // Check if this option is marked as correct and remove markers
                    let isCorrect = optionText.containsAnswerMarker
                    optionText = optionText.withoutAnswerMarkers

                    if !optionText.isEmpty {
                        options.append(MCQOption(text: optionText, isCorrect: isCorrect))
                    }
                }
            }
        }

        return options
    }

    /// Check if the response contains question blocks
    static func containsQuestions(in response: String) -> Bool {
        return response.contains(questionStartMarker)
    }

    /// Count the number of question blocks in the response
    static func countQuestions(in response: String) -> Int {
        return response.components(separatedBy: questionStartMarker).count - 1
    }
}
