import Foundation
import AppKit

/// Service for batch processing OCR and analysis on multiple submissions
@MainActor
@Observable
final class BatchProcessingService {
    static let shared = BatchProcessingService()

    // MARK: - State

    private(set) var isProcessing = false
    private(set) var currentTask: String = ""
    private(set) var currentSubTask: String = ""
    private(set) var progress: Double = 0
    private(set) var processedCount: Int = 0
    private(set) var totalCount: Int = 0
    private(set) var errors: [BatchError] = []
    private(set) var completedItems: [CompletedItem] = []

    // For image-level progress
    private(set) var currentImageIndex: Int = 0
    private(set) var totalImagesInSubmission: Int = 0

    // For accurate overall progress (counting all images)
    private var totalImagesOverall: Int = 0
    private var processedImagesOverall: Int = 0

    // Timing
    private(set) var startTime: Date?
    var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    struct BatchError: Identifiable {
        let id = UUID()
        let submissionId: UUID
        let studentName: String
        let error: String
        let timestamp: Date = Date()
    }

    struct CompletedItem: Identifiable {
        let id = UUID()
        let studentName: String
        let type: ItemType
        let detail: String
        let timestamp: Date = Date()

        enum ItemType {
            case ocr
            case analysis
        }
    }

    // MARK: - Pause/Resume State

    private(set) var isPaused = false
    private var shouldCancel = false

    func pause() {
        isPaused = true
        currentSubTask = "En pause..."
    }

    func resume() {
        isPaused = false
        currentSubTask = ""
    }

    // MARK: - Batch OCR

    /// Run OCR on all pending submissions for an assignment
    func runBatchOCR(for assignmentId: UUID) async {
        let dataStore = DataStore.shared
        let submissions = dataStore.getSubmissions(forAssignment: assignmentId)
            .filter { $0.status == .pending && !$0.imagePaths.isEmpty }

        guard !submissions.isEmpty else { return }

        await runBatchOCR(submissions: submissions)
    }

