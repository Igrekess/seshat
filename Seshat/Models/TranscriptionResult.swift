import Foundation

struct TranscriptionResult: Identifiable, Codable, Equatable {
    let id: UUID
    var boundingBoxes: [BoundingBox]
    let modelLevel: HTRModelLevel
    let processingTime: TimeInterval
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case boundingBoxes = "bounding_boxes"
        case modelLevel = "model_level"
        case processingTime = "processing_time"
        case timestamp
    }

    init(
        id: UUID = UUID(),
        boundingBoxes: [BoundingBox],
        modelLevel: HTRModelLevel,
        processingTime: TimeInterval,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.boundingBoxes = boundingBoxes
        self.modelLevel = modelLevel
        self.processingTime = processingTime
        self.timestamp = timestamp
    }

    // MARK: - Computed Properties

    var fullText: String {
        boundingBoxes.map { $0.text }.joined(separator: " ")
    }

    var overallConfidence: Double {
        guard !boundingBoxes.isEmpty else { return 0 }
        let totalConfidence = boundingBoxes.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Double(boundingBoxes.count)
    }

    var lowConfidenceBoxes: [BoundingBox] {
        boundingBoxes.filter { $0.confidence < 0.7 }
    }

    var editedBoxes: [BoundingBox] {
        boundingBoxes.filter { $0.isEdited }
    }

    // MARK: - Mutation Helpers

    func updating(box: BoundingBox, with newText: String) -> TranscriptionResult {
        var newBoxes = boundingBoxes
        if let index = newBoxes.firstIndex(where: { $0.id == box.id }) {
            var updatedBox = newBoxes[index]
            updatedBox.text = newText
            updatedBox.isEdited = true
            newBoxes[index] = updatedBox
        }
        return TranscriptionResult(
            id: id,
            boundingBoxes: newBoxes,
            modelLevel: modelLevel,
            processingTime: processingTime,
            timestamp: timestamp
        )
    }

    func removing(box: BoundingBox) -> TranscriptionResult {
        let newBoxes = boundingBoxes.filter { $0.id != box.id }
        return TranscriptionResult(
            id: id,
            boundingBoxes: newBoxes,
            modelLevel: modelLevel,
            processingTime: processingTime,
            timestamp: timestamp
        )
    }

    /// Replace all text with a new full text (creates a single bounding box)
    func withFullText(_ newText: String) -> TranscriptionResult {
        // If we have existing boxes, try to preserve structure by updating the first one
        // Otherwise create a new single box
        if boundingBoxes.isEmpty {
            let newBox = BoundingBox(
                rect: .zero,
                text: newText,
                confidence: 1.0,
                isEdited: true
            )
            return TranscriptionResult(
                id: id,
                boundingBoxes: [newBox],
                modelLevel: modelLevel,
                processingTime: processingTime,
                timestamp: timestamp
            )
        } else {
            // Keep the first box and update its text
            var newBoxes = [boundingBoxes[0]]
            newBoxes[0].text = newText
            newBoxes[0].isEdited = true
            return TranscriptionResult(
                id: id,
                boundingBoxes: newBoxes,
                modelLevel: modelLevel,
                processingTime: processingTime,
                timestamp: timestamp
            )
        }
    }
}
