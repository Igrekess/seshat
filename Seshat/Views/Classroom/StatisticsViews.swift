import SwiftUI
import Charts

// MARK: - Class Statistics View

struct ClassStatisticsView: View {
    let classId: UUID
    @State private var dataStore = DataStore.shared
    @State private var cachedStatistics: ClassStatistics?

    var body: some View {
        Group {
            if let stats = cachedStatistics {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Statistiques de classe")
                                .font(.title2)
                                .bold()

                            Text(stats.schoolClass.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Quick stats - adaptive grid
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100, maximum: 150))
                        ], spacing: 12) {
                            StatCard(
                                title: "Élèves",
                                value: "\(stats.totalStudents)",
                                icon: "person.fill",
                                color: .blue
                            )
                            StatCard(
                                title: "Devoirs",
                                value: "\(stats.totalAssignments)",
                                icon: "doc.text.fill",
                                color: .green
                            )
                            StatCard(
                                title: "Copies",
                                value: "\(stats.gradedSubmissions)/\(stats.totalSubmissions)",
                                icon: "checkmark.circle.fill",
                                color: .orange
                            )
                            StatCard(
                                title: "Moyenne",
                                value: stats.classAverage.map { String(format: "%.1f", $0) } ?? "-",
                                icon: "chart.bar.fill",
                                color: .purple
                            )
                        }

                        // Grade distribution
                        if stats.gradedSubmissions > 0 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Distribution des notes")
                                    .font(.headline)

                                GradeDistributionChart(distribution: stats.gradeDistribution)
                                    .frame(height: 200)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                        }

                        // Common errors
                        if !stats.commonErrors.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Erreurs les plus fréquentes")
                                    .font(.headline)

                                ForEach(stats.commonErrors.prefix(5), id: \.category) { item in
                                    HStack {
                                        Circle()
                                            .fill(Color(nsColor: NSColor(hex: item.category.defaultColor) ?? .gray))
                                            .frame(width: 12, height: 12)

                                        Text(item.category.displayName)

                                        Spacer()

                                        Text("\(item.count)")
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                        }

                        // Student rankings
                        StudentRankingsView(classId: classId)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Pas de données",
                    systemImage: "chart.bar",
                    description: Text("Les statistiques apparaîtront après les premières corrections")
                )
            }
        }
        .onAppear {
            cachedStatistics = dataStore.calculateClassStatistics(classId)
        }
        .onChange(of: dataStore.submissions) { _, _ in
            cachedStatistics = dataStore.calculateClassStatistics(classId)
        }
    }
}

// MARK: - Assignment Statistics View

struct AssignmentStatisticsView: View {
    let assignmentId: UUID
    @State private var dataStore = DataStore.shared
    @State private var cachedStatistics: AssignmentStatistics?

    var body: some View {
        Group {
            if let stats = cachedStatistics {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Statistiques du devoir")
                                .font(.title2)
                                .bold()

                            Text(stats.assignment.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Quick stats - adaptive grid
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100, maximum: 150))
                        ], spacing: 12) {
                            StatCard(
                                title: "Copies notées",
                                value: "\(stats.gradedSubmissions)/\(stats.totalSubmissions)",
                                icon: "doc.text.fill",
                                color: .blue
                            )
                            StatCard(
                                title: "Moyenne",
                                value: stats.averageGrade.map { String(format: "%.1f", $0) } ?? "-",
                                icon: "chart.bar.fill",
                                color: .purple
                            )
                            StatCard(
                                title: "Plus haute",
                                value: stats.highestGrade.map { String(format: "%.1f", $0) } ?? "-",
                                icon: "arrow.up.circle.fill",
                                color: .green
                            )
                            StatCard(
                                title: "Plus basse",
                                value: stats.lowestGrade.map { String(format: "%.1f", $0) } ?? "-",
                                icon: "arrow.down.circle.fill",
                                color: .red
                            )
                        }

                        // Grade distribution
                        if stats.gradedSubmissions > 0 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Distribution des notes")
                                    .font(.headline)