    /// Run OCR on specific submissions
    func runBatchOCR(submissions: [StudentSubmission]) async {
        guard !submissions.isEmpty else { return }

        isProcessing = true
        isPaused = false
        shouldCancel = false
        currentTask = "Transcription OCR"
        currentSubTask = ""
        progress = 0
        processedCount = 0
        totalCount = submissions.count
        errors = []
        completedItems = []
        startTime = Date()

        // Calculate total images for accurate progress
        totalImagesOverall = submissions.reduce(0) { $0 + $1.imagePaths.count }
        processedImagesOverall = 0

        let dataStore = DataStore.shared
        let factory = HTRServiceFactory()
        let (htrService, _) = await factory.createBestAvailableService()

        for (index, submission) in submissions.enumerated() {
            // Check for cancellation
            if shouldCancel {
                currentTask = "Annulé"
                break
            }

            // Wait while paused
            while isPaused && !shouldCancel {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            let student = dataStore.getStudent(by: submission.studentId)
            let studentName = student?.fullName ?? "Élève inconnu"

            currentTask = "OCR: \(studentName)"
            currentSubTask = "Copie \(index + 1)/\(totalCount)"

            // Reset image progress for this submission
            currentImageIndex = 0
            totalImagesInSubmission = submission.imagePaths.count

            do {
                var allBoxes: [BoundingBox] = []
                var totalProcessingTime: TimeInterval = 0

                // Process each image with progress tracking
                for (imageIndex, imagePath) in submission.imagePaths.enumerated() {
                    // Check for pause/cancel between images
                    while isPaused && !shouldCancel {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    if shouldCancel { break }

                    currentImageIndex = imageIndex + 1
                    currentSubTask = "Image \(imageIndex + 1)/\(submission.imagePaths.count) • Copie \(index + 1)/\(totalCount)"

                    // Update overall progress based on images processed
                    progress = Double(processedImagesOverall) / Double(max(totalImagesOverall, 1))

                    guard let image = dataStore.loadImage(relativePath: imagePath),
                          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        throw BatchProcessingError.imageLoadFailed(imagePath)
                    }

                    // Apply crop if defined for this image
                    let imageToProcess: CGImage
                    if let cropInfo = submission.cropSettings?.first(where: { $0.imageIndex == imageIndex }) {
                        // Denormalize crop rect to pixel coordinates
                        let cropRect = CGRect(
                            x: cropInfo.rect.origin.x * CGFloat(cgImage.width),
                            y: cropInfo.rect.origin.y * CGFloat(cgImage.height),
                            width: cropInfo.rect.size.width * CGFloat(cgImage.width),
                            height: cropInfo.rect.size.height * CGFloat(cgImage.height)
                        )

                        // Ensure crop rect is within bounds
                        let safeCropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

                        if let croppedImage = cgImage.cropping(to: safeCropRect) {
                            imageToProcess = croppedImage
                        } else {
                            imageToProcess = cgImage
                        }
                    } else {
                        imageToProcess = cgImage
                    }

                    let result = try await htrService.transcribe(imageToProcess)
                    allBoxes.append(contentsOf: result.boundingBoxes)
                    totalProcessingTime += result.processingTime

                    // Update overall progress
                    processedImagesOverall += 1
                    progress = Double(processedImagesOverall) / Double(max(totalImagesOverall, 1))
                }

                if shouldCancel { break }

                // Create combined transcription result
                let transcription = TranscriptionResult(
                    boundingBoxes: allBoxes,
                    modelLevel: htrService.modelLevel,
                    processingTime: totalProcessingTime
                )

                // Update submission immediately
                var updatedSubmission = submission
                updatedSubmission.transcription = transcription
                updatedSubmission.status = .transcribed
                dataStore.updateSubmission(updatedSubmission)

                // Add to completed items
                completedItems.append(CompletedItem(
                    studentName: studentName,
                    type: .ocr,
                    detail: "\(allBoxes.count) blocs • \(String(format: "%.1fs", totalProcessingTime))"
                ))

            } catch {
                errors.append(BatchError(
                    submissionId: submission.id,
                    studentName: studentName,
                    error: error.localizedDescription
                ))
            }

            processedCount = index + 1
        }

        progress = 1.0
        currentTask = shouldCancel ? "Annulé" : "OCR terminé"
        currentSubTask = "\(processedCount - errors.count)/\(totalCount) réussis"
        isProcessing = false
        isPaused = false
    }

    // MARK: - Batch Analysis

    /// Run analysis on all transcribed submissions for an assignment
    func runBatchAnalysis(for assignmentId: UUID) async {
        let dataStore = DataStore.shared
        let submissions = dataStore.getSubmissions(forAssignment: assignmentId)
            .filter { $0.status == .transcribed && $0.transcription != nil }

        guard !submissions.isEmpty else { return }

        await runBatchAnalysis(submissions: submissions, assignmentId: assignmentId)
    }

    /// Run analysis on specific submissions
    func runBatchAnalysis(submissions: [StudentSubmission], assignmentId: UUID? = nil) async {
        guard !submissions.isEmpty else { return }

        isProcessing = true
        isPaused = false
        shouldCancel = false
        currentTask = "Analyse linguistique"
        currentSubTask = ""
        progress = 0
        processedCount = 0
        totalCount = submissions.count
        errors = []
        completedItems = []
        currentImageIndex = 0
        totalImagesInSubmission = 0
        startTime = Date()
        totalImagesOverall = submissions.count  // For analysis, 1 "image" = 1 submission
        processedImagesOverall = 0

        let dataStore = DataStore.shared
        let analysisService = QwenAnalysisService.shared

        // Get rubric for grading
        var rubric: GradingRubric?
        if let assignmentId = assignmentId,
           let assignment = dataStore.getAssignment(by: assignmentId),
           let rubricId = assignment.rubricId {
            rubric = dataStore.getRubric(by: rubricId)
        }
        // Fall back to first available rubric
        if rubric == nil {
            rubric = dataStore.rubrics.first
        }

        for (index, submission) in submissions.enumerated() {
            // Check for cancellation
            if shouldCancel {
                currentTask = "Annulé"
                break
            }

            // Wait while paused
            while isPaused && !shouldCancel {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            let student = dataStore.getStudent(by: submission.studentId)
            let studentName = student?.fullName ?? "Élève inconnu"

            currentTask = "Analyse: \(studentName)"
            currentSubTask = "Copie \(index + 1)/\(totalCount)"
            progress = Double(processedImagesOverall) / Double(max(totalImagesOverall, 1))

            guard let transcription = submission.transcription else {
                errors.append(BatchError(
                    submissionId: submission.id,
                    studentName: studentName,
                    error: "Pas de transcription disponible"
                ))
                processedCount = index + 1
                continue
            }

            do {
                let text = transcription.fullText
                let analysis = try await analysisService.analyze(text)

                // Calculate grade if rubric available
                var calculatedGrade: Double?
                if let rubric = rubric {
                    calculatedGrade = rubric.calculateGrade(
                        grammarErrors: analysis.errorCount(for: .grammar),
                        spellingErrors: analysis.errorCount(for: .spelling),
                        vocabularyErrors: analysis.errorCount(for: .vocabulary),
                        syntaxErrors: analysis.errorCount(for: .syntax)
                    )
                }

                // Update submission immediately
                var updatedSubmission = submission
                updatedSubmission.analysis = analysis
                updatedSubmission.grade = calculatedGrade
                updatedSubmission.status = calculatedGrade != nil ? .graded : .analyzed
                dataStore.updateSubmission(updatedSubmission)

                // Add to completed items
                let gradeStr = calculatedGrade.map { String(format: "%.1f", $0) } ?? "-"
                completedItems.append(CompletedItem(
                    studentName: studentName,
                    type: .analysis,
                    detail: "\(analysis.totalErrors) erreurs • Note: \(gradeStr)"
                ))

                // Update progress
                processedImagesOverall += 1
                progress = Double(processedImagesOverall) / Double(max(totalImagesOverall, 1))

            } catch {
                errors.append(BatchError(
                    submissionId: submission.id,
                    studentName: studentName,
                    error: error.localizedDescription
                ))
            }

            processedCount = index + 1
        }

        progress = 1.0
        currentTask = shouldCancel ? "Annulé" : "Analyse terminée"
        currentSubTask = "\(processedCount - errors.count)/\(totalCount) réussis"
        isProcessing = false
        isPaused = false
    }

    // MARK: - Full Pipeline

    /// Run complete pipeline (OCR + Analysis) on all pending submissions
    func runFullPipeline(for assignmentId: UUID) async {
        let dataStore = DataStore.shared

        // First, run OCR on pending submissions
        let pendingSubmissions = dataStore.getSubmissions(forAssignment: assignmentId)
            .filter { $0.status == .pending && !$0.imagePaths.isEmpty }

        if !pendingSubmissions.isEmpty {
            await runBatchOCR(submissions: pendingSubmissions)
        }

        // Then, run analysis on transcribed submissions
        let transcribedSubmissions = dataStore.getSubmissions(forAssignment: assignmentId)
            .filter { $0.status == .transcribed && $0.transcription != nil }

        if !transcribedSubmissions.isEmpty {
            await runBatchAnalysis(submissions: transcribedSubmissions, assignmentId: assignmentId)
        }
    }

    // MARK: - Cancel

    func cancel() {
        shouldCancel = true
        isPaused = false
        currentSubTask = "Arrêt en cours..."
    }

    /// Clear completed items history
    func clearHistory() {
        completedItems = []
        errors = []
    }
}

// MARK: - Errors

enum BatchProcessingError: LocalizedError {
    case imageLoadFailed(String)
    case noTranscription
    case analysisFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let path):
            return "Impossible de charger l'image: \(path)"
        case .noTranscription:
            return "Pas de transcription disponible"
        case .analysisFailed(let reason):
            return "Analyse échouée: \(reason)"
        }
    }
}
