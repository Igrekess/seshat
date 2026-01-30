import Foundation
import CoreGraphics
import AppKit

struct StudentCopy: Identifiable, Codable {
    let id: UUID
    let imageData: Data
    let originalFilename: String
    let createdAt: Date
    var status: CopyStatus

    // Non-codable property
    var cgImage: CGImage?

    enum CodingKeys: String, CodingKey {
        case id
        case imageData = "image_data"
        case originalFilename = "original_filename"
        case createdAt = "created_at"
        case status
    }

    init(
        id: UUID = UUID(),
        imageData: Data,
        originalFilename: String,
        createdAt: Date = Date(),
        status: CopyStatus = .imported,
        cgImage: CGImage? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.originalFilename = originalFilename
        self.createdAt = createdAt
        self.status = status
        self.cgImage = cgImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        imageData = try container.decode(Data.self, forKey: .imageData)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decode(CopyStatus.self, forKey: .status)

        // Reconstruct cgImage from data
        if let nsImage = NSImage(data: imageData) {
            cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }

    var nsImage: NSImage? {
        NSImage(data: imageData)
    }

    var imageSize: CGSize? {
        nsImage?.size
    }
}

enum CopyStatus: String, Codable, CaseIterable {
    case imported = "imported"
    case transcribed = "transcribed"
    case validated = "validated"
    case analyzed = "analyzed"
    case exported = "exported"

    var displayName: String {
        switch self {
        case .imported: return "Importée"
        case .transcribed: return "Transcrite"
        case .validated: return "Validée"
        case .analyzed: return "Analysée"
        case .exported: return "Exportée"
        }
    }
}
