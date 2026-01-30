import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedMode: AppMode = .classroom

    enum AppMode: String, CaseIterable {
        case classroom = "Gestion des classes"
        case singleCopy = "Copie unique"
        case createTest = "Créer un test"

        var icon: String {
            switch self {
            case .classroom: return "person.3.fill"
            case .singleCopy: return "doc.text.fill"
            case .createTest: return "pencil.and.list.clipboard"
            }
        }

        /// Short name for use in segmented pickers
        var shortName: String {
            switch self {
            case .classroom: return "Classes"
            case .singleCopy: return "Copie"
            case .createTest: return "Test"
            }
        }
    }

    var body: some View {
        Group {
            switch selectedMode {
            case .classroom:
                // Classroom mode - use ClassroomView's own NavigationSplitView
                ClassroomView(modeBinding: $selectedMode)

            case .createTest:
                // Create Test mode - use CreateTestView's own NavigationSplitView
                CreateTestView(modeBinding: $selectedMode)

            case .singleCopy:
                // Single copy mode - use NavigationSplitView
                NavigationSplitView {
                    VStack(spacing: 0) {
                        // Mode selector
                        Picker("Mode", selection: $selectedMode) {
                            ForEach(AppMode.allCases, id: \.self) { mode in
                                Label(mode.shortName, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()

                        Divider()

                        SidebarView()
                    }
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                } detail: {
                    MainContentView()
                }
                .navigationTitle("Seshat")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if selectedMode == .singleCopy {
                    ToolbarButtons()
                }
            }
        }
        .alert("Erreur", isPresented: Binding(
            get: { appState.showErrorAlert },
            set: { appState.showErrorAlert = $0 }
        )) {
            Button("OK") {
                appState.showErrorAlert = false
            }
        } message: {
            if let error = appState.currentError {
                Text(error.errorDescription ?? "Erreur inconnue")
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showImportDialog },
            set: { appState.showImportDialog = $0 }
        )) {
            ImportDialogView()
        }
    }
}

// MARK: - Sidebar View (Single Copy Mode)

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Workflow") {
                ForEach(WorkflowStep.allCases, id: \.self) { step in
                    WorkflowStepRow(step: step, isActive: appState.currentStep == step)
                        .onTapGesture {
                            if canNavigateTo(step) {
                                appState.currentStep = step
                            }
                        }
                }
            }

            if appState.currentCopy != nil {
                Section("Copie actuelle") {
                    CopyInfoView()
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func canNavigateTo(_ step: WorkflowStep) -> Bool {
        switch step {
        case .import:
            return true
        case .transcription:
            return appState.currentCopy != nil
        case .validation:
            return appState.transcriptionResult != nil
        case .analysis:
            return appState.transcriptionResult != nil
        case .export:
            return appState.analysisResult != nil
        }
    }
}

// MARK: - Workflow Step Row

struct WorkflowStepRow: View {
    let step: WorkflowStep
    let isActive: Bool

    var body: some View {
        HStack {
            Image(systemName: step.icon)
                .foregroundColor(isActive ? .accentColor : .secondary)
                .frame(width: 24)

            Text(step.title)
                .fontWeight(isActive ? .semibold : .regular)

            Spacer()

            if isActive {
                Image(systemName: "chevron.right")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Copy Info View

struct CopyInfoView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let copy = appState.currentCopy {
            VStack(alignment: .leading, spacing: 8) {
                Text(copy.originalFilename)
                    .font(.headline)
                    .lineLimit(1)

                Text(copy.status.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let transcription = appState.transcriptionResult {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Confiance: \(Int(transcription.overallConfidence * 100))%")
                            .font(.caption)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Main Content View

struct MainContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            switch appState.currentStep {
            case .import:
                ImportView()
            case .transcription:
                TranscriptionView()
            case .validation:
                ValidationView()
            case .analysis:
                AnalysisView()
            case .export:
                ExportView()
            }

            if appState.isProcessing {
                ProcessingOverlay()
            }
        }
    }
}

// MARK: - Processing Overlay

struct ProcessingOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Spinner animé
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 50, height: 50)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                }

                Text(appState.processingMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(.regularMaterial)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
