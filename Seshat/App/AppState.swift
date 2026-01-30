import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class AppState {
    // MARK: - Navigation State
    var currentStep: WorkflowStep = .import
    var showImportDialog = false
    var showExportDialog = false

    // MARK: - Document State
    var currentCopy: StudentCopy?
    var transcriptionResult: TranscriptionResult?
    var analysisResult: AnalysisResult?
    var cropRegion: CGRect?  // Zone de crop en coordonnées normalisées (0-1)
    var cropRotation: Double = 0  // Rotation du crop en degrés (valeur libre pour redresser le texte)
    var imageRotation: Int = 0  // Rotation de l'image en degrés (0, 90, 180, 270)

    // MARK: - Processing State
    var isProcessing = false
    var processingProgress: Double = 0
    var processingMessage: String = ""

    // MARK: - Error State
    var currentError: SeshatError?
    var showErrorAlert = false

    // MARK: - Edit State
    var editHistory: [TranscriptionResult] = []
    var editHistoryIndex: Int = -1

    // MARK: - Services
    let htrServiceFactory: HTRServiceFactory
    let analysisService: QwenAnalysisService
    let pdfExportService: PDFExportService
    let modelDownloadService: ModelDownloadService

    init() {
        self.htrServiceFactory = HTRServiceFactory()
        self.analysisService = QwenAnalysisService.shared
        self.pdfExportService = PDFExportService()
        self.modelDownloadService = ModelDownloadService.shared
    }

    var configService: ConfigurationService {
        ConfigurationService.shared
    }

    // MARK: - Computed Properties
    var canUndo: Bool {
        editHistoryIndex > 0
    }

    var canRedo: Bool {
        editHistoryIndex < editHistory.count - 1
    }

    // MARK: - Actions
    func importImage(_ data: Data, filename: String) {
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            showError(.invalidImageFormat)
            return
        }

        let copy = StudentCopy(
            imageData: data,
            originalFilename: filename,
            cgImage: cgImage
        )

        currentCopy = copy
        transcriptionResult = nil
        analysisResult = nil
        editHistory = []
        editHistoryIndex = -1
        currentStep = .import
    }

    func startTranscription() async {
        guard let cgImage = currentCopy?.cgImage else {
            showError(.invalidImageFormat)
            return
        }

        isProcessing = true
        processingMessage = "Chargement du modèle HTR..."
        processingProgress = 0.1

        let imageToProcess = applyImageTransforms(to: cgImage)

        do {
            let (service, level) = await htrServiceFactory.createBestAvailableService()
            processingMessage = "Transcription en cours (\(level.displayName))..."
            processingProgress = 0.3

            let result = try await service.transcribe(imageToProcess)

            processingProgress = 1.0
            transcriptionResult = result
            editHistory = [result]
            editHistoryIndex = 0
            currentStep = .transcription

            // Check for low confidence warning
            if result.overallConfidence < 0.6 {
                showError(.lowConfidenceWarning(confidence: result.overallConfidence))
            }
        } catch {
            showError(.transcriptionFailed(underlying: error))
        }

        isProcessing = false
        processingProgress = 0
        processingMessage = ""
    }

    func validateTranscription() {
        guard transcriptionResult != nil else { return }
        currentStep = .validation
    }

    func startAnalysis() async {
        guard let transcription = transcriptionResult else { return }

        isProcessing = true
        processingMessage = "Chargement du modèle d'analyse..."
        processingProgress = 0.2

        do {
            if !analysisService.isAvailable {
                processingMessage = "Modèle d'analyse non disponible. Veuillez le télécharger dans les paramètres."
                showError(.analysisTimeout)
                isProcessing = false
                return
            }

            processingMessage = "Analyse linguistique en cours..."
            processingProgress = 0.5

            let result = try await analysisService.analyze(transcription.fullText)

            processingProgress = 1.0
            analysisResult = result
            currentStep = .analysis
        } catch {
            showError(.analysisTimeout)
        }

        isProcessing = false
        processingProgress = 0
        processingMessage = ""
    }

    func updateTranscription(_ newResult: TranscriptionResult) {
        // Add to edit history
        if editHistoryIndex < editHistory.count - 1 {
            editHistory = Array(editHistory.prefix(editHistoryIndex + 1))
        }
        editHistory.append(newResult)
        editHistoryIndex = editHistory.count - 1
        transcriptionResult = newResult
    }

    func undo() {
        guard canUndo else { return }
        editHistoryIndex -= 1
        transcriptionResult = editHistory[editHistoryIndex]
    }

    func redo() {
        guard canRedo else { return }
        editHistoryIndex += 1
        transcriptionResult = editHistory[editHistoryIndex]
    }

    func deleteCopy() {
        currentCopy = nil
        transcriptionResult = nil
        analysisResult = nil
        editHistory = []
        editHistoryIndex = -1
        cropRegion = nil
        cropRotation = 0
        imageRotation = 0
        currentStep = .import
    }

    private func showError(_ error: SeshatError) {
        currentError = error
        showErrorAlert = true
    }

    private func rotateImage(_ image: CGImage, degrees: Int) -> CGImage? {
        let normalizedDegrees = ((degrees % 360) + 360) % 360
        guard normalizedDegrees != 0 else { return image }

        let radians = CGFloat(normalizedDegrees) * .pi / 180

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Calculate new size after rotation
        let newWidth: CGFloat
        let newHeight: CGFloat
        if normalizedDegrees == 90 || normalizedDegrees == 270 {
            newWidth = height
            newHeight = width
        } else {
            newWidth = width
            newHeight = height
        }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: Int(newWidth),
            height: Int(newHeight),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }

        context.translateBy(x: newWidth / 2, y: newHeight / 2)
        context.rotate(by: radians)
        context.translateBy(x: -width / 2, y: -height / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    /// Rotate image by arbitrary angle (for crop rotation to straighten text)
    private func rotateImageArbitrary(_ image: CGImage, degrees: Double) -> CGImage? {
        guard abs(degrees) > 0.01 else { return image }

        let radians = CGFloat(degrees) * .pi / 180

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Calculate bounding box of rotated image
        let sinVal = abs(sin(radians))
        let cosVal = abs(cos(radians))
        let newWidth = width * cosVal + height * sinVal
        let newHeight = width * sinVal + height * cosVal

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: Int(ceil(newWidth)),
            height: Int(ceil(newHeight)),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }

        // Set white background (for the corners after rotation)
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        context.translateBy(x: newWidth / 2, y: newHeight / 2)
        context.rotate(by: radians)
        context.translateBy(x: -width / 2, y: -height / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    func rotateImageLeft() {
        imageRotation = (imageRotation - 90 + 360) % 360
    }

    func rotateImageRight() {
        imageRotation = (imageRotation + 90) % 360
    }

    /// Returns the processed image (rotated + cropped) for display in subsequent steps
    var processedImage: NSImage? {
        guard let cgImage = currentCopy?.cgImage else { return nil }
        let finalImage = applyImageTransforms(to: cgImage)
        return NSImage(cgImage: finalImage, size: NSSize(width: finalImage.width, height: finalImage.height))
    }

    /// Applies rotation, crop, and crop rotation transforms to an image
    private func applyImageTransforms(to cgImage: CGImage) -> CGImage {
        // Step 1: Apply 90° image rotation
        var result = cgImage
        if imageRotation != 0, let rotated = rotateImage(cgImage, degrees: imageRotation) {
            result = rotated
        }

        // Step 2: Apply crop region
        if let crop = cropRegion {
            let pixelRect = CGRect(
                x: crop.origin.x * CGFloat(result.width),
                y: crop.origin.y * CGFloat(result.height),
                width: crop.width * CGFloat(result.width),
                height: crop.height * CGFloat(result.height)
            )
            if let cropped = result.cropping(to: pixelRect) {
                result = cropped
            }
        }

        // Step 3: Apply crop rotation (arbitrary angle to straighten text)
        if abs(cropRotation) > 0.01, let rotated = rotateImageArbitrary(result, degrees: cropRotation) {
            result = rotated
        }

        return result
    }
}

// MARK: - Workflow Step
enum WorkflowStep: Int, CaseIterable, Sendable {
    case `import` = 0
    case transcription = 1
    case validation = 2
    case analysis = 3
    case export = 4

    var title: String {
        switch self {
        case .import: return "Import"
        case .transcription: return "Transcription"
        case .validation: return "Validation"
        case .analysis: return "Analyse"
        case .export: return "Export"
        }
    }

    var icon: String {
        switch self {
        case .import: return "square.and.arrow.down"
        case .transcription: return "text.viewfinder"
        case .validation: return "checkmark.circle"
        case .analysis: return "magnifyingglass"
        case .export: return "square.and.arrow.up"
        }
    }
}
