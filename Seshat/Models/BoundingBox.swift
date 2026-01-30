import Foundation
import CoreGraphics

struct BoundingBox: Identifiable, Codable, Equatable {
    let id: UUID
    var rect: CGRect
    var text: String
    var confidence: Double
    var isEdited: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case rect
        case text
        case confidence
        case isEdited = "is_edited"
    }

    init(
        id: UUID = UUID(),
        rect: CGRect,
        text: String,
        confidence: Double,
        isEdited: Bool = false
    ) {
        self.id = id
        self.rect = rect
        self.text = text
        self.confidence = confidence
        self.isEdited = isEdited
    }

    // Custom Codable for CGRect
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        confidence = try container.decode(Double.self, forKey: .confidence)
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false

        let rectData = try container.decode([String: CGFloat].self, forKey: .rect)
        rect = CGRect(
            x: rectData["x"] ?? 0,
            y: rectData["y"] ?? 0,
            width: rectData["width"] ?? 0,
            height: rectData["height"] ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(isEdited, forKey: .isEdited)

        let rectData: [String: CGFloat] = [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.size.width,
            "height": rect.size.height
        ]
        try container.encode(rectData, forKey: .rect)
    }

    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.7...: return .high
        case 0.5..<0.7: return .medium
        default: return .low
        }
    }
}

enum ConfidenceLevel: String, CaseIterable {
    case high
    case medium
    case low

    var color: String {
        switch self {
        case .high: return "green"
        case .medium: return "orange"
        case .low: return "red"
        }
    }
}
