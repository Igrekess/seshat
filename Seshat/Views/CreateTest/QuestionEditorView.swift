import SwiftUI

/// Editor view for a single question
struct QuestionEditorView: View {
    @Binding var question: Question
    var onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Label("Question \(question.order + 1)", systemImage: question.type.icon)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    // Actions menu
                    Menu {
                        if let onDuplicate = onDuplicate {
                            Button {
                                onDuplicate()
                            } label: {
                                Label("Dupliquer", systemImage: "doc.on.doc")
                            }
                        }

                        if let onDelete = onDelete {
                            Divider()
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                    }
                    .menuStyle(.borderlessButton)
                }

                Divider()

                // Question Type & Settings
                GroupBox {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Type")
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("Type", selection: $question.type) {
                                ForEach(QuestionType.allCases) { type in
                                    Label(type.displayName, systemImage: type.icon)
                                        .tag(type)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("Difficulté")
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("Difficulté", selection: Binding(
                                get: { question.difficultyLevel ?? .medium },
                                set: { question.difficultyLevel = $0 }
                            )) {
                                ForEach(DifficultyLevel.allCases) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }

                        HStack {
                            Text("Points")
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("Points", value: $question.points, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } label: {
                    Label("Paramètres", systemImage: "gearshape")
                }

                // Question Text
                GroupBox {
                    TextEditor(text: $question.text)
                        .font(.body)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                } label: {
                    Label("Énoncé de la question", systemImage: "text.alignleft")
                }

                // Type-specific content
                switch question.type {
                case .multipleChoice:
                    MCQOptionsEditor(options: Binding(
                        get: { question.options ?? [] },
                        set: { question.options = $0 }
                    ))

                case .trueFalse:
                    TrueFalseEditor(correctAnswer: Binding(
                        get: { question.correctAnswer ?? true },
                        set: { question.correctAnswer = $0 }
                    ))

                case .openEnded:
                    OpenEndedEditor(
                        expectedAnswer: Binding(
                            get: { question.expectedAnswer ?? "" },
                            set: { question.expectedAnswer = $0 }
                        ),
                        rubricGuidelines: Binding(
                            get: { question.rubricGuidelines ?? "" },
                            set: { question.rubricGuidelines = $0 }
                        )
                    )

                case .shortAnswer:
                    ShortAnswerEditor(expectedAnswer: Binding(
                        get: { question.expectedAnswer ?? "" },
                        set: { question.expectedAnswer = $0 }
                    ))
                }

                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - MCQ Options Editor

struct MCQOptionsEditor: View {
    @Binding var options: [MCQOption]

    var body: some View {
        GroupBox {
            VStack(spacing: 12) {
                ForEach(options.indices, id: \.self) { index in
                    MCQOptionRow(
                        option: $options[index],
                        label: String(UnicodeScalar(65 + index)!), // A, B, C, D...
                        onDelete: options.count > 2 ? { deleteOption(at: index) } : nil
                    )
                }

                if options.count < 6 {
                    Button {
                        addOption()
                    } label: {
                        Label("Ajouter une option", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } label: {
            HStack {
                Label("Options de réponse", systemImage: "list.bullet.circle")
                Spacer()
                Text("Cochez la/les bonne(s) réponse(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func addOption() {
        options.append(MCQOption(text: ""))
    }

    private func deleteOption(at index: Int) {
        options.remove(at: index)
    }
}

struct MCQOptionRow: View {
    @Binding var option: MCQOption
    let label: String
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Correct answer toggle
            Button {
                option.isCorrect.toggle()
            } label: {
                Image(systemName: option.isCorrect ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(option.isCorrect ? .green : .secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)

            // Option label
            Text(label)
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Option text
            TextField("Option \(label)", text: $option.text)
                .textFieldStyle(.roundedBorder)

            // Delete button
            if let onDelete = onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - True/False Editor

struct TrueFalseEditor: View {
    @Binding var correctAnswer: Bool

    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                Text("Quelle est la bonne réponse ?")
                    .foregroundColor(.secondary)

                Picker("Réponse correcte", selection: $correctAnswer) {
                    Text("Vrai").tag(true)
                    Text("Faux").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .frame(maxWidth: .infinity)
        } label: {
            Label("Réponse correcte", systemImage: "checkmark.circle")
        }
    }
}

// MARK: - Open-Ended Editor

struct OpenEndedEditor: View {
    @Binding var expectedAnswer: String
    @Binding var rubricGuidelines: String

    var body: some View {
        VStack(spacing: 16) {
            GroupBox {
                TextEditor(text: $expectedAnswer)
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
            } label: {
                Label("Réponse attendue / Points clés", systemImage: "text.justify")
            }

            GroupBox {
                TextEditor(text: $rubricGuidelines)
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
            } label: {
                Label("Critères de notation", systemImage: "star")
            }
        }
    }
}

// MARK: - Short Answer Editor

struct ShortAnswerEditor: View {
    @Binding var expectedAnswer: String

    var body: some View {
        GroupBox {
            TextField("Réponse attendue", text: $expectedAnswer)
                .textFieldStyle(.roundedBorder)
        } label: {
            Label("Réponse attendue", systemImage: "text.cursor")
        }
    }
}

#Preview {
    QuestionEditorView(
        question: .constant(Question(
            type: .multipleChoice,
            text: "What is the capital of France?",
            points: 2,
            options: [
                MCQOption(text: "London", isCorrect: false),
                MCQOption(text: "Paris", isCorrect: true),
                MCQOption(text: "Berlin", isCorrect: false),
                MCQOption(text: "Madrid", isCorrect: false)
            ],
            difficultyLevel: .easy,
            order: 0
        ))
    )
    .frame(width: 500, height: 700)
}
