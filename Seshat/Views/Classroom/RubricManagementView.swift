import SwiftUI

/// View for managing grading rubrics
struct RubricManagementView: View {
    @State private var dataStore = DataStore.shared
    @State private var showingAddRubric = false
    @State private var selectedRubric: GradingRubric?

    var body: some View {
        HSplitView {
            // Rubric list
            VStack(spacing: 0) {
                HStack {
                    Text("Barèmes")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingAddRubric = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                .padding()
                .background(.bar)

                Divider()

                List(dataStore.rubrics, selection: $selectedRubric) { rubric in
                    RubricRow(rubric: rubric)
                        .tag(rubric)
                        .contextMenu {
                            Button("Dupliquer") {
                                duplicateRubric(rubric)
                            }
                            Button("Supprimer", role: .destructive) {
                                if selectedRubric?.id == rubric.id {
                                    selectedRubric = nil
                                }
                                dataStore.deleteRubric(rubric.id)
                            }
                        }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 250)

            // Rubric editor
            if let rubric = selectedRubric {
                RubricEditorView(
                    rubric: rubric,
                    onSave: { updated in
                        dataStore.updateRubric(updated)
                        selectedRubric = updated
                    }
                )
            } else {
                ContentUnavailableView(
                    "Sélectionnez un barème",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Choisissez un barème à modifier ou créez-en un nouveau")
                )
            }
        }
        .sheet(isPresented: $showingAddRubric) {
            AddRubricSheet(isPresented: $showingAddRubric) { newRubric in
                dataStore.addRubric(newRubric)
                selectedRubric = newRubric
            }
        }
    }

    private func duplicateRubric(_ rubric: GradingRubric) {
        var duplicate = rubric
        duplicate = GradingRubric(
            name: "\(rubric.name) (copie)",
            description: rubric.description,
            criteria: rubric.criteria.map { criterion in
                RubricCriterion(
                    category: criterion.category,
                    pointsPerError: criterion.pointsPerError,
                    maxDeduction: criterion.maxDeduction,
                    description: criterion.description
                )
            },
            maxScore: rubric.maxScore
        )
        dataStore.addRubric(duplicate)
        selectedRubric = duplicate
    }
}

// MARK: - Rubric Row

struct RubricRow: View {
    let rubric: GradingRubric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rubric.name)
                .font(.headline)

            HStack {
                Text("\(rubric.criteria.count) critères")
                Text("•")
                Text("/\(Int(rubric.maxScore))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rubric Editor

struct RubricEditorView: View {
    let rubric: GradingRubric
    let onSave: (GradingRubric) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var maxScore: Double = 20
    @State private var criteria: [RubricCriterion] = []
    @State private var hasChanges = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Modifier le barème")
                    .font(.headline)

                Spacer()

                if hasChanges {
                    Button("Enregistrer") {
                        saveChanges()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic info
                    GroupBox("Informations") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Nom du barème", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: name) { _, _ in hasChanges = true }

                            TextField("Description", text: $description, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .onChange(of: description) { _, _ in hasChanges = true }

                            HStack {
                                Text("Note maximale:")
                                Stepper(value: $maxScore, in: 1...100, step: 1) {
                                    Text("\(Int(maxScore))")
                                        .frame(width: 40)
                                }
                                .onChange(of: maxScore) { _, _ in hasChanges = true }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Criteria
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Critères de notation")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    addCriterion()
                                } label: {
                                    Label("Ajouter", systemImage: "plus")
                                }
                            }

                            if criteria.isEmpty {
                                Text("Aucun critère défini")
                                    .foregroundStyle(.secondary)
                                    .padding()
                            } else {
                                ForEach(Array(criteria.enumerated()), id: \.element.id) { index, criterion in
                                    CriterionEditorRow(
                                        criterion: criterion,
                                        onUpdate: { updated in
                                            criteria[index] = updated
                                            hasChanges = true
                                        },
                                        onDelete: {
                                            criteria.remove(at: index)
                                            hasChanges = true
                                        }
                                    )

                                    if index < criteria.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } label: {
                        Text("Pénalités par type d'erreur")
                    }

                    // Preview
                    GroupBox("Aperçu du calcul") {
                        RubricPreviewView(criteria: criteria, maxScore: maxScore)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            loadRubric()
        }
        .onChange(of: rubric.id) { _, _ in
            loadRubric()
        }
    }

    private func loadRubric() {
        name = rubric.name
        description = rubric.description
        maxScore = rubric.maxScore
        criteria = rubric.criteria
        hasChanges = false
    }

    private func saveChanges() {
        let updated = GradingRubric(
            id: rubric.id,
            name: name,
            description: description,
            criteria: criteria,
            maxScore: maxScore,
            createdAt: rubric.createdAt,
            updatedAt: Date()
        )
        onSave(updated)
        hasChanges = false
    }

    private func addCriterion() {
        // Find a category not yet used
        let usedCategories = Set(criteria.map { $0.category })
        let availableCategory = ErrorCategory.allCases.first { !usedCategories.contains($0) } ?? .grammar

        let newCriterion = RubricCriterion(
            category: availableCategory,
            pointsPerError: 0.5,
            maxDeduction: 4.0
        )
        criteria.append(newCriterion)
        hasChanges = true
    }
}

// MARK: - Criterion Editor Row

struct CriterionEditorRow: View {
    let criterion: RubricCriterion
    let onUpdate: (RubricCriterion) -> Void
    let onDelete: () -> Void

    @State private var category: ErrorCategory
    @State private var pointsPerError: Double
    @State private var maxDeduction: Double
    @State private var description: String

    init(criterion: RubricCriterion, onUpdate: @escaping (RubricCriterion) -> Void, onDelete: @escaping () -> Void) {
        self.criterion = criterion
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _category = State(initialValue: criterion.category)
        _pointsPerError = State(initialValue: criterion.pointsPerError)
        _maxDeduction = State(initialValue: criterion.maxDeduction)
        _description = State(initialValue: criterion.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Catégorie", selection: $category) {
                    ForEach(ErrorCategory.allCases, id: \.self) { cat in
                        HStack {
                            Circle()
                                .fill(Color(nsColor: NSColor(hex: cat.defaultColor) ?? .gray))
                                .frame(width: 10, height: 10)
                            Text(cat.displayName)
                        }
                        .tag(cat)
                    }
                }
                .onChange(of: category) { _, _ in updateCriterion() }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Points par erreur")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Slider(value: $pointsPerError, in: 0.25...2.0, step: 0.25)
                            .frame(width: 100)
                            .onChange(of: pointsPerError) { _, _ in updateCriterion() }

                        Text(String(format: "-%.2f", pointsPerError))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Déduction max")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Slider(value: $maxDeduction, in: 1...10, step: 0.5)
                            .frame(width: 100)
                            .onChange(of: maxDeduction) { _, _ in updateCriterion() }

                        Text(String(format: "-%.1f", maxDeduction))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50)
                    }
                }
            }

            TextField("Description (optionnel)", text: $description)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onChange(of: description) { _, _ in updateCriterion() }
        }
        .padding()
        .background(Color(nsColor: NSColor(hex: category.defaultColor) ?? .gray).opacity(0.05))
        .cornerRadius(8)
    }

    private func updateCriterion() {
        let updated = RubricCriterion(
            id: criterion.id,
            category: category,
            pointsPerError: pointsPerError,
            maxDeduction: maxDeduction,
            description: description
        )
        onUpdate(updated)
    }
}

// MARK: - Rubric Preview

struct RubricPreviewView: View {
    let criteria: [RubricCriterion]
    let maxScore: Double

