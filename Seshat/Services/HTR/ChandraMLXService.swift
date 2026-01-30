import Foundation
import CoreGraphics
import CoreImage
import AppKit
import MLX
import MLXVLM
import MLXLMCommon
import Hub

/// Chandra HTR Service - Inférence Swift native avec MLX
///
/// Utilise mlx-community/chandra-4bit (architecture qwen3_vl)
/// Plus besoin de script Python externe
final class ChandraMLXService: HTRServiceProtocol, @unchecked Sendable {
    /// Singleton pour réutiliser le modèle préchargé
    static let shared = ChandraMLXService()

    let modelLevel: HTRModelLevel = .chandra

    /// Constante Chandra : bounding boxes normalisées à 0-1024
    private static let bboxScale: CGFloat = 1024

    /// Modèle chargé en mémoire
    private var modelContainer: ModelContainer?
    private let modelId = "mlx-community/chandra-4bit"

    /// Prompt OCR spécialisé pour l'écriture manuscrite
    private static let ocrLayoutPrompt = """
    OCR this HANDWRITTEN text image to HTML. This is a student's handwritten essay in English.

    IMPORTANT: This is handwriting, not printed text. Be careful with:
    - Letters that look similar: a/o, e/c, n/u, m/n, l/i, r/v
    - Words may be connected or have inconsistent spacing
    - Some letters may be poorly formed - use context to guess the intended word
    - Read carefully and transcribe what makes sense grammatically

    Output format: HTML with layout blocks. Each block is a div with:
    - data-bbox="[x0, y0, x1, y1]" (coordinates normalized 0-1024)
    - data-label="Text" for text paragraphs

    Use only these tags: ['p', 'br', 'div']

    Guidelines:
    * Group text into logical paragraphs using <p>...</p> tags
    * Use <br> only for intentional line breaks within a paragraph
    * Preserve the original text exactly - do not correct spelling or grammar errors
    * If a word is unclear, transcribe your best guess based on context
    * Reading order should follow natural top-to-bottom, left-to-right flow
    """

