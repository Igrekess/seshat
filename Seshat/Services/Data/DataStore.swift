import Foundation
import AppKit

/// Centralized data store for all school-related data
/// Uses JSON file-based persistence in ~/Library/Application Support/Seshat/data/
@MainActor
@Observable
final class DataStore {
    static let shared = DataStore()

    // MARK: - Data Collections

    private(set) var classes: [SchoolClass] = []
    private(set) var students: [Student] = []
    private(set) var assignments: [Assignment] = []
    private(set) var submissions: [StudentSubmission] = []
    private(set) var rubrics: [GradingRubric] = []
    private(set) var tests: [Test] = []

    // MARK: - File Paths

    private let dataDirectory: URL
    private let classesFile: URL
    private let studentsFile: URL
    private let assignmentsFile: URL
    private let submissionsFile: URL
    private let rubricsFile: URL
    private let testsFile: URL
    private let imagesDirectory: URL

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        dataDirectory = appSupport.appendingPathComponent("Seshat/data")
        classesFile = dataDirectory.appendingPathComponent("classes.json")
        studentsFile = dataDirectory.appendingPathComponent("students.json")
        assignmentsFile = dataDirectory.appendingPathComponent("assignments.json")
        submissionsFile = dataDirectory.appendingPathComponent("submissions.json")
        rubricsFile = dataDirectory.appendingPathComponent("rubrics.json")
        testsFile = dataDirectory.appendingPathComponent("tests.json")
        imagesDirectory = dataDirectory.appendingPathComponent("images")

