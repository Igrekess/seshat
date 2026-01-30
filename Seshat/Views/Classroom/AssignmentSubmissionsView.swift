import SwiftUI
import UniformTypeIdentifiers
import Combine

/// View for managing all submissions for an assignment
struct AssignmentSubmissionsView: View {
    @Binding var assignment: Assignment
    @Binding var selectedStudent: Student?
    var onBack: (() -> Void)? = nil
    @State private var dataStore = DataStore.shared
    @State private var batchService = BatchProcessingService.shared
    @State private var showingImportImages = false
    @State private var selectedStudentForImport: Student?

    var students: [Student] {
        dataStore.getStudents(for: assignment.classId)
    }

    var submissions: [StudentSubmission] {
        dataStore.getSubmissions(forAssignment: assignment.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with batch actions
            AssignmentHeader(
                assignment: assignment,
                onBack: onBack,
                onRunOCR: { Task { await batchService.runBatchOCR(for: assignment.id) } },
                onRunAnalysis: { Task { await batchService.runBatchAnalysis(for: assignment.id) } },
                onRunFullPipeline: { Task { await batchService.runFullPipeline(for: assignment.id) } }
            )

            Divider()

            // Progress indicator
            if batchService.isProcessing {
                BatchProgressView()
            }

            // Student submissions list
            List(students, selection: $selectedStudent) { student in
                SubmissionRow(
                    student: student,
                    submission: getSubmission(for: student),
                    onImportImages: {
                        selectedStudentForImport = student
                        showingImportImages = true
                    }
                )
                .tag(student)
            }
            .listStyle(.inset)
        }
        .navigationTitle(assignment.title)
        .fileImporter(
            isPresented: $showingImportImages,
            allowedContentTypes: [.image, .jpeg, .png, .heic],
            allowsMultipleSelection: true
        ) { result in
            handleImageImport(result)
        }
    }

    private func getSubmission(for student: Student) -> StudentSubmission? {
        dataStore.getSubmission(for: student.id, assignmentId: assignment.id)
    }

    private func handleImageImport(_ result: Result<[URL], Error>) {
        guard let student = selectedStudentForImport else { return }

        switch result {
        case .success(let urls):
            importImages(urls, for: student)
        case .failure:
            break
        }

        selectedStudentForImport = nil
    }

    private func importImages(_ urls: [URL], for student: Student) {
        // Get or create submission
        var submission = dataStore.getSubmission(for: student.id, assignmentId: assignment.id)
            ?? StudentSubmission(studentId: student.id, assignmentId: assignment.id)

        // Import each image
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            if let relativePath = dataStore.importImage(from: url, for: submission.id) {
                submission.imagePaths.append(relativePath)
            }
        }

        submission.status = .pending

        // Save submission
        if dataStore.getSubmission(by: submission.id) != nil {
            dataStore.updateSubmission(submission)
        } else {
            dataStore.addSubmission(submission)
        }
    }
}

// MARK: - Assignment Header

struct AssignmentHeader: View {
    let assignment: Assignment
    var onBack: (() -> Void)? = nil
    let onRunOCR: () -> Void
    let onRunAnalysis: () -> Void
    let onRunFullPipeline: () -> Void

    @State private var dataStore = DataStore.shared
    @State private var batchService = BatchProcessingService.shared
    @State private var showingExportCSV = false
    @State private var showingExportPronote = false

    var pendingCount: Int {
        dataStore.getSubmissions(forAssignment: assignment.id)
            .filter { $0.status == .pending && !$0.imagePaths.isEmpty }.count
    }

    var transcribedCount: Int {
        dataStore.getSubmissions(forAssignment: assignment.id)
            .filter { $0.status == .transcribed }.count
    }

    var gradedCount: Int {
        dataStore.getSubmissions(forAssignment: assignment.id)
            .filter { $0.finalGrade != nil }.count
    }

    var totalCount: Int {
        dataStore.getSubmissions(forAssignment: assignment.id).count
    }

