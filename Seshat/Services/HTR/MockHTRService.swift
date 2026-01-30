import Foundation
import CoreGraphics

/// Mock HTR service for development and testing
final class MockHTRService: HTRServiceProtocol {
    let modelLevel: HTRModelLevel = .mock

    var isAvailable: Bool { true }

    func transcribe(_ image: CGImage) async throws -> TranscriptionResult {
        let startTime = Date()

        // Simulate processing delay
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Generate demo content
        let mockContent: [(String, Double)] = [
            ("Dear Teacher,", 0.92),
            ("I am writing to explain why I was absent yesterday.", 0.88),
            ("I had a very bad cold and my mother taked me to the doctor.", 0.76),
            ("He said I needed to rest for one day.", 0.85),
            ("I have did all my homework at home.", 0.71),
            ("I hope you will understanding my situation.", 0.68),
            ("Thank you for your patience.", 0.91),
            ("Sincerely, Student", 0.89)
        ]

        let lineHeight = height / CGFloat(mockContent.count + 2)
        let margin = width * 0.08

        let boundingBoxes = mockContent.enumerated().map { indexAndItem -> BoundingBox in
            let index = indexAndItem.offset
            let item = indexAndItem.element
            let text = item.0
            let confidence = item.1

            return BoundingBox(
                rect: CGRect(
                    x: margin,
                    y: lineHeight * CGFloat(index + 1),
                    width: width - (margin * 2),
                    height: lineHeight * 0.75
                ),
                text: text,
                confidence: confidence
            )
        }

        return TranscriptionResult(
            boundingBoxes: boundingBoxes,
            modelLevel: modelLevel,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }
}