        // Create directories
        try? FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true
        )

        // Load all data
        loadAll()

        // Create default rubric if none exists
        if rubrics.isEmpty {
            createDefaultRubric()
        }
    }

    // MARK: - Load/Save

    func loadAll() {
        classes = load(from: classesFile) ?? []
        students = load(from: studentsFile) ?? []
        assignments = load(from: assignmentsFile) ?? []
        submissions = load(from: submissionsFile) ?? []
        rubrics = load(from: rubricsFile) ?? []
        tests = (load(from: testsFile) as [Test]?) ?? []
    }

    func saveAll() {
        save(classes, to: classesFile)
        save(students, to: studentsFile)
        save(assignments, to: assignmentsFile)
        save(submissions, to: submissionsFile)
        save(rubrics, to: rubricsFile)
        save(tests, to: testsFile)
    }

    private func load<T: Codable>(from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch is DecodingError {
            // Backup corrupted file for recovery
            let backupURL = url.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.copyItem(at: url, to: backupURL)
            return nil
        } catch {
            return nil
        }
    }

    private func save<T: Codable>(_ data: T, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(data)

            // Atomic write: write to temp file first, then rename
            let tempURL = url.deletingPathExtension().appendingPathExtension("tmp.json")
            try jsonData.write(to: tempURL, options: .atomic)

            // Remove existing file and rename temp
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            // Silent fail - data persistence errors are handled gracefully
        }
    }

    // MARK: - Class CRUD

    func addClass(_ schoolClass: SchoolClass) {
        classes.append(schoolClass)
        save(classes, to: classesFile)
    }

    func updateClass(_ schoolClass: SchoolClass) {
        if let index = classes.firstIndex(where: { $0.id == schoolClass.id }) {
            var updated = schoolClass
            updated.updatedAt = Date()
            classes[index] = updated
            save(classes, to: classesFile)
        }
    }

    func deleteClass(_ classId: UUID) {
        // Delete all students in the class
        let studentsToDelete = students.filter { $0.classId == classId }
        for student in studentsToDelete {
            deleteStudent(student.id)
        }

        // Delete all assignments in the class
        let assignmentsToDelete = assignments.filter { $0.classId == classId }
        for assignment in assignmentsToDelete {
            deleteAssignment(assignment.id)
        }

        classes.removeAll { $0.id == classId }
        save(classes, to: classesFile)
    }

    func getClass(by id: UUID) -> SchoolClass? {
        classes.first { $0.id == id }
    }

    // MARK: - Student CRUD

    func addStudent(_ student: Student) {
        students.append(student)
        save(students, to: studentsFile)

        // Update class
        if var schoolClass = getClass(by: student.classId) {
            schoolClass.studentIds.append(student.id)
            updateClass(schoolClass)
        }
    }

    func updateStudent(_ student: Student) {
        if let index = students.firstIndex(where: { $0.id == student.id }) {
            var updated = student
            updated.updatedAt = Date()
            students[index] = updated
            save(students, to: studentsFile)
        }
    }

    func deleteStudent(_ studentId: UUID) {
        // Delete all submissions by this student
        let submissionsToDelete = submissions.filter { $0.studentId == studentId }
        for submission in submissionsToDelete {
            deleteSubmission(submission.id)
        }

        // Remove from class
        if let student = getStudent(by: studentId),
           var schoolClass = getClass(by: student.classId) {
            schoolClass.studentIds.removeAll { $0 == studentId }
            updateClass(schoolClass)
        }

        students.removeAll { $0.id == studentId }
        save(students, to: studentsFile)
    }

    func getStudent(by id: UUID) -> Student? {
        students.first { $0.id == id }
    }

    func getStudents(for classId: UUID) -> [Student] {
        students.filter { $0.classId == classId }.sorted { $0.sortableName < $1.sortableName }
    }

    // MARK: - Assignment CRUD

    func addAssignment(_ assignment: Assignment) {
        assignments.append(assignment)
        save(assignments, to: assignmentsFile)

        // Update class
        if var schoolClass = getClass(by: assignment.classId) {
            schoolClass.assignmentIds.append(assignment.id)
            updateClass(schoolClass)
        }
    }

    func updateAssignment(_ assignment: Assignment) {
        if let index = assignments.firstIndex(where: { $0.id == assignment.id }) {
            var updated = assignment
            updated.updatedAt = Date()
            assignments[index] = updated
            save(assignments, to: assignmentsFile)
        }
    }

    func deleteAssignment(_ assignmentId: UUID) {
        // Delete all submissions for this assignment
        let submissionsToDelete = submissions.filter { $0.assignmentId == assignmentId }
        for submission in submissionsToDelete {
            deleteSubmission(submission.id)
        }

        // Remove from class
        if let assignment = getAssignment(by: assignmentId),
           var schoolClass = getClass(by: assignment.classId) {
            schoolClass.assignmentIds.removeAll { $0 == assignmentId }
            updateClass(schoolClass)
        }

        assignments.removeAll { $0.id == assignmentId }
        save(assignments, to: assignmentsFile)
    }

    func getAssignment(by id: UUID) -> Assignment? {
        assignments.first { $0.id == id }
    }

    func getAssignments(for classId: UUID) -> [Assignment] {
        assignments.filter { $0.classId == classId }.sorted { ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast) }
    }

    // MARK: - Submission CRUD

    func addSubmission(_ submission: StudentSubmission) {
        submissions.append(submission)
        save(submissions, to: submissionsFile)
    }

    func updateSubmission(_ submission: StudentSubmission) {
        if let index = submissions.firstIndex(where: { $0.id == submission.id }) {
            var updated = submission
            updated.updatedAt = Date()
            submissions[index] = updated
            save(submissions, to: submissionsFile)
        }
    }

    func deleteSubmission(_ submissionId: UUID) {
        // Delete associated images
        if let submission = getSubmission(by: submissionId) {
            for imagePath in submission.imagePaths {
                let fullPath = imagesDirectory.appendingPathComponent(imagePath)
                try? FileManager.default.removeItem(at: fullPath)
            }
        }

        submissions.removeAll { $0.id == submissionId }
        save(submissions, to: submissionsFile)
    }

    func getSubmission(by id: UUID) -> StudentSubmission? {
        submissions.first { $0.id == id }
    }

    func getSubmission(for studentId: UUID, assignmentId: UUID) -> StudentSubmission? {
        submissions.first { $0.studentId == studentId && $0.assignmentId == assignmentId }
    }

    func getSubmissions(forAssignment assignmentId: UUID) -> [StudentSubmission] {
        submissions.filter { $0.assignmentId == assignmentId }
    }

    func getSubmissions(forStudent studentId: UUID) -> [StudentSubmission] {
        submissions.filter { $0.studentId == studentId }
    }

    // MARK: - Rubric CRUD

    func addRubric(_ rubric: GradingRubric) {
        rubrics.append(rubric)
        save(rubrics, to: rubricsFile)
    }

    func updateRubric(_ rubric: GradingRubric) {
        if let index = rubrics.firstIndex(where: { $0.id == rubric.id }) {
            var updated = rubric
            updated.updatedAt = Date()
            rubrics[index] = updated
            save(rubrics, to: rubricsFile)
        }
    }

    func deleteRubric(_ rubricId: UUID) {
        rubrics.removeAll { $0.id == rubricId }
        save(rubrics, to: rubricsFile)
    }

    func getRubric(by id: UUID) -> GradingRubric? {
        rubrics.first { $0.id == id }
    }

    // MARK: - Test CRUD

    func addTest(_ test: Test) {
        tests.append(test)
        save(tests, to: testsFile)
    }

    func updateTest(_ test: Test) {
        if let index = tests.firstIndex(where: { $0.id == test.id }) {
            var updated = test
            updated.updatedAt = Date()
            tests[index] = updated
            save(tests, to: testsFile)
        }
    }

    func deleteTest(_ testId: UUID) {
        tests.removeAll { $0.id == testId }
        save(tests, to: testsFile)
    }

    func getTest(by id: UUID) -> Test? {
        tests.first { $0.id == id }
    }

    func getAllTests() -> [Test] {
        tests.sorted { $0.updatedAt > $1.updatedAt }
    }

    func getTests(forAssignment assignmentId: UUID) -> [Test] {
        tests.filter { $0.assignmentId == assignmentId }
    }

    // MARK: - Image Management

    /// Copies an image to the data directory and returns the relative path
    func importImage(from sourceURL: URL, for submissionId: UUID) -> String? {
        let submissionDir = imagesDirectory.appendingPathComponent(submissionId.uuidString)
        try? FileManager.default.createDirectory(at: submissionDir, withIntermediateDirectories: true)

        let fileName = sourceURL.lastPathComponent
        let destPath = submissionDir.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: destPath.path) {
                try FileManager.default.removeItem(at: destPath)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destPath)
            return "\(submissionId.uuidString)/\(fileName)"
        } catch {
            return nil
        }
    }

    /// Returns the full URL for a relative image path
    func imageURL(for relativePath: String) -> URL {
        imagesDirectory.appendingPathComponent(relativePath)
    }

    /// Loads an NSImage from a relative path
    func loadImage(relativePath: String) -> NSImage? {
        let url = imageURL(for: relativePath)
        return NSImage(contentsOf: url)
    }

    // MARK: - Statistics

    func calculateStudentStatistics(_ studentId: UUID) -> StudentStatistics? {
        guard let student = getStudent(by: studentId) else { return nil }

        let studentSubmissions = getSubmissions(forStudent: studentId)
        let gradedSubmissions = studentSubmissions.filter { $0.finalGrade != nil }

        var totalErrors = 0
        var errorsByCategory: [ErrorCategory: Int] = [:]
        var gradeHistory: [(date: Date, grade: Double)] = []

        for submission in studentSubmissions {
            if let analysis = submission.analysis {
                totalErrors += analysis.totalErrors
                for category in ErrorCategory.allCases {
                    errorsByCategory[category, default: 0] += analysis.errorCount(for: category)
                }
            }
            if let grade = submission.finalGrade {
                gradeHistory.append((submission.updatedAt, grade))
            }
        }

        let averageGrade: Double? = gradedSubmissions.isEmpty ? nil :
            gradedSubmissions.compactMap { $0.finalGrade }.reduce(0, +) / Double(gradedSubmissions.count)

        return StudentStatistics(
            student: student,
            totalSubmissions: studentSubmissions.count,
            gradedSubmissions: gradedSubmissions.count,
            averageGrade: averageGrade,
            totalErrors: totalErrors,
            errorsByCategory: errorsByCategory,
            gradeHistory: gradeHistory.sorted { $0.date < $1.date }
        )
    }

    func calculateClassStatistics(_ classId: UUID) -> ClassStatistics? {
        guard let schoolClass = getClass(by: classId) else { return nil }

        let classStudents = getStudents(for: classId)
        let classAssignments = getAssignments(for: classId)
        let classSubmissions = submissions.filter { submission in
            classAssignments.contains { $0.id == submission.assignmentId }
        }
        let gradedSubmissions = classSubmissions.filter { $0.finalGrade != nil }

        // Calculate average
        let grades = gradedSubmissions.compactMap { $0.finalGrade }
        let classAverage: Double? = grades.isEmpty ? nil : grades.reduce(0, +) / Double(grades.count)

        let distribution = calculateGradeDistribution(grades)

        // Common errors
        var errorCounts: [ErrorCategory: Int] = [:]
        for submission in classSubmissions {
            if let analysis = submission.analysis {
                for category in ErrorCategory.allCases {
                    errorCounts[category, default: 0] += analysis.errorCount(for: category)
                }
            }
        }
        let commonErrors = errorCounts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        return ClassStatistics(
            schoolClass: schoolClass,
            totalStudents: classStudents.count,
            totalAssignments: classAssignments.count,
            totalSubmissions: classSubmissions.count,
            gradedSubmissions: gradedSubmissions.count,
            classAverage: classAverage,
            gradeDistribution: distribution,
            commonErrors: commonErrors
        )
    }

    func calculateAssignmentStatistics(_ assignmentId: UUID) -> AssignmentStatistics? {
        guard let assignment = getAssignment(by: assignmentId) else { return nil }

        let assignmentSubmissions = getSubmissions(forAssignment: assignmentId)
        let gradedSubmissions = assignmentSubmissions.filter { $0.finalGrade != nil }
        let grades = gradedSubmissions.compactMap { $0.finalGrade }.sorted()

        let averageGrade: Double? = grades.isEmpty ? nil : grades.reduce(0, +) / Double(grades.count)
        let medianGrade: Double? = grades.isEmpty ? nil : grades[grades.count / 2]

        let distribution = calculateGradeDistribution(grades)

        // Common error texts
        var errorTextCounts: [String: Int] = [:]
        for submission in assignmentSubmissions {
            if let analysis = submission.analysis {
                for error in analysis.errors {
                    errorTextCounts[error.text, default: 0] += 1
                }
            }
        }
        let commonErrors = errorTextCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }

        return AssignmentStatistics(
            assignment: assignment,
            totalSubmissions: assignmentSubmissions.count,
            gradedSubmissions: gradedSubmissions.count,
            averageGrade: averageGrade,
            highestGrade: grades.last,
            lowestGrade: grades.first,
            medianGrade: medianGrade,
            gradeDistribution: distribution,
            commonErrors: commonErrors
        )
    }

    // MARK: - Helpers

    /// Calcule la distribution des notes sur une échelle française (0-20)
    private func calculateGradeDistribution(_ grades: [Double]) -> [String: Int] {
        var distribution: [String: Int] = [
            "0-4": 0, "5-7": 0, "8-9": 0, "10-11": 0,
            "12-13": 0, "14-15": 0, "16-17": 0, "18-20": 0
        ]
        for grade in grades {
            switch grade {
            case 0..<5: distribution["0-4", default: 0] += 1
            case 5..<8: distribution["5-7", default: 0] += 1
            case 8..<10: distribution["8-9", default: 0] += 1
            case 10..<12: distribution["10-11", default: 0] += 1
            case 12..<14: distribution["12-13", default: 0] += 1
            case 14..<16: distribution["14-15", default: 0] += 1
            case 16..<18: distribution["16-17", default: 0] += 1
            default: distribution["18-20", default: 0] += 1
            }
        }
        return distribution
    }

    // MARK: - Default Rubric

    private func createDefaultRubric() {
        let defaultRubric = GradingRubric(
            name: "Barème standard anglais",
            description: "Barème par défaut pour les devoirs d'anglais",
            criteria: [
                RubricCriterion(
                    category: .grammar,
                    pointsPerError: 0.5,
                    maxDeduction: 6.0,
                    description: "Erreurs de grammaire (conjugaison, accords, temps)"
                ),
                RubricCriterion(
                    category: .spelling,
                    pointsPerError: 0.25,
                    maxDeduction: 3.0,
                    description: "Erreurs d'orthographe"
                ),
                RubricCriterion(
                    category: .vocabulary,
                    pointsPerError: 0.5,
                    maxDeduction: 4.0,
                    description: "Erreurs de vocabulaire et faux-amis"
                ),
                RubricCriterion(
                    category: .syntax,
                    pointsPerError: 0.5,
                    maxDeduction: 4.0,
                    description: "Erreurs de syntaxe (ordre des mots, structure)"
                )
            ],
            maxScore: 20.0
        )
        addRubric(defaultRubric)
    }
}