    // Sample error counts for preview
    let sampleErrors: [ErrorCategory: Int] = [
        .grammar: 5,
        .spelling: 3,
        .vocabulary: 2,
        .syntax: 1
    ]

    var calculatedGrade: Double {
        var deductions = 0.0
        for criterion in criteria {
            let errorCount = sampleErrors[criterion.category] ?? 0
            let deduction = min(Double(errorCount) * criterion.pointsPerError, criterion.maxDeduction)
            deductions += deduction
        }
        return max(0, maxScore - deductions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exemple avec: 5 grammaire, 3 orthographe, 2 vocabulaire, 1 syntaxe")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(criteria) { criterion in
                let errorCount = sampleErrors[criterion.category] ?? 0
                let deduction = min(Double(errorCount) * criterion.pointsPerError, criterion.maxDeduction)
                let isMaxed = deduction >= criterion.maxDeduction

                HStack {
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: criterion.category.defaultColor) ?? .gray))
                        .frame(width: 10, height: 10)

                    Text(criterion.category.displayName)
                        .frame(width: 80, alignment: .leading)

                    Text("\(errorCount) × \(String(format: "%.2f", criterion.pointsPerError))")
                        .foregroundStyle(.secondary)
                        .frame(width: 80)

                    Spacer()

                    Text(String(format: "-%.1f", deduction))
                        .foregroundStyle(.red)
                        .frame(width: 50, alignment: .trailing)

                    if isMaxed {
                        Text("(max)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }

            Divider()

            HStack {
                Text("Note calculée:")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f / %.0f", calculatedGrade, maxScore))
                    .font(.title2)
                    .bold()
                    .foregroundStyle(gradeColor)
            }
        }
        .padding(.vertical, 8)
    }

    var gradeColor: Color {
        let ratio = calculatedGrade / maxScore
        switch ratio {
        case 0..<0.4: return .red
        case 0.4..<0.5: return .orange
        case 0.5..<0.6: return .yellow
        case 0.6..<0.7: return .green
        default: return .blue
        }
    }
}

// MARK: - Add Rubric Sheet

struct AddRubricSheet: View {
    @Binding var isPresented: Bool
    let onSave: (GradingRubric) -> Void

    @State private var name = ""
    @State private var maxScore: Double = 20

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Annuler") {
                    isPresented = false
                }

                Spacer()

                Text("Nouveau barème")
                    .font(.headline)

                Spacer()

                Button("Créer") {
                    let rubric = GradingRubric(
                        name: name.isEmpty ? "Nouveau barème" : name,
                        criteria: defaultCriteria(),
                        maxScore: maxScore
                    )
                    onSave(rubric)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
            .background(.bar)

            Divider()

            Form {
                Section("Informations") {
                    TextField("Nom du barème", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Stepper("Note maximale: \(Int(maxScore))", value: $maxScore, in: 1...100)
                }

                Section("Critères par défaut") {
                    Text("Le barème sera créé avec des critères par défaut que vous pourrez modifier ensuite.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 400, height: 280)
    }

    private func defaultCriteria() -> [RubricCriterion] {
        [
            RubricCriterion(category: .grammar, pointsPerError: 0.5, maxDeduction: 6.0),
            RubricCriterion(category: .spelling, pointsPerError: 0.25, maxDeduction: 3.0),
            RubricCriterion(category: .vocabulary, pointsPerError: 0.5, maxDeduction: 4.0),
            RubricCriterion(category: .syntax, pointsPerError: 0.5, maxDeduction: 4.0)
        ]
    }
}

#Preview {
    RubricManagementView()
}