                                GradeDistributionChart(distribution: stats.gradeDistribution)
                                    .frame(height: 200)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                        }

                        // Common errors
                        if !stats.commonErrors.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Erreurs les plus fréquentes")
                                    .font(.headline)

                                ForEach(Array(stats.commonErrors.prefix(10).enumerated()), id: \.offset) { index, item in
                                    HStack {
                                        Text("\(index + 1).")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24)

                                        Text(item.text)
                                            .font(.system(.body, design: .monospaced))

                                        Spacer()

                                        Text("\(item.count) élève\(item.count > 1 ? "s" : "")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Pas de données",
                    systemImage: "chart.bar",
                    description: Text("Les statistiques apparaîtront après les premières corrections")
                )
            }
        }
        .onAppear {
            cachedStatistics = dataStore.calculateAssignmentStatistics(assignmentId)
        }
        .onChange(of: dataStore.submissions) { _, _ in
            cachedStatistics = dataStore.calculateAssignmentStatistics(assignmentId)
        }
    }
}

// MARK: - Grade Distribution Chart

struct GradeDistributionChart: View {
    let distribution: [String: Int]

    var sortedData: [(range: String, count: Int)] {
        let order = ["0-4", "5-7", "8-9", "10-11", "12-13", "14-15", "16-17", "18-20"]
        return order.map { range in
            (range, distribution[range] ?? 0)
        }
    }

    var body: some View {
        Chart(sortedData, id: \.range) { item in
            BarMark(
                x: .value("Note", item.range),
                y: .value("Nombre", item.count)
            )
            .foregroundStyle(barColor(for: item.range))
            .annotation(position: .top) {
                if item.count > 0 {
                    Text("\(item.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }

    private func barColor(for range: String) -> Color {
        switch range {
        case "0-4": return .red
        case "5-7": return .orange
        case "8-9": return .yellow
        case "10-11": return .green.opacity(0.7)
        case "12-13": return .green
        case "14-15": return .blue.opacity(0.7)
        case "16-17": return .blue
        case "18-20": return .purple
        default: return .gray
        }
    }
}

// MARK: - Student Rankings

struct StudentRankingsView: View {
    let classId: UUID
    @State private var dataStore = DataStore.shared

    var rankedStudents: [(student: Student, stats: StudentStatistics)] {
        let students = dataStore.getStudents(for: classId)
        return students.compactMap { student in
            guard let stats = dataStore.calculateStudentStatistics(student.id),
                  stats.averageGrade != nil else { return nil }
            return (student, stats)
        }.sorted { ($0.stats.averageGrade ?? 0) > ($1.stats.averageGrade ?? 0) }
    }

    var body: some View {
        if !rankedStudents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Classement des élèves")
                    .font(.headline)

                ForEach(Array(rankedStudents.enumerated()), id: \.element.student.id) { index, item in
                    HStack {
                        // Rank
                        ZStack {
                            Circle()
                                .fill(rankColor(index))
                                .frame(width: 28, height: 28)

                            Text("\(index + 1)")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.white)
                        }

                        // Name
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.student.fullName)
                                .font(.headline)

                            Text("\(item.stats.gradedSubmissions) copie\(item.stats.gradedSubmissions > 1 ? "s" : "") notée\(item.stats.gradedSubmissions > 1 ? "s" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Average grade
                        if let avg = item.stats.averageGrade {
                            Text(String(format: "%.1f", avg))
                                .font(.title2)
                                .bold()
                                .foregroundStyle(GradeUtilities.color(for: avg))
                        }

                        // Progress indicator
                        if item.stats.gradeHistory.count >= 2 {
                            let trend = calculateTrend(item.stats.gradeHistory)
                            Image(systemName: trend > 0 ? "arrow.up.circle.fill" :
                                    trend < 0 ? "arrow.down.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(trend > 0 ? .green : trend < 0 ? .red : .gray)
                        }
                    }
                    .padding(.vertical, 4)

                    if index < rankedStudents.count - 1 {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .yellow
        case 1: return .gray
        case 2: return .orange
        default: return .blue.opacity(0.5)
        }
    }

    private func calculateTrend(_ history: [(date: Date, grade: Double)]) -> Int {
        guard history.count >= 2 else { return 0 }
        let recent = history.suffix(2)
        let diff = recent.last!.grade - recent.first!.grade
        if diff > 0.5 { return 1 }
        if diff < -0.5 { return -1 }
        return 0
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(value)
                .font(.title3)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview("Class Stats") {
    ClassStatisticsView(classId: UUID())
}

#Preview("Assignment Stats") {
    AssignmentStatisticsView(assignmentId: UUID())
}
