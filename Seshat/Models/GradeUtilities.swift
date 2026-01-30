import SwiftUI

/// Shared utilities for grade-related calculations and display
enum GradeUtilities {
    /// Returns the appropriate color for a given grade (out of 20 by default)
    /// - Parameters:
    ///   - grade: The grade value
    ///   - maxGrade: The maximum possible grade (default: 20)
    /// - Returns: A Color representing the grade level
    static func color(for grade: Double, maxGrade: Double = 20.0) -> Color {
        // Normalize to 20-point scale for consistent color mapping
        let normalizedGrade = (grade / maxGrade) * 20.0

        switch normalizedGrade {
        case 0..<8: return .red
        case 8..<10: return .orange
        case 10..<12: return .yellow
        case 12..<14: return .green
        default: return .blue
        }
    }
}
