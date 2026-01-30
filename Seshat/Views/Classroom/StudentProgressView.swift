import SwiftUI
import Charts

/// Detailed view of a student's progress and performance
struct StudentProgressView: View {
    let studentId: UUID
    @State private var dataStore = DataStore.shared

    var student: Student? {
        dataStore.getStudent(by: studentId)
    }

    var statistics: StudentStatistics? {
        dataStore.calculateStudentStatistics(studentId)
    }

    var submissions: [StudentSubmission] {
        dataStore.getSubmissions(forStudent: studentId)
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        if let student = student, let stats = statistics {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    StudentProgressHeader(student: student, stats: stats)

                    // Grade evolution chart
                    if !stats.gradeHistory.isEmpty {
                        GradeEvolutionChart(gradeHistory: stats.gradeHistory)
                    }

                    // Error breakdown
                    ErrorBreakdownView(stats: stats)

                    // Submissions history
                    SubmissionsHistoryView(submissions: submissions)

                    // Recommendations
                    RecommendationsView(stats: stats)
                }
                .padding()
            }
            .navigationTitle(student.fullName)
        } else {
            ContentUnavailableView(
                "Élève introuvable",
                systemImage: "person.slash",
                description: Text("Les données de cet élève ne sont pas disponibles")
            )
        }
    }
}

// MARK: - Header

struct StudentProgressHeader: View {
    let student: Student
    let stats: StudentStatistics
    @State private var dataStore = DataStore.shared

    var schoolClass: SchoolClass? {
        dataStore.getClass(by: student.classId)
    }

    var body: some View {
        HStack(spacing: 20) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 80, height: 80)

                Text(student.firstName.prefix(1).uppercased() + student.lastName.prefix(1).uppercased())
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(student.fullName)
                    .font(.largeTitle)
                    .bold()

                if let schoolClass = schoolClass {
                    Text(schoolClass.name)
                        .foregroundStyle(.secondary)
                }

