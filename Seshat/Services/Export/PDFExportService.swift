import Foundation
import AppKit
import PDFKit

/// Service for exporting annotated copies to PDF
@MainActor
final class PDFExportService {

    func exportToPDF(
        copy: StudentCopy,
        transcription: TranscriptionResult,
        analysis: AnalysisResult,
        options: ExportOptions,
        processedImage: NSImage? = nil
    ) async throws -> URL {
        // Use processed image if provided, otherwise fall back to original
        guard let image = processedImage ?? copy.nsImage else {
            throw SeshatError.invalidImageFormat
        }

        // Create PDF document
        let pdfDocument = PDFDocument()

        // Page 1: Image de la copie
        if let imagePage = createImagePage(image: image) {
            pdfDocument.insert(imagePage, at: 0)
        }

        // Page 2: Transcription and statistics
        if let statsPage = createStatsPage(transcription: transcription, analysis: analysis, options: options) {
            pdfDocument.insert(statsPage, at: 1)
        }

        // Save to destination
        let outputURL = options.destinationURL ?? generateDefaultOutputURL(for: copy)

        guard pdfDocument.write(to: outputURL) else {
            throw SeshatError.exportFailed(path: outputURL.path)
        }

        return outputURL
    }

    private func createImagePage(image: NSImage) -> PDFPage? {
        let pageSize = CGSize(width: 612, height: 792) // US Letter

        let pdfPage = NSImage(size: pageSize)
        pdfPage.lockFocus()

        // Draw white background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: pageSize).fill()

        // Calculate image rect (with margins)
        let margin: CGFloat = 40
        let availableWidth = pageSize.width - (margin * 2)
        let availableHeight = pageSize.height - (margin * 2)

        let imageAspect = image.size.width / image.size.height
        var imageRect: NSRect

        if imageAspect > availableWidth / availableHeight {
            let width = availableWidth
            let height = width / imageAspect
            imageRect = NSRect(x: margin, y: pageSize.height - margin - height, width: width, height: height)
        } else {
            let height = availableHeight
            let width = height * imageAspect
            imageRect = NSRect(x: margin, y: pageSize.height - margin - height, width: width, height: height)
        }

        // Draw image
        image.draw(in: imageRect)

        pdfPage.unlockFocus()

        // Convert NSImage to PDFPage
        guard let tiffData = pdfPage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]),
              let nsImage = NSImage(data: pngData) else {
            return nil
        }

        return PDFPage(image: nsImage)
    }

    private func createStatsPage(
        transcription: TranscriptionResult,
        analysis: AnalysisResult,
        options: ExportOptions
    ) -> PDFPage? {
        let pageSize = CGSize(width: 612, height: 792)
        let pdfPage = NSImage(size: pageSize)
        pdfPage.lockFocus()

        NSColor.white.setFill()
        NSRect(origin: .zero, size: pageSize).fill()

        let margin: CGFloat = 40
        var yPosition = pageSize.height - margin

        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]
        "Récapitulatif de la correction".draw(at: NSPoint(x: margin, y: yPosition - 18), withAttributes: titleAttributes)
        yPosition -= 40

        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.darkGray
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.black
        ]
        let smallAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.gray
        ]

        // Summary stats
        "Résumé: \(analysis.totalErrors) erreur(s)".draw(at: NSPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
        yPosition -= 18

        let config = ConfigurationService.shared.loadPreferences()
        var xPos = margin
        for category in ErrorCategory.allCases {
            let count = analysis.errorCount(for: category)
            if count > 0 {
                let color = NSColor(hex: config.categoryColors[category] ?? category.defaultColor) ?? .gray
                color.setFill()
                NSBezierPath(rect: NSRect(x: xPos, y: yPosition, width: 10, height: 10)).fill()
                let statText = "\(category.displayName): \(count)"
                statText.draw(at: NSPoint(x: xPos + 14, y: yPosition - 2), withAttributes: smallAttributes)
                xPos += 100
            }
        }
        yPosition -= 25

        // Detailed errors by category
        for category in ErrorCategory.allCases {
            let categoryErrors = analysis.errors.filter { $0.category == category }
            guard !categoryErrors.isEmpty else { continue }

            // Category header
            let color = NSColor(hex: config.categoryColors[category] ?? category.defaultColor) ?? .gray
            color.setFill()
            NSBezierPath(rect: NSRect(x: margin, y: yPosition, width: 12, height: 12)).fill()

            let catHeader = "\(category.displayName) (\(categoryErrors.count))"
            catHeader.draw(at: NSPoint(x: margin + 16, y: yPosition - 2), withAttributes: headerAttributes)
            yPosition -= 20

            // List each error
            for error in categoryErrors {
                guard yPosition > margin + 40 else { break } // Don't overflow

                // Error: text → correction
                let errorText = "• \"\(error.text)\" → \"\(error.correction ?? "?")\""
                let errorAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: color
                ]
                errorText.draw(at: NSPoint(x: margin + 10, y: yPosition), withAttributes: errorAttributes)
                yPosition -= 14

                // Explanation
                error.explanation.draw(at: NSPoint(x: margin + 20, y: yPosition), withAttributes: smallAttributes)
                yPosition -= 16
            }
            yPosition -= 8
        }

        // Global feedback section (if available)
        if let feedback = analysis.globalFeedback, yPosition > 200 {
            yPosition -= 10

            // Feedback header with grade
            let feedbackHeader = "Appréciation du professeur"
            feedbackHeader.draw(at: NSPoint(x: margin, y: yPosition), withAttributes: headerAttributes)

            if let grade = feedback.suggestedGrade {
                let gradeAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: NSColor.systemBlue
                ]
                grade.draw(at: NSPoint(x: pageSize.width - margin - 60, y: yPosition), withAttributes: gradeAttributes)
            }
            yPosition -= 18

            // Overall assessment
            feedback.overallAssessment.draw(at: NSPoint(x: margin, y: yPosition), withAttributes: bodyAttributes)
            yPosition -= 30

            // Strengths
            if !feedback.strengths.isEmpty && yPosition > 150 {
                let strengthsHeader: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.systemGreen
                ]
                "Points forts:".draw(at: NSPoint(x: margin, y: yPosition), withAttributes: strengthsHeader)
                yPosition -= 14

                for strength in feedback.strengths.prefix(3) {
                    "• \(strength)".draw(at: NSPoint(x: margin + 10, y: yPosition), withAttributes: smallAttributes)
                    yPosition -= 12
                }
            }

            // Areas for improvement
            if !feedback.areasForImprovement.isEmpty && yPosition > 120 {
                let improvementHeader: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.systemOrange
                ]
                yPosition -= 4
                "Axes d'amélioration:".draw(at: NSPoint(x: margin, y: yPosition), withAttributes: improvementHeader)
                yPosition -= 14

                for area in feedback.areasForImprovement.prefix(3) {
                    "• \(area)".draw(at: NSPoint(x: margin + 10, y: yPosition), withAttributes: smallAttributes)
                    yPosition -= 12
                }
            }

            // Encouragement
            if yPosition > 80 {
                yPosition -= 8
                let encouragementFont = NSFontManager.shared.convert(
                    NSFont.systemFont(ofSize: 10),
                    toHaveTrait: .italicFontMask
                )
                let encouragementAttributes: [NSAttributedString.Key: Any] = [
                    .font: encouragementFont,
                    .foregroundColor: NSColor.purple
                ]
                feedback.encouragement.draw(at: NSPoint(x: margin, y: yPosition), withAttributes: encouragementAttributes)
                yPosition -= 20
            }
        }

        // Transcription section (if space)
        if yPosition > 100 {
            yPosition -= 10
            "Transcription".draw(at: NSPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
            yPosition -= 18

            let transcriptionText = transcription.fullText
            let textRect = NSRect(x: margin, y: margin + 40, width: pageSize.width - margin * 2, height: yPosition - margin - 40)
            transcriptionText.draw(in: textRect, withAttributes: bodyAttributes)
        }

        // Footer
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.gray
        ]
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "fr_FR")

        let footerText = "Généré par Seshat le \(dateFormatter.string(from: Date()))"
        footerText.draw(at: NSPoint(x: margin, y: margin / 2), withAttributes: footerAttributes)

        pdfPage.unlockFocus()

        guard let tiffData = pdfPage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]),
              let nsImage = NSImage(data: pngData) else {
            return nil
        }

        return PDFPage(image: nsImage)
    }

    private func generateDefaultOutputURL(for copy: StudentCopy) -> URL {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let filename = copy.originalFilename.replacingOccurrences(of: ".", with: "_corrected.")
        return desktopURL.appendingPathComponent("\(filename).pdf")
    }
}

// MARK: - Export Options
struct ExportOptions: Codable, Sendable {
    var includeOriginalImage: Bool = true
    var includeTranscription: Bool = true
    var includeStatistics: Bool = true
    var includeLegend: Bool = true
    var destinationURL: URL?

    enum CodingKeys: String, CodingKey {
        case includeOriginalImage = "include_original_image"
        case includeTranscription = "include_transcription"
        case includeStatistics = "include_statistics"
        case includeLegend = "include_legend"
    }
}

// MARK: - NSColor Extension
extension NSColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)

        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}
