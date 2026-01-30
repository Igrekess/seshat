import Foundation
import CoreGraphics

protocol HTRServiceProtocol: Sendable {
    var modelLevel: HTRModelLevel { get }
    var isAvailable: Bool { get }

    func transcribe(_ image: CGImage) async throws -> TranscriptionResult
    func checkAvailability() async -> Bool
}

extension HTRServiceProtocol {
    func checkAvailability() async -> Bool {
        isAvailable
    }
}