                if let email = student.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Quick stats
            HStack(spacing: 24) {
                VStack {
                    Text("\(stats.gradedSubmissions)")
                        .font(.title)
                        .bold()
                    Text("Copies notées")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let avg = stats.averageGrade {
                    VStack {
                        Text(String(format: "%.1f", avg))
                            .font(.title)
                            .bold()
                            .foregroundStyle(GradeUtilities.color(for: avg))
                        Text("Moyenne")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack {
                    Text("\(stats.totalErrors)")
                        .font(.title)
                        .bold()
                        .foregroundStyle(.orange)
                    Text("Erreurs totales")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Grade Evolution Chart

struct GradeEvolutionChart: View {
    let gradeHistory: [(date: Date, grade: Double)]

    var trend: Double {
        guard gradeHistory.count >= 2 else { return 0 }
        let firstHalf = gradeHistory.prefix(gradeHistory.count / 2)
        let secondHalf = gradeHistory.suffix(gradeHistory.count / 2)
        let firstAvg = firstHalf.map { $0.grade }.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.map { $0.grade }.reduce(0, +) / Double(secondHalf.count)
        return secondAvg - firstAvg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Évolution des notes")
                    .font(.headline)

                Spacer()

                // Trend indicator
                HStack(spacing: 4) {
                    Image(systemName: trend > 0.5 ? "arrow.up.circle.fill" :
                            trend < -0.5 ? "arrow.down.circle.fill" : "minus.circle.fill")
                    Text(trend > 0.5 ? "En progression" : trend < -0.5 ? "En baisse" : "Stable")
                        .font(.caption)
                }
                .foregroundStyle(trend > 0.5 ? .green : trend < -0.5 ? .red : .gray)
            }

            Chart {
                ForEach(Array(gradeHistory.enumerated()), id: \.offset) { index, item in
                    LineMark(
                        x: .value("Devoir", index + 1),
                        y: .value("Note", item.grade)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)

                    PointMark(
                        x: .value("Devoir", index + 1),
                        y: .value("Note", item.grade)
                    )
                    .foregroundStyle(.blue)
                }

                // Average line
                if let avg = gradeHistory.isEmpty ? nil : gradeHistory.map({ $0.grade }).reduce(0, +) / Double(gradeHistory.count) {
                    RuleMark(y: .value("Moyenne", avg))
                        .foregroundStyle(.orange.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .trailing) {
                            Text("Moy: \(String(format: "%.1f", avg))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                }

                // Pass threshold
                RuleMark(y: .value("Seuil", 10))
                    .foregroundStyle(.red.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartYScale(domain: 0...20)
            .chartYAxis {
                AxisMarks(values: [0, 5, 10, 15, 20])
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Error Breakdown

struct ErrorBreakdownView: View {
    let stats: StudentStatistics

    var totalErrors: Int {
        stats.totalErrors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Répartition des erreurs")
                .font(.headline)

            HStack(spacing: 20) {
                // Pie chart
                Chart {
                    ForEach(ErrorCategory.allCases, id: \.self) { category in
                        let count = stats.errorsByCategory[category] ?? 0
                        if count > 0 {
                            SectorMark(
                                angle: .value("Erreurs", count),
                                innerRadius: .ratio(0.5),
                                angularInset: 2
                            )
                            .foregroundStyle(Color(nsColor: NSColor(hex: category.defaultColor) ?? .gray))
                            .annotation(position: .overlay) {
                                if Double(count) / Double(totalErrors) > 0.1 {
                                    Text("\(count)")
                                        .font(.caption)
                                        .bold()
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                .frame(width: 150, height: 150)

                // Legend with percentages
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ErrorCategory.allCases, id: \.self) { category in
                        let count = stats.errorsByCategory[category] ?? 0
                        let percentage = totalErrors > 0 ? Double(count) / Double(totalErrors) * 100 : 0

                        HStack {
                            Circle()
                                .fill(Color(nsColor: NSColor(hex: category.defaultColor) ?? .gray))
                                .frame(width: 12, height: 12)

                            Text(category.displayName)
                                .frame(width: 100, alignment: .leading)

                            Text("\(count)")
                                .font(.headline)
                                .frame(width: 40, alignment: .trailing)

                            Text(String(format: "(%.0f%%)", percentage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }

            // Most common errors recommendation
            if let topCategory = stats.errorsByCategory.max(by: { $0.value < $1.value })?.key {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("Focus recommandé: **\(topCategory.displayName)**")
                        .font(.caption)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Submissions History

struct SubmissionsHistoryView: View {
    let submissions: [StudentSubmission]
    @State private var dataStore = DataStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historique des copies")
                .font(.headline)

            if submissions.isEmpty {
                Text("Aucune copie soumise")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(submissions) { submission in
                    SubmissionHistoryRow(submission: submission)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct SubmissionHistoryRow: View {
    let submission: StudentSubmission
    @State private var dataStore = DataStore.shared

    var assignment: Assignment? {
        dataStore.getAssignment(by: submission.assignmentId)
    }

    var body: some View {
        HStack {
            // Status icon
            Image(systemName: submission.status.icon)
                .foregroundStyle(Color(hex: submission.status.color) ?? .gray)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(assignment?.title ?? "Devoir inconnu")
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(submission.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let errorCount = submission.analysis?.totalErrors {
                        Text("\(errorCount) erreur\(errorCount > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if let grade = submission.finalGrade {
                GradeBadge(grade: grade, maxGrade: assignment?.maxScore ?? 20)
            } else {
                StatusBadge(status: submission.status)
            }
        }
        .padding(.vertical, 8)

        Divider()
    }
}

// MARK: - Recommendations

struct RecommendationsView: View {
    let stats: StudentStatistics

    var recommendations: [Recommendation] {
        var recs: [Recommendation] = []

        // Grammar focus
        if stats.grammarErrors > 5 {
            recs.append(Recommendation(
                icon: "textformat.abc",
                color: .red,
                title: "Réviser la grammaire",
                description: "Les erreurs grammaticales sont fréquentes. Revoir les règles de conjugaison et d'accord."
            ))
        }

        // Spelling
        if stats.spellingErrors > 3 {
            recs.append(Recommendation(
                icon: "pencil",
                color: .orange,
                title: "Travailler l'orthographe",
                description: "Pratiquer l'orthographe des mots courants et utiliser un dictionnaire."
            ))
        }

        // Vocabulary
        if stats.vocabularyErrors > 2 {
            recs.append(Recommendation(
                icon: "character.book.closed",
                color: .blue,
                title: "Enrichir le vocabulaire",
                description: "Attention aux faux-amis français/anglais. Apprendre le vocabulaire en contexte."
            ))
        }

        // Syntax
        if stats.syntaxErrors > 2 {
            recs.append(Recommendation(
                icon: "arrow.left.arrow.right",
                color: .green,
                title: "Revoir la syntaxe",
                description: "Travailler l'ordre des mots en anglais (SVO) et les structures de phrases."
            ))
        }

        // Positive feedback
        if stats.averageGrade ?? 0 >= 14 {
            recs.append(Recommendation(
                icon: "star.fill",
                color: .purple,
                title: "Excellent travail !",
                description: "Maintenir ce niveau et viser l'excellence dans tous les critères."
            ))
        }

        return recs
    }

    struct Recommendation: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let description: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommandations personnalisées")
                .font(.headline)

            if recommendations.isEmpty {
                Text("Pas de recommandation particulière - continuer ainsi !")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(recommendations) { rec in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: rec.icon)
                            .font(.title2)
                            .foregroundStyle(rec.color)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(rec.title)
                                .font(.headline)
                            Text(rec.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rec.color.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    StudentProgressView(studentId: UUID())
}
