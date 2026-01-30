import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Service for extracting text from various document formats to use as context
@MainActor
final class DocumentContextService {
    static let shared = DocumentContextService()

    private init() {}

    // MARK: - Supported Types

    static let supportedTextTypes: [UTType] = [
        .pdf,
        .plainText,
        .utf8PlainText,
        .rtf,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data
    ]

    static let supportedImageTypes: [UTType] = [
        .png,
        .jpeg,
        .heic,
        .tiff,
        .webP
    ]

    static var supportedTypes: [UTType] {
        supportedTextTypes + supportedImageTypes
    }

    static var supportedExtensions: [String] {
        ["pdf", "txt", "md", "markdown", "rtf", "docx", "png", "jpg", "jpeg", "heic", "tiff", "webp"]
    }

    static var supportedTextExtensions: [String] {
        ["pdf", "txt", "md", "markdown", "rtf", "docx"]
    }

    static var supportedImageExtensions: [String] {
        ["png", "jpg", "jpeg", "heic", "tiff", "webp"]
    }

    // MARK: - Document Extraction

    /// Extract text content from a file URL
    func extractText(from url: URL) throws -> DocumentContext {
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent

        let content: String

        switch ext {
        case "pdf":
            content = try extractFromPDF(url)
        case "txt", "md", "markdown":
            content = try String(contentsOf: url, encoding: .utf8)
        case "rtf":
            content = try extractFromRTF(url)
        case "docx":
            content = try extractFromDOCX(url)
        default:
            // Try plain text as fallback
            content = try String(contentsOf: url, encoding: .utf8)
        }

        let wordCount = content.split(separator: " ").count
        let estimatedTokens = Int(Double(wordCount) * 1.3) // Rough estimate

        return DocumentContext(
            filename: filename,
            content: content,
            wordCount: wordCount,
            estimatedTokens: estimatedTokens,
            sourceURL: url
        )
    }

    /// Extract text from multiple files
    func extractText(from urls: [URL]) throws -> [DocumentContext] {
        try urls.map { try extractText(from: $0) }
    }

    // MARK: - Image OCR Extraction

    /// Extract text from an image using Chandra OCR
    func extractTextFromImage(url: URL) async throws -> DocumentContext {
        let filename = url.lastPathComponent
        let imageData = try Data(contentsOf: url)

        guard let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DocumentExtractionError.cannotOpenFile(filename)
        }

        return try await extractTextFromImage(cgImage: cgImage, filename: filename, imageData: imageData)
    }

    /// Extract text from a CGImage using Chandra OCR
    func extractTextFromImage(cgImage: CGImage, filename: String, imageData: Data) async throws -> DocumentContext {
        // Use ChandraMLXService for OCR
        let chandraService = ChandraMLXService.shared

        let result = try await chandraService.transcribe(cgImage)

        // Combine all extracted text from bounding boxes
        let extractedText = result.boundingBoxes.map { $0.text }.joined(separator: "\n\n")

        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DocumentExtractionError.noTextContent(filename)
        }

        let wordCount = extractedText.split(separator: " ").count
        let estimatedTokens = Int(Double(wordCount) * 1.3)

        return DocumentContext(
            filename: filename,
            content: extractedText,
            wordCount: wordCount,
            estimatedTokens: estimatedTokens,
            sourceType: .image,
            originalImageData: imageData
        )
    }

    /// Check if a file is an image based on extension
    func isImageFile(_ url: URL) -> Bool {
        Self.supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Smart extraction that auto-detects file type
    func extractContent(from url: URL) async throws -> DocumentContext {
        if isImageFile(url) {
            return try await extractTextFromImage(url: url)
        } else {
            return try extractText(from: url)
        }
    }

    // MARK: - Format-Specific Extraction

    private func extractFromPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentExtractionError.cannotOpenFile(url.lastPathComponent)
        }

        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                if let pageText = page.string {
                    text += pageText + "\n\n"
                }
            }
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DocumentExtractionError.noTextContent(url.lastPathComponent)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractFromRTF(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        guard let attributedString = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            throw DocumentExtractionError.cannotOpenFile(url.lastPathComponent)
        }

        return attributedString.string
    }

    private func extractFromDOCX(_ url: URL) throws -> String {
        // DOCX is a zip file containing XML
        // We'll extract the main document.xml and parse it

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Unzip the DOCX
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            task.arguments = ["-q", url.path, "-d", tempDir.path]
            try task.run()
            task.waitUntilExit()
        } catch {
            throw DocumentExtractionError.cannotOpenFile(url.lastPathComponent)
        }

        // Read document.xml
        let documentPath = tempDir.appendingPathComponent("word/document.xml")

        guard fileManager.fileExists(atPath: documentPath.path) else {
            throw DocumentExtractionError.invalidFormat(url.lastPathComponent)
        }

        let xmlData = try Data(contentsOf: documentPath)
        let xmlString = String(data: xmlData, encoding: .utf8) ?? ""

        // Simple extraction: get text between <w:t> tags
        let pattern = #"<w:t[^>]*>([^<]+)</w:t>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(xmlString.startIndex..., in: xmlString)

        var extractedText = ""
        regex.enumerateMatches(in: xmlString, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range(at: 1),
               let swiftRange = Range(matchRange, in: xmlString) {
                extractedText += xmlString[swiftRange] + " "
            }
        }

        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DocumentExtractionError.noTextContent(url.lastPathComponent)
        }

        return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - File Pickers

    /// Show an open panel to select documents (text files only)
    func showDocumentPicker() -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedTextTypes.compactMap { $0 }
        panel.message = "Sélectionnez les documents à utiliser comme contexte"
        panel.prompt = "Ajouter"

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls
    }

    /// Show an open panel to select images
    func showImagePicker() -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedImageTypes.compactMap { $0 }
        panel.message = "Sélectionnez les images à OCR (photos de cours, manuels scannés...)"
        panel.prompt = "Ajouter"

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls
    }

    /// Show an open panel to select any supported file (text or image)
    func showAllFilesPicker() -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedTypes.compactMap { $0 }
        panel.message = "Sélectionnez les documents ou images à utiliser comme contexte"
        panel.prompt = "Ajouter"

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls
    }
}

// MARK: - Errors

enum DocumentExtractionError: LocalizedError {
    case cannotOpenFile(String)
    case noTextContent(String)
    case invalidFormat(String)
    case fileTooLarge(String, Int)

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let name):
            return "Impossible d'ouvrir le fichier '\(name)'"
        case .noTextContent(let name):
            return "Aucun texte extractible dans '\(name)'"
        case .invalidFormat(let name):
            return "Format non reconnu pour '\(name)'"
        case .fileTooLarge(let name, let tokens):
            return "Le fichier '\(name)' est trop volumineux (\(tokens) tokens estimés)"
        }
    }
}
