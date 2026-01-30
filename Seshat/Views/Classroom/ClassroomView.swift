import SwiftUI

/// Main classroom management view with sidebar navigation
struct ClassroomView: View {
    @Binding var modeBinding: ContentView.AppMode
    @State private var dataStore = DataStore.shared
    @State private var selectedClass: SchoolClass?
    @State private var selectedAssignment: Assignment?
    @State private var selectedStudent: Student?
    @State private var selectedStudentForProgress: Student?
    @State private var showingAddClass = false
    @State private var showingAddAssignment = false
    @State private var showingAddStudent = false
    @State private var showingRubricManagement = false
    @State private var navigationPath = NavigationPath()

    init(modeBinding: Binding<ContentView.AppMode>? = nil) {
        self._modeBinding = modeBinding ?? .constant(.classroom)
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar - list of classes
            ClassroomSidebar(
                selectedClass: $selectedClass,
                selectedAssignment: $selectedAssignment,
                selectedStudent: $selectedStudent,
                showingAddClass: $showingAddClass,
                modeBinding: $modeBinding
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            // Content - depends on selection
            if let selectedClass = selectedClass {
                if selectedAssignment != nil {
                    AssignmentSubmissionsView(
                        assignment: Binding(
                            get: { selectedAssignment! },
                            set: { selectedAssignment = $0 }
                        ),
                        selectedStudent: $selectedStudent,
                        onBack: {
                            selectedAssignment = nil
                            selectedStudent = nil
                        }
                    )
                    .navigationSplitViewColumnWidth(min: 350, ideal: 450, max: .infinity)
                } else {
                    ClassDetailView(
                        schoolClass: Binding(
                            get: { selectedClass },
                            set: { self.selectedClass = $0 }
                        ),
                        selectedAssignment: $selectedAssignment,
                        selectedStudentForProgress: $selectedStudentForProgress,
                        showingAddAssignment: $showingAddAssignment,
                        showingAddStudent: $showingAddStudent
                    )
                    .navigationSplitViewColumnWidth(min: 350, ideal: 450, max: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "Sélectionnez une classe",
                    systemImage: "person.3",
                    description: Text("Choisissez une classe dans la barre latérale ou créez-en une nouvelle")
                )
            }
        } detail: {
            // Detail - submission, student progress, or statistics
            Group {
                if let student = selectedStudent, let assignment = selectedAssignment {
                    SubmissionDetailView(
                        studentId: student.id,
                        assignmentId: assignment.id
                    )
                } else if let student = selectedStudentForProgress {
                    StudentProgressView(studentId: student.id)
                } else if let assignment = selectedAssignment {
                    AssignmentStatisticsView(assignmentId: assignment.id)
                } else if let selectedClass = selectedClass {
                    ClassStatisticsView(classId: selectedClass.id)
                } else {
                    ContentUnavailableView(
                        "Gestion des classes",
                        systemImage: "graduationcap",
                        description: Text("Organisez vos classes, devoirs et élèves pour corriger efficacement")
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 500, max: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingRubricManagement = true
                } label: {
                    Label("Barèmes", systemImage: "list.bullet.rectangle")
                }
                .help("Gérer les barèmes de notation")
            }
        }
        .sheet(isPresented: $showingRubricManagement) {
            NavigationStack {
                RubricManagementView()
                    .navigationTitle("Gestion des barèmes")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fermer") {
                                showingRubricManagement = false
                            }
                        }
                    }
            }
            .frame(minWidth: 800, minHeight: 600)
        }
        .sheet(isPresented: $showingAddClass) {
            AddClassSheet(isPresented: $showingAddClass) { newClass in
                dataStore.addClass(newClass)
                selectedClass = newClass
            }
        }
        .sheet(isPresented: $showingAddAssignment) {
            if let classId = selectedClass?.id {
                AddAssignmentSheet(classId: classId, isPresented: $showingAddAssignment) { newAssignment in
                    dataStore.addAssignment(newAssignment)
                    selectedAssignment = newAssignment
                }
            }
        }
        .sheet(isPresented: $showingAddStudent) {
            if let classId = selectedClass?.id {
                AddStudentSheet(classId: classId, isPresented: $showingAddStudent) { newStudent in
                    dataStore.addStudent(newStudent)
                }
            }
        }
    }
}

