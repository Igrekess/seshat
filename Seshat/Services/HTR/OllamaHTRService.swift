import Foundation
import CoreGraphics
import AppKit

/// Ollama-based HTR service as fallback
/// Connects to local Ollama server running vision-capable model
final class OllamaHTRService: HTRServiceProtocol {
    let modelLevel: HTRModelLevel = .ollama

    private let baseURL: URL
    private let modelName: String

    var isAvailable: Bool {
        // Would check if Ollama server is running
        false // Disabled for MVP
    }

    init(baseURL: URL = URL(string: "http://localhost:11434")!, modelName: String = "llava") {
        self.baseURL = baseURL
        self.modelName = modelName
    }

    func checkAvailability() async -> Bool {
        // Try to connect to Ollama server
        let healthURL = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Server not running
        }
        return false
    }

    func transcribe(_ image: CGImage) async throws -> TranscriptionResult {
        let startTime = Date()

        // Convert image to base64
        guard let imageData = imageToBase64(image) else {
            throw SeshatError.invalidImageFormat
        }

        // Build request to Ollama
        let requestBody: [String: Any] = [
            "model": modelName,
            "prompt": "Transcribe all handwritten text in this image. Return only the transcribed text, line by line.",
            "images": [imageData],
            "stream": false
        ]

        let apiURL = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw SeshatError.transcriptionFailed(underlying: NSError(domain: "Seshat", code: -1))
        }

        // Convert response to bounding boxes (simplified - no actual coordinates from Ollama)
        let lines = responseText.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let boundingBoxes = lines.enumerated().map { index, line in
            BoundingBox(
                rect: CGRect(x: 50, y: 50 + (index * 30), width: 500, height: 25),
                text: line,
                confidence: 0.7 // Ollama doesn't provide confidence
            )
        }

        let processingTime = Date().timeIntervalSince(startTime)

        return TranscriptionResult(
            boundingBoxes: boundingBoxes,
            modelLevel: modelLevel,
            processingTime: processingTime
        )
    }

    private func imageToBase64(_ image: CGImage) -> String? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }
}
