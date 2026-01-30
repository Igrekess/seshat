import Foundation
import AppKit
import PDFKit

/// Options for PDF export
struct PDFExportOptions {
    var includeAnswers: Bool = false
    var includePoints: Bool = true
    var includeRubric: Bool = false
    var includeStudentFields: Bool = true

    static let `default` = PDFExportOptions()
    static let withAnswers = PDFExportOptions(includeAnswers: true, includePoints: true, includeRubric: true, includeStudentFields: false)
}

/// Service for exporting tests to PDF format
@MainActor
final class TestPDFExportService {
    static let shared = TestPDFExportService()

    private init() {}

    // MARK: - Constants

    private let pageWidth: CGFloat = 595   // A4 width in points
    private let pageHeight: CGFloat = 842  // A4 height in points
    private let marginLeft: CGFloat = 45
    private let marginRight: CGFloat = 45
    private let marginTop: CGFloat = 40
    private let marginBottom: CGFloat = 50
    private let lineSpacing: CGFloat = 5

    // Colors
    private var primaryColor: NSColor { NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 1.0) }
    private var lightGrayBg: NSColor { NSColor(calibratedWhite: 0.96, alpha: 1.0) }
    private var borderColor: NSColor { NSColor(calibratedWhite: 0.85, alpha: 1.0) }

    // MARK: - PDF Export

    /// Export a test to PDF and save to the specified URL
    func exportToPDF(_ test: Test, to url: URL, options: PDFExportOptions = .default) throws {
        let pdfData = generatePDFData(for: test, options: options)

        do {
            try pdfData.write(to: url)
        } catch {
            throw PDFExportError.writeFailed
        }
    }

    /// Export a test to PDF and prompt user for save location
    func exportWithSavePanel(_ test: Test, options: PDFExportOptions = .default) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = test.title.sanitizedForFilename + ".pdf"
        savePanel.title = "Exporter le test en PDF"
        savePanel.message = "Choisissez l'emplacement pour sauvegarder le PDF"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try exportToPDF(test, to: url, options: options)
                NSWorkspace.shared.open(url)
            } catch {
                // Silently fail - the save panel already shows errors
            }
        }
    }

    // MARK: - PDF Generation

    private func generatePDFData(for test: Test, options: PDFExportOptions) -> Data {
        let pdfData = NSMutableData()
        let contentWidth = pageWidth - marginLeft - marginRight

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        var yPosition: CGFloat = 0

        // Start first page
        context.beginPDFPage(nil)
        yPosition = pageHeight - marginTop

        // Draw header with title and metadata
        yPosition = drawHeader(test: test, options: options, at: yPosition, width: contentWidth, in: context)

        // Draw student info fields if enabled
        if options.includeStudentFields {
            yPosition = drawStudentInfoFields(at: yPosition, width: contentWidth, in: context)
        }

        // Draw separator line
        yPosition -= 10
        drawHorizontalLine(at: yPosition, in: context)
        yPosition -= 20

        // Draw questions
        for (index, question) in test.sortedQuestions.enumerated() {
            let questionNumber = index + 1

            // Estimate if we need a new page
            let estimatedHeight = estimateQuestionHeight(question, width: contentWidth, options: options)
            if yPosition - estimatedHeight < marginBottom {
                context.endPDFPage()
                context.beginPDFPage(nil)
                yPosition = pageHeight - marginTop
            }

            yPosition = drawQuestion(question, number: questionNumber, at: CGPoint(x: marginLeft, y: yPosition), width: contentWidth, in: context, options: options)
            yPosition -= 18
        }

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    // MARK: - Header Drawing

    private func drawHeader(test: Test, options: PDFExportOptions, at yPosition: CGFloat, width: CGFloat, in context: CGContext) -> CGFloat {
        var currentY = yPosition

        // Title with accent color
        let titleFont = NSFont.boldSystemFont(ofSize: 22)
        let titleText = test.title.isEmpty ? "Sans titre" : test.title
        currentY = drawText(titleText, font: titleFont, color: primaryColor, at: CGPoint(x: marginLeft, y: currentY), width: width, in: context, centered: true)
        currentY -= 8

        // Metadata line
        var metadataParts: [String] = []
        if !test.subject.isEmpty {
            metadataParts.append(test.subject)
        }
        if !test.gradeLevel.isEmpty {
            metadataParts.append(test.gradeLevel)
        }

        if !metadataParts.isEmpty {
            let metadataText = metadataParts.joined(separator: " - ")
            let metadataFont = NSFont.systemFont(ofSize: 12, weight: .medium)
            currentY = drawText(metadataText, font: metadataFont, color: .darkGray, at: CGPoint(x: marginLeft, y: currentY), width: width, in: context, centered: true)
            currentY -= 6
        }

        // Points, question count and duration
        var statsText = "\(test.questions.count) question\(test.questions.count > 1 ? "s" : "")"
        if options.includePoints {
            statsText += " • Total: \(String(format: "%.0f", test.calculatedTotalPoints)) points"
        }
        if let duration = test.duration, duration > 0 {
            statsText += " • Durée: \(duration) min"
        }
        let statsFont = NSFont.systemFont(ofSize: 10)
        currentY = drawText(statsText, font: statsFont, color: .gray, at: CGPoint(x: marginLeft, y: currentY), width: width, in: context, centered: true)
        currentY -= 15

        return currentY
    }

    // MARK: - Student Info Fields

    private func drawStudentInfoFields(at yPosition: CGFloat, width: CGFloat, in context: CGContext) -> CGFloat {
        let boxHeight: CGFloat = 70
        let boxY = yPosition - boxHeight
        let boxRect = CGRect(x: marginLeft, y: boxY, width: width, height: boxHeight)

        // Draw rounded background box
        context.saveGState()
        let path = CGPath(roundedRect: boxRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.setFillColor(lightGrayBg.cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
        context.restoreGState()

        // Field layout: 2 columns
        let fieldLabelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let fieldLineColor = NSColor.darkGray

        let col1X = marginLeft + 15
        let col2X = marginLeft + width / 2 + 15
        let colWidth = width / 2 - 30

        // Row 1 - Nom / Prénom
        let row1Y = boxY + boxHeight - 25
        let nomLabelWidth: CGFloat = 38
        let prenomLabelWidth: CGFloat = 55

        drawFieldLabel("Nom :", at: CGPoint(x: col1X, y: row1Y), font: fieldLabelFont, in: context)
        drawFieldLine(at: CGPoint(x: col1X + nomLabelWidth, y: row1Y - 10), width: colWidth - nomLabelWidth, color: fieldLineColor, in: context)

        drawFieldLabel("Prénom :", at: CGPoint(x: col2X, y: row1Y), font: fieldLabelFont, in: context)
        drawFieldLine(at: CGPoint(x: col2X + prenomLabelWidth, y: row1Y - 10), width: colWidth - prenomLabelWidth, color: fieldLineColor, in: context)

        // Row 2 - Classe / Date
        let row2Y = boxY + boxHeight - 50
        let classeLabelWidth: CGFloat = 48
        let dateLabelWidth: CGFloat = 38

        drawFieldLabel("Classe :", at: CGPoint(x: col1X, y: row2Y), font: fieldLabelFont, in: context)
        drawFieldLine(at: CGPoint(x: col1X + classeLabelWidth, y: row2Y - 10), width: colWidth - classeLabelWidth, color: fieldLineColor, in: context)

        drawFieldLabel("Date :", at: CGPoint(x: col2X, y: row2Y), font: fieldLabelFont, in: context)
        drawFieldLine(at: CGPoint(x: col2X + dateLabelWidth, y: row2Y - 10), width: colWidth - dateLabelWidth, color: fieldLineColor, in: context)

        return boxY - 10
    }

    private func drawFieldLabel(_ text: String, at point: CGPoint, font: NSFont, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.darkGray
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()

        context.saveGState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        // Draw text so baseline aligns with the line
        attrString.draw(at: NSPoint(x: point.x, y: point.y - textSize.height + 2))
        context.restoreGState()
    }

    private func drawFieldLine(at point: CGPoint, width: CGFloat, color: NSColor, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.5)
        context.move(to: point)
        context.addLine(to: CGPoint(x: point.x + width, y: point.y))
        context.strokePath()
        context.restoreGState()
    }

    private func drawHorizontalLine(at y: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: marginLeft, y: y))
        context.addLine(to: CGPoint(x: pageWidth - marginRight, y: y))
        context.strokePath()
        context.restoreGState()
    }

    private func drawText(_ text: String, font: NSFont, color: NSColor, at point: CGPoint, width: CGFloat, in context: CGContext, centered: Bool = false) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = centered ? .center : .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)

        // Calculate text height
        let textRect = attributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let textHeight = ceil(textRect.height)

        // Draw in flipped coordinate system
        context.saveGState()

        // Create a flipped graphics context for text drawing
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        let drawRect = CGRect(x: point.x, y: point.y - textHeight, width: width, height: textHeight)
        attributedString.draw(in: drawRect)

        context.restoreGState()

        return point.y - textHeight - lineSpacing
    }

    private func drawQuestion(_ question: Question, number: Int, at point: CGPoint, width: CGFloat, in context: CGContext, options: PDFExportOptions) -> CGFloat {
        var currentY = point.y
        let questionIndent: CGFloat = 28

        // Draw question number badge (circle with number)
        let badgeSize: CGFloat = 22
        let badgeCenterX = point.x + badgeSize / 2
        let badgeCenterY = currentY - badgeSize / 2 - 2

        context.saveGState()
        context.setFillColor(primaryColor.cgColor)
        context.fillEllipse(in: CGRect(x: badgeCenterX - badgeSize / 2, y: badgeCenterY - badgeSize / 2, width: badgeSize, height: badgeSize))
        context.restoreGState()

        // Draw number in badge
        let numberFont = NSFont.boldSystemFont(ofSize: 11)
        let numberStr = "\(number)"
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.white
        ]
        let numberAttr = NSAttributedString(string: numberStr, attributes: numberAttrs)
        let numberSize = numberAttr.size()

        context.saveGState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        numberAttr.draw(at: NSPoint(x: badgeCenterX - numberSize.width / 2, y: badgeCenterY - numberSize.height / 2))
        context.restoreGState()

        // Points badge (if enabled)
        let headerX = point.x + questionIndent
        let headerWidth = width - questionIndent

        if options.includePoints {
            let pointsText = String(format: "%.0f pt", question.points)
            let pointsFont = NSFont.systemFont(ofSize: 9, weight: .medium)
            let pointsAttrs: [NSAttributedString.Key: Any] = [
                .font: pointsFont,
                .foregroundColor: NSColor.darkGray
            ]
            let pointsAttr = NSAttributedString(string: pointsText, attributes: pointsAttrs)
            let pointsSize = pointsAttr.size()

            // Draw points pill
            let pillPadding: CGFloat = 6
            let pillHeight: CGFloat = 16
            let pillWidth = pointsSize.width + pillPadding * 2
            let pillX = point.x + width - pillWidth
            let pillY = currentY - pillHeight - 3

            context.saveGState()
            let pillPath = CGPath(roundedRect: CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight), cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil)
            context.addPath(pillPath)
            context.setFillColor(lightGrayBg.cgColor)
            context.fillPath()
            context.restoreGState()

            context.saveGState()
            let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsCtx
            pointsAttr.draw(at: NSPoint(x: pillX + pillPadding, y: pillY + (pillHeight - pointsSize.height) / 2))
            context.restoreGState()
        }

        // Question text - clean it from any raw LLM artifacts
        currentY -= 5
        let cleanedQuestionText = cleanQuestionText(question.text)
        let questionText = cleanedQuestionText.isEmpty ? "(Question vide)" : cleanedQuestionText
        let questionFont = NSFont.systemFont(ofSize: 11.5)
        currentY = drawText(questionText, font: questionFont, color: .black, at: CGPoint(x: headerX, y: currentY), width: headerWidth - (options.includePoints ? 50 : 0), in: context)
        currentY -= 8

        // Options for MCQ
        if question.type == .multipleChoice, let mcqOptions = question.options, !mcqOptions.isEmpty {
            let labels = ["A", "B", "C", "D"]
            let optionFont = NSFont.systemFont(ofSize: 10.5)

            // Filter and clean options - only keep valid ones (max 4, no artifacts)
            let cleanedOptions = cleanMCQOptions(mcqOptions)

            for (index, option) in cleanedOptions.prefix(4).enumerated() {
                let label = labels[index]
                let isCorrectAndShown = options.includeAnswers && option.isCorrect
                let checkbox = isCorrectAndShown ? "●" : "○"
                var optionText = "\(checkbox)  \(label).  \(option.text)"
                if isCorrectAndShown {
                    optionText += "  ✓"
                }
                let textColor: NSColor = isCorrectAndShown ? NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.3, alpha: 1.0) : .black
                currentY = drawText(optionText, font: optionFont, color: textColor, at: CGPoint(x: headerX + 10, y: currentY), width: headerWidth - 20, in: context)
            }
        }

        // Answer lines for short answer / open ended
        if question.type == .shortAnswer {
            currentY -= 5
            if options.includeAnswers, let expected = question.expectedAnswer, !expected.isEmpty {
                let answerFont = NSFont.systemFont(ofSize: 10, weight: .medium)
                currentY = drawText("Réponse : \(expected)", font: answerFont, color: NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.3, alpha: 1.0), at: CGPoint(x: headerX, y: currentY), width: headerWidth, in: context)
            } else {
                drawAnswerLine(at: CGPoint(x: headerX, y: currentY), width: headerWidth, in: context)
                currentY -= 22
            }
        } else if question.type == .openEnded {
            currentY -= 5
            if options.includeAnswers, let expected = question.expectedAnswer, !expected.isEmpty {
                let answerFont = NSFont.systemFont(ofSize: 10, weight: .medium)
                currentY = drawText("Réponse attendue : \(expected)", font: answerFont, color: NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.3, alpha: 1.0), at: CGPoint(x: headerX, y: currentY), width: headerWidth, in: context)
            } else {
                // Draw lined area for open response
                for i in 0..<4 {
                    let lineY = currentY - CGFloat(i) * 18
                    drawAnswerLine(at: CGPoint(x: headerX, y: lineY), width: headerWidth, in: context)
                }
                currentY -= 72
            }

            // Rubric guidelines (only if includeAnswers AND includeRubric)
            if options.includeAnswers && options.includeRubric, let rubric = question.rubricGuidelines, !rubric.isEmpty {
                currentY -= 8
                let rubricLabelFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
                currentY = drawText("Critères de notation :", font: rubricLabelFont, color: .darkGray, at: CGPoint(x: headerX, y: currentY), width: headerWidth, in: context)
                let rubricFont = NSFont.systemFont(ofSize: 9)
                currentY = drawText(rubric, font: rubricFont, color: .gray, at: CGPoint(x: headerX, y: currentY), width: headerWidth, in: context)
            }
        } else if question.type == .trueFalse {
            currentY -= 5
            let tfFont = NSFont.systemFont(ofSize: 10.5)
            // Use correctAnswer field for True/False questions
            if options.includeAnswers {
                let isTrue = question.correctAnswer ?? true
                let tfText = isTrue ? "●  Vrai          ○  Faux" : "○  Vrai          ●  Faux"
                currentY = drawText(tfText, font: tfFont, color: NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.3, alpha: 1.0), at: CGPoint(x: headerX + 10, y: currentY), width: headerWidth - 10, in: context)
            } else {
                currentY = drawText("○  Vrai          ○  Faux", font: tfFont, color: .black, at: CGPoint(x: headerX + 10, y: currentY), width: headerWidth - 10, in: context)
            }
        }

        return currentY
    }

    /// Clean MCQ options from LLM artifacts
    private func cleanMCQOptions(_ options: [MCQOption]) -> [MCQOption] {
        var cleaned: [MCQOption] = []

        for option in options {
            let text = option.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty options
            if text.isEmpty {
                continue
            }

            // Skip options that are clearly artifacts
            let lowerText = text.lowercased()
            if lowerText.contains("expected") ||
               lowerText.contains("rubric") ||
               lowerText == "expected:" ||
               lowerText == "rubric:" ||
               text.hasPrefix("EXPECTED") ||
               text.hasPrefix("RUBRIC") {
                continue
            }

            // Skip options that start with numbers followed by closing paren (like "7. RUBRIC:")
            if text.range(of: #"^\d+[\.\)]"#, options: .regularExpression) != nil {
                continue
            }

            // Skip if it looks like a duplicate label (E., F., etc. followed by content we already have)
            if text.range(of: #"^[E-Za-z]\s*[\.\)]\s*"#, options: .regularExpression) != nil &&
               text.range(of: #"^[A-Da-d]\s*[\.\)]"#, options: .regularExpression) == nil {
                // This is E), F), etc. - might be an artifact, check content
                let contentWithoutLabel = text.replacingOccurrences(of: #"^[E-Za-z]\s*[\.\)]\s*"#, with: "", options: .regularExpression)
                if contentWithoutLabel.lowercased().contains("expected") ||
                   contentWithoutLabel.lowercased().contains("rubric") ||
                   contentWithoutLabel.isEmpty {
                    continue
                }
            }

            // Clean the option text - remove any leading label if present (B) By the time... -> By the time...)
            var cleanedText = text
            if let labelRange = cleanedText.range(of: #"^[A-Da-d]\s*[\.\)]\s*"#, options: .regularExpression) {
                cleanedText = String(cleanedText[labelRange.upperBound...])
            }

            // Remove answer markers
            cleanedText = cleanedText.withoutAnswerMarkers

            if !cleanedText.isEmpty {
                cleaned.append(MCQOption(id: option.id, text: cleanedText, isCorrect: option.isCorrect))
            }

            // Stop after 4 valid options
            if cleaned.count >= 4 {
                break
            }
        }

        return cleaned
    }

    /// Clean question text from raw LLM artifacts
    private func cleanQuestionText(_ text: String) -> String {
        var cleaned = text

        // First, find the first option pattern and cut everything from there
        // This handles cases where options start with A), A., a), etc.
        let firstOptionPatterns = [
            #"(?:^|\n)\s*[Aa]\s*[\.\)]\s*"#,  // A) or A. at start of line
            #"(?:^|\n)\s*OPTIONS\s*:"#,        // OPTIONS: marker
            #"(?:^|\n)\s*EXPECTED\s*:"#,       // EXPECTED: marker
            #"(?:^|\n)\s*RUBRIC\s*:"#          // RUBRIC: marker
        ]

        for pattern in firstOptionPatterns {
            if let range = cleaned.range(of: pattern, options: .regularExpression) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }

        // Remove any remaining answer markers that might be inline
        cleaned = cleaned.withoutAnswerMarkers

        // If the text still contains obvious option patterns inline, try to clean them
        // Pattern: text followed by A) option B) option etc on the same line or following lines
        let lines = cleaned.components(separatedBy: .newlines)
        var cleanLines: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            // Skip lines that look like options (start with A), B), C), D) or similar)
            if trimmedLine.range(of: #"^[A-Da-d]\s*[\.\)]"#, options: .regularExpression) != nil {
                continue
            }
            // Skip lines that are just "True" or "False"
            if trimmedLine.lowercased() == "true" || trimmedLine.lowercased() == "false" ||
               trimmedLine.lowercased() == "vrai" || trimmedLine.lowercased() == "faux" {
                continue
            }
            cleanLines.append(line)
        }

        cleaned = cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private func drawAnswerLine(at point: CGPoint, width: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor(calibratedWhite: 0.75, alpha: 1.0).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: point.x, y: point.y))
        context.addLine(to: CGPoint(x: point.x + width, y: point.y))
        context.strokePath()
        context.restoreGState()
    }

    private func estimateQuestionHeight(_ question: Question, width: CGFloat, options: PDFExportOptions) -> CGFloat {
        let questionIndent: CGFloat = 28
        let effectiveWidth = width - questionIndent
        var height: CGFloat = 45 // Badge, spacing

        // Text height estimate using cleaned text (rough: ~55 chars per line at 11.5pt)
        let cleanedText = cleanQuestionText(question.text)
        let charsPerLine = max(1, Int(effectiveWidth / 6.5))
        let textLines = max(1, Int(ceil(Double(cleanedText.count) / Double(charsPerLine))))
        height += CGFloat(textLines * 16)

        // Options for MCQ (use cleaned options count, max 4)
        if question.type == .multipleChoice, let mcqOptions = question.options {
            let cleanedCount = min(cleanMCQOptions(mcqOptions).count, 4)
            height += CGFloat(cleanedCount * 18)
        }

        // Answer space
        if question.type == .shortAnswer {
            if options.includeAnswers, let expected = question.expectedAnswer, !expected.isEmpty {
                let answerLines = max(1, Int(ceil(Double(expected.count) / Double(charsPerLine))))
                height += CGFloat(answerLines * 16)
            } else {
                height += 28
            }
        } else if question.type == .openEnded {
            if options.includeAnswers, let expected = question.expectedAnswer, !expected.isEmpty {
                let answerLines = max(1, Int(ceil(Double(expected.count) / Double(charsPerLine))))
                height += CGFloat(answerLines * 16)
            } else {
                height += 80 // 4 lines
            }
            if options.includeRubric, let rubric = question.rubricGuidelines, !rubric.isEmpty {
                let rubricLines = max(1, Int(ceil(Double(rubric.count) / Double(charsPerLine))))
                height += CGFloat(rubricLines * 14) + 15
            }
        } else if question.type == .trueFalse {
            height += 22
        }

        return height
    }

}

// MARK: - Errors

enum PDFExportError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            return "Impossible d'écrire le fichier PDF"
        }
    }
}
