import SwiftUI

/// Sheet for configuring a new test before starting creation
struct NewTestSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var configuration: TestConfiguration
    var onStart: () -> Void
    var onQuickStart: () -> Void

    @State private var showingQuickStart = false

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info Section
                Section {
                    TextField("Titre du test", text: $configuration.title)
                        .textFieldStyle(.plain)

                    Picker("Matière", selection: $configuration.subject) {
                        Text("Sélectionner...").tag("")
                        ForEach(TestConfiguration.commonSubjects, id: \.self) { subject in
                            Text(subject).tag(subject)
                        }
                    }

                    Picker("Niveau", selection: $configuration.gradeLevel) {
                        Text("Sélectionner...").tag("")
                        ForEach(TestConfiguration.gradeLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                } header: {
                    Text("Informations")
                }

                // Question Types Section
                Section {
                    ForEach(QuestionType.allCases) { type in
                        Toggle(isOn: binding(for: type)) {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                } header: {
                    Text("Types de questions")
                } footer: {
                    Text("Sélectionnez les types de questions que vous souhaitez générer")
                }

                // Settings Section
                Section {
                    Stepper("Nombre de questions: \(configuration.targetQuestionCount)", value: $configuration.targetQuestionCount, in: 1...50)

                    HStack {
                        Text("Total des points")
                        Spacer()
                        TextField("Points", value: $configuration.totalPoints, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Toggle("Durée limitée", isOn: Binding(
                            get: { configuration.duration != nil },
                            set: { configuration.duration = $0 ? 60 : nil }
                        ))

                        if configuration.duration != nil {
                            Spacer()
                            Stepper(
                                "\(configuration.duration ?? 60) min",
                                value: Binding(
                                    get: { configuration.duration ?? 60 },
                                    set: { configuration.duration = $0 }
                                ),
                                in: 5...240,
                                step: 5
                            )
                            .frame(width: 140)
                        }
                    }
                } header: {
                    Text("Paramètres")
                }

                // Description Section
                Section {
                    TextEditor(text: $configuration.description)
                        .frame(minHeight: 80)
                } header: {
                    Text("Description / Contexte (optionnel)")
                } footer: {
                    Text("Décrivez le sujet, les chapitres couverts, ou toute information utile pour la génération")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nouveau test")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            onStart()
                            dismiss()
                        } label: {
                            Label("Démarrer avec configuration", systemImage: "play.fill")
                        }

                        Button {
                            onQuickStart()
                            dismiss()
                        } label: {
                            Label("Démarrage rapide", systemImage: "bolt.fill")
                        }
                    } label: {
                        Text("Démarrer")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    private func binding(for type: QuestionType) -> Binding<Bool> {
        Binding(
            get: { configuration.questionTypes.contains(type) },
            set: { isSelected in
                if isSelected {
                    configuration.questionTypes.insert(type)
                } else {
                    configuration.questionTypes.remove(type)
                }
            }
        )
    }
}

#Preview {
    NewTestSetupSheet(
        configuration: .constant(TestConfiguration()),
        onStart: {},
        onQuickStart: {}
    )
}
