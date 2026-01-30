import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("Général", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            ModelsSettingsView()
                .tabItem {
                    Label("Modèles", systemImage: "cpu")
                }
                .tag(SettingsTab.models)

            ColorsSettingsView()
                .tabItem {
                    Label("Couleurs", systemImage: "paintpalette")
                }
                .tag(SettingsTab.colors)

            CommentsSettingsView()
                .tabItem {
                    Label("Commentaires", systemImage: "text.bubble")
                }
                .tag(SettingsTab.comments)

            DataSettingsView()
                .tabItem {
                    Label("Données", systemImage: "externaldrive")
                }
                .tag(SettingsTab.data)
        }
        .frame(width: 550, height: 450)
    }
}

enum SettingsTab {
    case general
    case models
    case colors
    case comments
    case data
}

// MARK: - Models Settings
struct ModelsSettingsView: View {
    @ObservedObject private var modelService = ModelDownloadService.shared
    @State private var downloadError: Error?
    @State private var showDeleteAlert = false
    @State private var modelToDelete: SeshatModel?

    var body: some View {
        Form {
            Section("Modèles requis") {
                ForEach(SeshatModel.allCases) { model in
                    ModelRowView(
                        model: model,
                        state: modelService.downloadStates[model],
                        onDownload: { downloadModel(model) },
                        onDelete: {
                            modelToDelete = model
                            showDeleteAlert = true
                        }
                    )
                }
            }

            Section("Espace disque") {
                LabeledContent("Modèles téléchargés", value: modelService.formattedTotalDiskUsage)

                HStack {
                    Text("Statut")
                    Spacer()
                    if modelService.allRequiredModelsDownloaded {
                        Label("Tous les modèles sont prêts", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Modèles manquants", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }

            Section("Actions") {
                Button("Télécharger tous les modèles manquants") {
                    downloadAllModels()
                }
                .disabled(modelService.allRequiredModelsDownloaded || modelService.isDownloading)

                Button("Ouvrir le dossier des modèles") {
                    if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                        let modelsURL = url.appendingPathComponent("Seshat/Models")
                        NSWorkspace.shared.open(modelsURL)
                    }
                }
            }

            if let error = downloadError {
                Section("Erreur") {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Supprimer le modèle ?", isPresented: $showDeleteAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                if let model = modelToDelete {
                    try? modelService.deleteModel(model)
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("Le modèle \(model.displayName) sera supprimé. Vous devrez le retélécharger pour l'utiliser.")
            }
        }
    }

    private func downloadModel(_ model: SeshatModel) {
        Task {
            do {
                downloadError = nil
                try await modelService.downloadModel(model)
            } catch {
                downloadError = error
            }
        }
    }

    private func downloadAllModels() {
        Task {
            do {
                downloadError = nil
                try await modelService.downloadAllRequiredModels()
            } catch {
                downloadError = error
            }
        }
    }
}

struct ModelRowView: View {
    let model: SeshatModel
    let state: ModelDownloadState?
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .fontWeight(.medium)
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusView
            }

            if let state = state, state.status == .downloading {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state?.status {
        case .completed:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(model.estimatedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

        case .downloading:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("\(Int(state?.progress ?? 0 * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }

        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Button("Réessayer", action: onDownload)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

        case .notStarted, .none:
            HStack(spacing: 8) {
                Text(model.estimatedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Télécharger", action: onDownload)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @State private var preferences = ConfigurationService.shared.loadPreferences()

    var body: some View {
        Form {
            Section("Transcription") {
                Toggle("Afficher les indicateurs de confiance", isOn: $preferences.showConfidenceIndicators)
                    .onChange(of: preferences.showConfidenceIndicators) { _, _ in
                        savePreferences()
                    }

                Toggle("Lancer l'analyse automatiquement après validation", isOn: $preferences.autoStartAnalysis)
                    .onChange(of: preferences.autoStartAnalysis) { _, _ in
                        savePreferences()
                    }
            }

            Section("Export") {
                HStack {
                    Text("Dossier par défaut")
                    Spacer()
                    Text(preferences.defaultExportPath ?? "Bureau")
                        .foregroundColor(.secondary)
                    Button("Changer...") {
                        selectDefaultExportPath()
                    }
                }
            }

            Section("Préférences") {
                HStack {
                    Button("Exporter les préférences...") {
                        exportPreferences()
                    }

                    Button("Importer des préférences...") {
                        importPreferences()
                    }
                }

                Button("Réinitialiser les préférences", role: .destructive) {
                    ConfigurationService.shared.resetPreferences()
                    preferences = ConfigurationService.shared.loadPreferences()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func savePreferences() {
        ConfigurationService.shared.savePreferences(preferences)
    }

    private func selectDefaultExportPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            preferences.defaultExportPath = url.path
            savePreferences()
        }
    }

    private func exportPreferences() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "seshat_preferences.json"

        if panel.runModal() == .OK, let url = panel.url {
            try? ConfigurationService.shared.exportPreferences(to: url, preferences: preferences)
        }
    }

    private func importPreferences() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            if let imported = try? ConfigurationService.shared.importPreferences(from: url) {
                ConfigurationService.shared.savePreferences(imported)
                preferences = imported
            }
        }
    }
}

// MARK: - Colors Settings
struct ColorsSettingsView: View {
    @State private var preferences = ConfigurationService.shared.loadPreferences()

    var body: some View {
        Form {
            Section("Couleurs des catégories d'erreurs") {
                ForEach(ErrorCategory.allCases, id: \.self) { category in
                    ColorPickerRow(
                        category: category,
                        color: Binding(
                            get: {
                                Color(nsColor: NSColor(hex: preferences.categoryColors[category] ?? category.defaultColor) ?? .gray)
                            },
                            set: { newColor in
                                if let nsColor = NSColor(newColor) {
                                    preferences.categoryColors[category] = nsColor.hexString
                                    savePreferences()
                                }
                            }
                        )
                    )
                }
            }

            Section {
                Button("Réinitialiser les couleurs par défaut") {
                    for category in ErrorCategory.allCases {
                        preferences.categoryColors[category] = category.defaultColor
                    }
                    savePreferences()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func savePreferences() {
        ConfigurationService.shared.savePreferences(preferences)
    }
}

struct ColorPickerRow: View {
    let category: ErrorCategory
    @Binding var color: Color

    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(category.displayName)

            Spacer()

            ColorPicker("", selection: $color)
                .labelsHidden()
        }
    }
}

// MARK: - Comments Settings
struct CommentsSettingsView: View {
    @State private var preferences = ConfigurationService.shared.loadPreferences()
    @State private var newCommentTitle = ""
    @State private var newCommentText = ""
    @State private var newCommentCategory: ErrorCategory?

    var body: some View {
        VStack(spacing: 0) {
            // List of existing comments
            List {
                ForEach(preferences.predefinedComments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(comment.title)
                                .fontWeight(.medium)

                            if let category = comment.category {
                                Text(category.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: NSColor(hex: category.defaultColor) ?? .gray).opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }

                        Text(comment.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteComment)
            }

            Divider()

            // Add new comment form
            VStack(spacing: 12) {
                Text("Nouveau commentaire prédéfini")
                    .font(.headline)

                TextField("Titre", text: $newCommentTitle)
                    .textFieldStyle(.roundedBorder)

                TextField("Texte du commentaire", text: $newCommentText)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Picker("Catégorie", selection: $newCommentCategory) {
                        Text("Aucune").tag(nil as ErrorCategory?)
                        ForEach(ErrorCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category as ErrorCategory?)
                        }
                    }

                    Spacer()

                    Button("Ajouter") {
                        addComment()
                    }
                    .disabled(newCommentTitle.isEmpty || newCommentText.isEmpty)
                }
            }
            .padding()
        }
    }

    private func addComment() {
        let comment = PredefinedComment(
            title: newCommentTitle,
            text: newCommentText,
            category: newCommentCategory
        )
        preferences.predefinedComments.append(comment)
        ConfigurationService.shared.savePreferences(preferences)

        newCommentTitle = ""
        newCommentText = ""
        newCommentCategory = nil
    }

    private func deleteComment(at offsets: IndexSet) {
        preferences.predefinedComments.remove(atOffsets: offsets)
        ConfigurationService.shared.savePreferences(preferences)
    }
}

// MARK: - Data Settings
struct DataSettingsView: View {
    @State private var storageInfo = ConfigurationService.shared.getStorageInfo()

    var body: some View {
        Form {
            Section("Stockage local") {
                LabeledContent("Modèles ML", value: storageInfo.formattedModelStorage)
                LabeledContent("Fichiers temporaires", value: storageInfo.formattedTempStorage)
                LabeledContent("Total", value: storageInfo.formattedTotal)
            }

            Section("Actions") {
                Button("Supprimer les fichiers temporaires") {
                    ConfigurationService.shared.clearTempData()
                    storageInfo = ConfigurationService.shared.getStorageInfo()
                }

                Button("Ouvrir le dossier des modèles") {
                    NSWorkspace.shared.open(ConfigurationService.shared.modelDirectory)
                }
            }

            Section("Confidentialité") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Traitement 100% local", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)

                    Text("Seshat ne transmet aucune donnée sur internet. Toutes les copies et transcriptions sont traitées localement sur votre Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - NSColor Extension
extension NSColor {
    convenience init?(_ color: Color) {
        guard let cgColor = color.cgColor else { return nil }
        self.init(cgColor: cgColor)
    }

    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#Preview {
    SettingsView()
}