    var body: some View {
        HStack(spacing: 12) {
            // Back button
            if let onBack = onBack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Retour à la liste des devoirs")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.title)
                    .font(.title3)
                    .bold()
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(pendingCount) en attente", systemImage: "clock")
                    Label("\(transcribedCount) transcrits", systemImage: "doc.text")
                    Label("\(gradedCount)/\(totalCount) notés", systemImage: "star.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Batch action buttons - compact style
            HStack(spacing: 8) {
                Button {
                    onRunOCR()
                } label: {
                    Image(systemName: "text.viewfinder")
                }
                .disabled(pendingCount == 0 || batchService.isProcessing)
                .help("OCR - Transcrire toutes les copies en attente")

                Button {
                    onRunAnalysis()
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .disabled(transcribedCount == 0 || batchService.isProcessing)
                .help("Analyser toutes les copies transcrites")

                Button {
                    onRunFullPipeline()
                } label: {
                    Label("Tout tra...", systemImage: "bolt.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled((pendingCount == 0 && transcribedCount == 0) || batchService.isProcessing)
                .help("OCR + Analyse sur toutes les copies")

                Menu {
                    Button {
                        showingExportPronote = true
                    } label: {
                        Label("Export PRONOTE (notes + appréciations)", systemImage: "tablecells")
                    }

                    Button {
                        showingExportCSV = true
                    } label: {
                        Label("Export CSV (détaillé)", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(gradedCount == 0)
                .help("Exporter les notes")
            }
        }
        .padding()
        .background(.bar)
        .fileExporter(
            isPresented: $showingExportCSV,
            document: GradesCSVDocument(csvContent: generateGradesCSV(assignment: assignment, dataStore: dataStore)),
            contentType: .commaSeparatedText,
            defaultFilename: "\(assignment.title)_notes.csv"
        ) { _ in }
        .fileExporter(
            isPresented: $showingExportPronote,
            document: PronoteCSVDocument(csvContent: generatePronoteCSV(assignment: assignment, dataStore: dataStore)),
            contentType: .tabSeparatedText,
            defaultFilename: "\(assignment.title)_pronote.txt"
        ) { _ in }
    }
}

// MARK: - CSV Documents

struct GradesCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let csvContent: String

    init(csvContent: String) {
        self.csvContent = csvContent
    }

    init(configuration: ReadConfiguration) throws {
        csvContent = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = csvContent.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

/// Document CSV compatible PRONOTE (séparateur tabulation, encodage UTF-16)
struct PronoteCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.tabSeparatedText] }

    let csvContent: String

    init(csvContent: String) {
        self.csvContent = csvContent
    }

    init(configuration: ReadConfiguration) throws {
        csvContent = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // UTF-16 Little Endian avec BOM pour compatibilité PRONOTE
        var data = Data()
        // BOM UTF-16 LE
        data.append(contentsOf: [0xFF, 0xFE])
        if let contentData = csvContent.data(using: .utf16LittleEndian) {
            data.append(contentData)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

// Helper to generate CSV content
@MainActor
func generateGradesCSV(assignment: Assignment, dataStore: DataStore) -> String {
    var csv = "Élève,Note,Note Max,Erreurs Grammaire,Erreurs Orthographe,Erreurs Vocabulaire,Erreurs Syntaxe,Total Erreurs,Statut\n"

    let students = dataStore.getStudents(for: assignment.classId)
    for student in students {
        if let submission = dataStore.getSubmission(for: student.id, assignmentId: assignment.id) {
            let grade = submission.finalGrade.map { String(format: "%.1f", $0) } ?? ""
            let grammarErrors = submission.analysis?.errorCount(for: .grammar) ?? 0
            let spellingErrors = submission.analysis?.errorCount(for: .spelling) ?? 0
            let vocabularyErrors = submission.analysis?.errorCount(for: .vocabulary) ?? 0
            let syntaxErrors = submission.analysis?.errorCount(for: .syntax) ?? 0
            let totalErrors = submission.analysis?.totalErrors ?? 0
            let status = submission.status.displayName

            csv += "\"\(student.fullName)\",\(grade),\(Int(assignment.maxScore)),\(grammarErrors),\(spellingErrors),\(vocabularyErrors),\(syntaxErrors),\(totalErrors),\(status)\n"
        } else {
            csv += "\"\(student.fullName)\",,\(Int(assignment.maxScore)),,,,,,Pas de copie\n"
        }
    }

    return csv
}

/// Génère un CSV compatible PRONOTE (séparateur tabulation, colonnes Nom/Prénom/Note/Appréciation)
@MainActor
func generatePronoteCSV(assignment: Assignment, dataStore: DataStore) -> String {
    // En-tête avec la note max comme titre de colonne (format PRONOTE)
    var csv = "Nom\tPrénom\tNote/\(Int(assignment.maxScore))\tAppréciation\n"

    let students = dataStore.getStudents(for: assignment.classId)
        .sorted { $0.lastName < $1.lastName }

    for student in students {
        let submission = dataStore.getSubmission(for: student.id, assignmentId: assignment.id)

        let grade = submission?.finalGrade.map { String(format: "%.1f", $0) } ?? ""
        let appreciation = buildAppreciation(from: submission)

        // Échapper les tabulations dans les champs
        let cleanLastName = student.lastName.replacingOccurrences(of: "\t", with: " ")
        let cleanFirstName = student.firstName.replacingOccurrences(of: "\t", with: " ")
        let cleanAppreciation = appreciation.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")

        csv += "\(cleanLastName)\t\(cleanFirstName)\t\(grade)\t\(cleanAppreciation)\n"
    }

    return csv
}

/// Construit l'appréciation condensée pour PRONOTE (max 300 caractères)
private func buildAppreciation(from submission: StudentSubmission?) -> String {
    guard let submission = submission else { return "" }

    var parts: [String] = []

    // Notes du professeur (prioritaires, en premier)
    if !submission.teacherNotes.isEmpty {
        parts.append(submission.teacherNotes)
    }

    // Appréciation globale de l'IA
    if let feedback = submission.analysis?.globalFeedback {
        parts.append(feedback.overallAssessment)

        // Ajouter un résumé des points forts si place disponible
        if !feedback.strengths.isEmpty {
            let strengthsSummary = "Points forts: " + feedback.strengths.prefix(2).joined(separator: ", ")
            parts.append(strengthsSummary)
        }
    }

    let result = parts.joined(separator: " ")

    // Limiter à 300 caractères (limite pratique PRONOTE)
    if result.count > 300 {
        return String(result.prefix(297)) + "..."
    }
    return result
}

// MARK: - Batch Progress

struct BatchProgressView: View {
    @State private var batchService = BatchProcessingService.shared
    @State private var showCompletedItems = true
    @State private var elapsedTimeString = "0:00"

    // Use a TimelineView for automatic updates
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Main progress bar
            VStack(spacing: 8) {
                HStack {
                    // Status indicator
                    if batchService.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(batchService.currentTask)
                            .font(.caption)
                            .fontWeight(.medium)

                        if !batchService.currentSubTask.isEmpty {
                            Text(batchService.currentSubTask)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Counters and timing
                    HStack(spacing: 12) {
                        // Elapsed time
                        Label(elapsedTimeString, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        if batchService.processedCount > 0 {
                            Label("\(batchService.processedCount - batchService.errors.count)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }

                        if !batchService.errors.isEmpty {
                            Label("\(batchService.errors.count)", systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }

                        Text("\(batchService.processedCount)/\(batchService.totalCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    // Control buttons
                    HStack(spacing: 4) {
                        // Pause/Resume button
                        Button {
                            if batchService.isPaused {
                                batchService.resume()
                            } else {
                                batchService.pause()
                            }
                        } label: {
                            Image(systemName: batchService.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                .font(.title3)
                                .foregroundStyle(batchService.isPaused ? .green : .orange)
                        }
                        .buttonStyle(.plain)
                        .help(batchService.isPaused ? "Reprendre" : "Mettre en pause")

                        // Cancel button
                        Button {
                            batchService.cancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Arrêter")
                    }
                }

                ProgressView(value: batchService.progress)
                    .progressViewStyle(.linear)
                    .tint(batchService.isPaused ? .orange : .accentColor)
            }
            .padding()
            .background(batchService.isPaused ? Color.orange.opacity(0.1) : Color.accentColor.opacity(0.1))

            // Completed items list (collapsible)
            if !batchService.completedItems.isEmpty {
                Divider()

                VStack(spacing: 0) {
                    // Header
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCompletedItems.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: showCompletedItems ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Text("Terminés (\(batchService.completedItems.count))")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)

                    if showCompletedItems {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(batchService.completedItems.suffix(10).reversed()) { item in
                                    HStack(spacing: 8) {
                                        Image(systemName: item.type == .ocr ? "text.viewfinder" : "wand.and.stars")
                                            .font(.caption)
                                            .foregroundStyle(item.type == .ocr ? .blue : .purple)
                                            .frame(width: 16)

                                        Text(item.studentName)
                                            .font(.caption)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(item.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)

                                    Divider()
                                        .padding(.leading, 32)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .onReceive(timer) { _ in
            updateElapsedTime()
        }
        .onAppear {
            updateElapsedTime()
        }
    }

    private func updateElapsedTime() {
        let elapsed = batchService.elapsedTime
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        elapsedTimeString = String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Submission Row

struct SubmissionRow: View {
    let student: Student
    let submission: StudentSubmission?
    let onImportImages: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Student info
            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName)
                    .font(.headline)

                if let submission = submission {
                    HStack(spacing: 8) {
                        StatusBadge(status: submission.status)

                        if submission.imagePaths.count > 0 {
                            Text("\(submission.imagePaths.count) image\(submission.imagePaths.count > 1 ? "s" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let errorCount = submission.analysis?.totalErrors {
                            Text("\(errorCount) erreur\(errorCount > 1 ? "s" : "")")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Pas de copie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Grade
            if let grade = submission?.finalGrade {
                GradeBadge(grade: grade, maxGrade: 20)
            }

            // Import button
            Button {
                onImportImages()
            } label: {
                Image(systemName: "photo.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Importer des images")
        }
        .padding(.vertical, 6)
    }
}

struct StatusBadge: View {
    let status: SubmissionStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
            Text(status.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color(hex: status.color)?.opacity(0.2) ?? Color.gray.opacity(0.2))
        .foregroundStyle(Color(hex: status.color) ?? .gray)
        .cornerRadius(4)
    }
}

struct GradeBadge: View {
    let grade: Double
    let maxGrade: Double

    var color: Color {
        let ratio = grade / maxGrade
        switch ratio {
        case 0..<0.4: return .red
        case 0.4..<0.5: return .orange
        case 0.5..<0.6: return .yellow
        case 0.6..<0.7: return .green
        default: return .blue
        }
    }

    var body: some View {
        Text(String(format: "%.1f", grade))
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)

        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}

#Preview {
    AssignmentSubmissionsView(
        assignment: .constant(Assignment(title: "Test Assignment", classId: UUID())),
        selectedStudent: .constant(nil)
    )
}