    var isAvailable: Bool {
        // Vérifier si le modèle est téléchargé via le chemin du cache HuggingFace
        let hubApi = HubApi()
        let repo = Hub.Repo(id: modelId)
        let modelDir = hubApi.localRepoLocation(repo)
        let configPath = modelDir.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configPath.path)
    }

    func checkAvailability() async -> Bool {
        isAvailable
    }

    /// Charge le modèle en mémoire si nécessaire
    func loadModel() async throws {
        guard modelContainer == nil else { return }

        let configuration = ModelConfiguration(id: modelId)

        modelContainer = try await VLMModelFactory.shared.loadContainer(
            configuration: configuration
        ) { _ in }
    }

    /// Décharge le modèle de la mémoire
    func unloadModel() {
        modelContainer = nil
    }

    func transcribe(_ image: CGImage) async throws -> TranscriptionResult {
        let startTime = Date()
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        // Charger le modèle si nécessaire
        try await loadModel()

        guard let container = modelContainer else {
            throw ChandraMLXError.modelNotLoaded
        }

        // Prétraitement : améliorer le contraste pour l'écriture manuscrite
        let enhancedImage = enhanceImageForOCR(image)

        // Convertir CGImage en CIImage
        let ciImage = CIImage(cgImage: enhancedImage)

        // Construire le chat avec l'image attachée au message utilisateur
        let chat: [Chat.Message] = [
            .user(Self.ocrLayoutPrompt, images: [.ciImage(ciImage)])
        ]

        var userInput = UserInput(chat: chat)

        // Calculer la taille en préservant l'aspect ratio (max 1536px)
        let maxDimension: CGFloat = 1536
        let resizeSize = calculateResizePreservingAspectRatio(
            width: imageWidth,
            height: imageHeight,
            maxDimension: maxDimension
        )
        userInput.processing.resize = .init(width: Int(resizeSize.width), height: Int(resizeSize.height))

        // Préparer l'input pour le modèle
        let preparedInput = try await container.prepare(input: userInput)

        // Paramètres de génération
        let generateParameters = GenerateParameters(
            maxTokens: 4096,
            temperature: 0.0  // Déterministe pour OCR
        )

        // Générer la réponse
        var generatedText = ""
        let stream = try await container.generate(
            input: preparedInput,
            parameters: generateParameters
        )

        for await generation in stream {
            switch generation {
            case .chunk(let text):
                generatedText += text
            default:
                continue
            }
        }

        let processingTime = Date().timeIntervalSince(startTime)

        // Parser le HTML pour extraire les bounding boxes
        let boundingBoxes = parseLayoutBlocks(
            html: generatedText,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )

        return TranscriptionResult(
            boundingBoxes: boundingBoxes,
            modelLevel: modelLevel,
            processingTime: processingTime
        )
    }

    // MARK: - Private Methods

    /// Parse le HTML Chandra et extrait les bounding boxes
    /// Note: Chandra génère du HTML mal formé (</div< au lieu de </div><)
    private func parseLayoutBlocks(
        html: String,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [BoundingBox] {
        let widthScaler = imageWidth / Self.bboxScale
        let heightScaler = imageHeight / Self.bboxScale

        var boxes: [BoundingBox] = []

        // Chandra génère un format spécial mal formé:
        // <div data-bbox="[x1, y1, x2, y2]" data-label="Text<p>contenu</p></div<
        // On doit adapter le parsing à ce format

        // Regex adaptée au format Chandra:
        // - data-bbox="[x1, y1, x2, y2]"
        // - data-label="Label<p> (le " et > sont fusionnés avec <p>)
        // - contenu jusqu'à </p></div (sans le > final parfois)
        let divPattern = #"<div\s+data-bbox\s*=\s*"\[(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\]"\s+data-label="[^"<]*<p>([\s\S]*?)</p></div"#

        guard let regex = try? NSRegularExpression(
            pattern: divPattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 6 else { continue }

            // Extraire les coordonnées
            guard let x1Range = Range(match.range(at: 1), in: html),
                  let y1Range = Range(match.range(at: 2), in: html),
                  let x2Range = Range(match.range(at: 3), in: html),
                  let y2Range = Range(match.range(at: 4), in: html),
                  let contentRange = Range(match.range(at: 5), in: html),
                  let x1 = Double(String(html[x1Range])),
                  let y1 = Double(String(html[y1Range])),
                  let x2 = Double(String(html[x2Range])),
                  let y2 = Double(String(html[y2Range])) else {
                continue
            }

            // Mettre à l'échelle vers les coordonnées réelles
            let scaledX1 = max(0, CGFloat(x1) * widthScaler)
            let scaledY1 = max(0, CGFloat(y1) * heightScaler)
            let scaledX2 = min(CGFloat(x2) * widthScaler, imageWidth)
            let scaledY2 = min(CGFloat(y2) * heightScaler, imageHeight)

            let width = scaledX2 - scaledX1
            let height = scaledY2 - scaledY1

            guard width > 0, height > 0 else { continue }

            // Extraire et nettoyer le texte
            let rawContent = String(html[contentRange])
            let text = stripHTMLTags(rawContent).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }

            boxes.append(BoundingBox(
                rect: CGRect(x: scaledX1, y: scaledY1, width: width, height: height),
                text: text,
                confidence: 0.9
            ))
        }

        return boxes
    }

    /// Calcule la taille de redimensionnement en préservant l'aspect ratio
    private func calculateResizePreservingAspectRatio(
        width: CGFloat,
        height: CGFloat,
        maxDimension: CGFloat
    ) -> CGSize {
        let aspectRatio = width / height

        if width > height {
            // Image horizontale
            let newWidth = min(width, maxDimension)
            let newHeight = newWidth / aspectRatio
            return CGSize(width: newWidth, height: newHeight)
        } else {
            // Image verticale ou carrée
            let newHeight = min(height, maxDimension)
            let newWidth = newHeight * aspectRatio
            return CGSize(width: newWidth, height: newHeight)
        }
    }

    /// Améliore l'image pour une meilleure reconnaissance de l'écriture manuscrite
    private func enhanceImageForOCR(_ image: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: image)

        // Pipeline de filtres pour améliorer le contraste de l'écriture manuscrite
        guard let contrastFilter = CIFilter(name: "CIColorControls") else {
            return image
        }

        contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.2, forKey: kCIInputContrastKey)  // Augmenter le contraste
        contrastFilter.setValue(0.0, forKey: kCIInputSaturationKey)  // Désaturer (noir & blanc)
        contrastFilter.setValue(0.05, forKey: kCIInputBrightnessKey)  // Légèrement plus lumineux

        guard let contrastOutput = contrastFilter.outputImage else {
            return image
        }

        // Sharpening pour rendre les traits plus nets
        guard let sharpenFilter = CIFilter(name: "CISharpenLuminance") else {
            return renderCIImage(contrastOutput, size: CGSize(width: image.width, height: image.height)) ?? image
        }

        sharpenFilter.setValue(contrastOutput, forKey: kCIInputImageKey)
        sharpenFilter.setValue(0.5, forKey: kCIInputSharpnessKey)  // Netteté modérée

        guard let finalOutput = sharpenFilter.outputImage else {
            return renderCIImage(contrastOutput, size: CGSize(width: image.width, height: image.height)) ?? image
        }

        return renderCIImage(finalOutput, size: CGSize(width: image.width, height: image.height)) ?? image
    }

    /// Convertit une CIImage en CGImage
    private func renderCIImage(_ ciImage: CIImage, size: CGSize) -> CGImage? {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(ciImage, from: CGRect(origin: .zero, size: size))
    }

    /// Supprime les tags HTML d'une chaîne
    private func stripHTMLTags(_ html: String) -> String {
        var result = html

        // Remplacer <br> par des espaces
        result = result.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: .regularExpression)

        // Supprimer tous les autres tags
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // Décoder les entités HTML basiques
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")

        // Normaliser les espaces
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return result
    }
}

// MARK: - Errors

enum ChandraMLXError: LocalizedError {
    case modelNotLoaded
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Le modèle Chandra n'est pas chargé"
        case .inferenceError(let message):
            return "Erreur d'inférence Chandra: \(message)"
        }
    }
}
