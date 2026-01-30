import SwiftUI

struct AddClassSheet: View {
    @Binding var isPresented: Bool
    var onSave: (SchoolClass) -> Void

    @State private var name = ""
    @State private var level = "Terminale"
    @State private var year = ""

    private let levels = ["Seconde", "Première", "Terminale", "BTS 1", "BTS 2", "Autre"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Text("Nouvelle classe")
                    .font(.headline)

                Spacer()

                Button("Créer") {
                    let newClass = SchoolClass(
                        name: name.isEmpty ? "Nouvelle classe" : name,
                        year: year,
                        level: level
                    )
                    onSave(newClass)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
            .background(.bar)

            Divider()

            // Form
            Form {
                Section("Informations") {
                    TextField("Nom de la classe", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker("Niveau", selection: $level) {
                        ForEach(levels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }

                    TextField("Année scolaire (ex: 2025-2026)", text: $year)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 400, height: 300)
        .onAppear {
            // Default year
            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: Date())
            let month = calendar.component(.month, from: Date())
            if month >= 9 {
                year = "\(currentYear)-\(currentYear + 1)"
            } else {
                year = "\(currentYear - 1)-\(currentYear)"
            }
        }
    }
}

struct AddAssignmentSheet: View {
    let classId: UUID
    @Binding var isPresented: Bool
    var onSave: (Assignment) -> Void

    @State private var dataStore = DataStore.shared
    @State private var title = ""
    @State private var description = ""
    @State private var dueDate = Date()
    @State private var hasDueDate = false
    @State private var maxScore: Double = 20
    @State private var selectedRubricId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Text("Nouveau devoir")
                    .font(.headline)

                Spacer()

                Button("Créer") {
                    let newAssignment = Assignment(
                        title: title.isEmpty ? "Nouveau devoir" : title,
                        description: description,
                        classId: classId,
                        dueDate: hasDueDate ? dueDate : nil,
                        rubricId: selectedRubricId,
                        maxScore: maxScore
                    )
                    onSave(newAssignment)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
            .padding()
            .background(.bar)

            Divider()

            // Form
            Form {
                Section("Informations") {
                    TextField("Titre du devoir", text: $title)
                        .textFieldStyle(.roundedBorder)

                    TextField("Description (optionnel)", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                Section("Date limite") {
                    Toggle("Date limite", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Notation") {
                    HStack {
                        Text("Note maximale")
                        Spacer()
                        TextField("Max", value: $maxScore, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }

                    Picker("Barème", selection: $selectedRubricId) {
                        Text("Aucun").tag(nil as UUID?)
                        ForEach(dataStore.rubrics) { rubric in
                            Text(rubric.name).tag(rubric.id as UUID?)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 450, height: 450)
        .onAppear {
            // Default to first rubric
            selectedRubricId = dataStore.rubrics.first?.id
        }
    }
}

struct AddStudentSheet: View {
    let classId: UUID
    @Binding var isPresented: Bool
    var onSave: (Student) -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var bulkMode = false
    @State private var bulkText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Text(bulkMode ? "Ajouter plusieurs élèves" : "Nouvel élève")
                    .font(.headline)

                Spacer()

                Button(bulkMode ? "Ajouter" : "Créer") {
                    if bulkMode {
                        addBulkStudents()
                    } else {
                        addSingleStudent()
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(bulkMode ? bulkText.isEmpty : (firstName.isEmpty && lastName.isEmpty))
            }
            .padding()
            .background(.bar)

            Divider()

            // Mode toggle
            Picker("Mode", selection: $bulkMode) {
                Text("Un élève").tag(false)
                Text("Plusieurs élèves").tag(true)
            }
            .pickerStyle(.segmented)
            .padding()

            if bulkMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entrez un élève par ligne (Prénom Nom)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $bulkText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .border(Color.secondary.opacity(0.3))

                    Text("Exemple:\nJean Dupont\nMarie Martin\nPierre Bernard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                Form {
                    Section("Informations") {
                        TextField("Prénom", text: $firstName)
                            .textFieldStyle(.roundedBorder)

                        TextField("Nom", text: $lastName)
                            .textFieldStyle(.roundedBorder)

                        TextField("Email (optionnel)", text: $email)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .formStyle(.grouped)
                .padding()
            }

            Spacer()
        }
        .frame(width: 400, height: bulkMode ? 400 : 300)
    }

    private func addSingleStudent() {
        let student = Student(
            firstName: firstName.isEmpty ? "Prénom" : firstName,
            lastName: lastName.isEmpty ? "Nom" : lastName,
            email: email.isEmpty ? nil : email,
            classId: classId
        )
        onSave(student)
        isPresented = false
    }

    private func addBulkStudents() {
        let lines = bulkText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            let parts = line.components(separatedBy: " ")
            let firstName = parts.first ?? "Prénom"
            let lastName = parts.dropFirst().joined(separator: " ")

            let student = Student(
                firstName: firstName,
                lastName: lastName.isEmpty ? "Nom" : lastName,
                classId: classId
            )
            onSave(student)
        }
        isPresented = false
    }
}

#Preview("Add Class") {
    AddClassSheet(isPresented: .constant(true)) { _ in }
}

#Preview("Add Assignment") {
    AddAssignmentSheet(classId: UUID(), isPresented: .constant(true)) { _ in }
}

#Preview("Add Student") {
    AddStudentSheet(classId: UUID(), isPresented: .constant(true)) { _ in }
}
