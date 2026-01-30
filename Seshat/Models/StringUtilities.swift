import Foundation

/// Shared utilities for string manipulation across Seshat
extension String {
    /// Checks if the string contains answer markers (typically for MCQ)
    /// Markers: [CORRECT], [CORRECTE], ✓, *
    var containsAnswerMarker: Bool {
        self.contains("[CORRECT]") ||
        self.contains("[CORRECTE]") ||
        self.contains("✓") ||
        self.contains("*")
    }

    /// Removes LLM answer markers commonly found in generated questions
    /// Handles: [CORRECT], [CORRECTE], ✓, *
    var withoutAnswerMarkers: String {
        self.replacingOccurrences(of: "[CORRECT]", with: "")
            .replacingOccurrences(of: "[CORRECTE]", with: "")
            .replacingOccurrences(of: "✓", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips common HTML tags and entities from text
    /// Used primarily for cleaning HTR/OCR output
    var strippingHTML: String {
        var result = self
        // HTML tags
        result = result.replacingOccurrences(of: "<br>", with: "\n")
        result = result.replacingOccurrences(of: "<br/>", with: "\n")
        result = result.replacingOccurrences(of: "<br />", with: "\n")
        result = result.replacingOccurrences(of: "</p>", with: "\n")
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // HTML entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalizes the string: uppercased and trimmed
    var normalized: String {
        self.uppercased().trimmingCharacters(in: .whitespaces)
    }

    /// Sanitizes the string for use as a filename
    /// Removes characters that are invalid in file paths
    var sanitizedForFilename: String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let sanitized = self.components(separatedBy: invalidCharacters).joined(separator: "_")
        return sanitized.isEmpty ? "document" : sanitized
    }
}