// MARK: - Sidebar

struct ClassroomSidebar: View {
    @State private var dataStore = DataStore.shared
    @Binding var selectedClass: SchoolClass?
    @Binding var selectedAssignment: Assignment?
    @Binding var selectedStudent: Student?
    @Binding var showingAddClass: Bool
    @Binding var modeBinding: ContentView.AppMode

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector at top
            Picker("Mode", selection: $modeBinding) {
                ForEach(ContentView.AppMode.allCases, id: \.self) { mode in
                    Label(mode.shortName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Classes list with shortcuts
            List(selection: $selectedClass) {
                Section("Mes classes") {
                    ForEach(dataStore.classes) { schoolClass in
                        ClassRow(schoolClass: schoolClass, isSelected: selectedClass?.id == schoolClass.id)
                            .tag(schoolClass)
                            .contextMenu {
                                Button("Supprimer", role: .destructive) {
                                    if selectedClass?.id == schoolClass.id {
                                        selectedClass = nil
                                        selectedAssignment = nil
                                        selectedStudent = nil
                                    }
                                    dataStore.deleteClass(schoolClass.id)
                                }
                            }
                    }
                }

                Section("Statistiques") {
                    HStack {
                        Label("Classes", systemImage: "person.3")
                        Spacer()
                        Text("\(dataStore.classes.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Élèves", systemImage: "person")
                        Spacer()
                        Text("\(dataStore.students.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("À traiter", systemImage: "doc.badge.clock")
                        Spacer()
                        let pending = dataStore.submissions.filter { $0.status == .pending && !$0.imagePaths.isEmpty }.count
                        Text("\(pending)")
                            .foregroundStyle(pending > 0 ? .orange : .secondary)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddClass = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Ajouter une classe")
            }
        }
        .onChange(of: selectedClass) { _, newValue in
            // Reset sub-selections when class changes
            if newValue?.id != selectedAssignment?.classId {
                selectedAssignment = nil
                selectedStudent = nil
            }
        }
    }
}

struct ClassRow: View {
    let schoolClass: SchoolClass
    let isSelected: Bool
    @State private var dataStore = DataStore.shared

    var studentCount: Int {
        dataStore.getStudents(for: schoolClass.id).count
    }

    var body: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .foregroundStyle(isSelected ? .white : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(schoolClass.name)
                    .font(.headline)

                Text("\(studentCount) élève\(studentCount > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Class Detail View

struct ClassDetailView: View {
    @Binding var schoolClass: SchoolClass
    @Binding var selectedAssignment: Assignment?
    @Binding var selectedStudentForProgress: Student?
    @Binding var showingAddAssignment: Bool
    @Binding var showingAddStudent: Bool
    @State private var dataStore = DataStore.shared
    @State private var selectedTab = 0

    var students: [Student] {
        dataStore.getStudents(for: schoolClass.id)
    }

    var assignments: [Assignment] {
        dataStore.getAssignments(for: schoolClass.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(schoolClass.name)
                    .font(.title)
                    .bold()
                    .lineLimit(1)

                if !schoolClass.level.isEmpty || !schoolClass.year.isEmpty {
                    Text([schoolClass.level, schoolClass.year].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Quick stats - horizontal layout
                HStack(spacing: 16) {
                    StatBadge(value: students.count, label: "Élèves", icon: "person.fill")
                    StatBadge(value: assignments.count, label: "Devoirs", icon: "doc.text.fill")
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.bar)

            Divider()

            // Tabs
            Picker("Vue", selection: $selectedTab) {
                Text("Devoirs").tag(0)
                Text("Élèves").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            if selectedTab == 0 {
                AssignmentListView(
                    classId: schoolClass.id,
                    selectedAssignment: $selectedAssignment,
                    showingAddAssignment: $showingAddAssignment
                )
            } else {
                StudentListView(
                    classId: schoolClass.id,
                    selectedStudent: $selectedStudentForProgress,
                    showingAddStudent: $showingAddStudent
                )
            }
        }
        .navigationTitle(schoolClass.name)
        .onChange(of: selectedTab) { _, newTab in
            // Clear selections when switching tabs
            if newTab == 0 {
                selectedStudentForProgress = nil
            } else {
                selectedAssignment = nil
            }
        }
    }
}

struct StatBadge: View {
    let value: Int
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.headline)
                .bold()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Assignment List

struct AssignmentListView: View {
    let classId: UUID
    @Binding var selectedAssignment: Assignment?
    @Binding var showingAddAssignment: Bool
    @State private var dataStore = DataStore.shared

    var assignments: [Assignment] {
        dataStore.getAssignments(for: classId)
    }

    var body: some View {
        if assignments.isEmpty {
            ContentUnavailableView {
                Label("Aucun devoir", systemImage: "doc.text")
            } description: {
                Text("Créez votre premier devoir pour cette classe")
            } actions: {
                Button("Ajouter un devoir") {
                    showingAddAssignment = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            List(assignments, selection: $selectedAssignment) { assignment in
                AssignmentRow(assignment: assignment)
                    .tag(assignment)
                    .contextMenu {
                        Button("Supprimer", role: .destructive) {
                            if selectedAssignment?.id == assignment.id {
                                selectedAssignment = nil
                            }
                            dataStore.deleteAssignment(assignment.id)
                        }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddAssignment = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

struct AssignmentRow: View {
    let assignment: Assignment
    @State private var dataStore = DataStore.shared

    var submissionCount: Int {
        dataStore.getSubmissions(forAssignment: assignment.id).count
    }

    var gradedCount: Int {
        dataStore.getSubmissions(forAssignment: assignment.id).filter { $0.finalGrade != nil }.count
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.title)
                    .font(.headline)

                HStack(spacing: 8) {
                    if let dueDate = assignment.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(gradedCount)/\(submissionCount) notés")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("/\(Int(assignment.maxScore))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Student List

struct StudentListView: View {
    let classId: UUID
    @Binding var selectedStudent: Student?
    @Binding var showingAddStudent: Bool
    @State private var dataStore = DataStore.shared
    @State private var searchText = ""

    var students: [Student] {
        let allStudents = dataStore.getStudents(for: classId)
        if searchText.isEmpty {
            return allStudents
        }
        return allStudents.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        if dataStore.getStudents(for: classId).isEmpty {
            ContentUnavailableView {
                Label("Aucun élève", systemImage: "person")
            } description: {
                Text("Ajoutez des élèves à cette classe")
            } actions: {
                Button("Ajouter un élève") {
                    showingAddStudent = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            List(students, selection: $selectedStudent) { student in
                StudentRow(student: student, isSelected: selectedStudent?.id == student.id)
                    .tag(student)
                    .contextMenu {
                        Button("Voir le progrès") {
                            selectedStudent = student
                        }
                        Divider()
                        Button("Supprimer", role: .destructive) {
                            if selectedStudent?.id == student.id {
                                selectedStudent = nil
                            }
                            dataStore.deleteStudent(student.id)
                        }
                    }
            }
            .searchable(text: $searchText, prompt: "Rechercher un élève")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddStudent = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
        }
    }
}

struct StudentRow: View {
    let student: Student
    var isSelected: Bool = false
    @State private var dataStore = DataStore.shared

    var submissionCount: Int {
        dataStore.getSubmissions(forStudent: student.id).count
    }

    var averageGrade: Double? {
        let grades = dataStore.getSubmissions(forStudent: student.id).compactMap { $0.finalGrade }
        guard !grades.isEmpty else { return nil }
        return grades.reduce(0, +) / Double(grades.count)
    }

    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(isSelected ? .white : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName)
                    .font(.headline)

                if let email = student.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let avg = averageGrade {
                Text(String(format: "%.1f", avg))
                    .font(.headline)
                    .foregroundStyle(GradeUtilities.color(for: avg))
            }

            Text("\(submissionCount) copie\(submissionCount > 1 ? "s" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

}

// MARK: - Previews

#Preview {
    ClassroomView(modeBinding: .constant(.classroom))
}
