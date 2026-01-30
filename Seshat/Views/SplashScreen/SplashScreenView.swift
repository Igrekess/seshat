import SwiftUI

/// Splash screen avec préchargement des modèles MLX
struct SplashScreenView: View {
    @ObservedObject private var modelService = ModelDownloadService.shared

    @State private var loadingPhase: LoadingPhase = .initializing
    @State private var loadingProgress: Double = 0
    @State private var loadingMessage: String = "Initialisation..."
    @State private var isComplete = false
    @State private var loadError: Error?
    @State private var modelState = ModelLoadingState()

    let onComplete: () -> Void

    enum LoadingPhase: String {
        case initializing = "Initialisation..."
        case checkingModels = "Vérification des modèles..."
        case loadingModels = "Chargement des modèles IA..."
        case ready = "Prêt !"
    }

    struct ModelLoadingState {
        var chandraLoaded = false
        var qwenLoaded = false
        var chandraError: Error?
        var qwenError: Error?
    }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Logo animé
            ZStack {
                // Cercle de fond
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                // Icône
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Titre
            VStack(spacing: 8) {
                Text("Seshat")
                    .font(.system(size: 42, weight: .bold, design: .rounded))

                Text("Aide à la correcton de copie")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Zone de chargement
            VStack(spacing: 16) {
                // Barre de progression
                ProgressView(value: loadingProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 300)

                // Message de statut
                HStack(spacing: 8) {
                    if !isComplete && loadError == nil {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if loadError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }

                    Text(loadingMessage)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                // Afficher l'erreur si présente
                if let error = loadError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)

                    Button("Continuer sans préchargement") {
                        onComplete()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
            }

            Spacer()

            // Version
            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.bottom, 20)
        }
        .frame(width: 500, height: 450)
        .onAppear {
            startPreloading()
        }
    }

    private func startPreloading() {
        Task {
            do {
                // Phase 1: Vérification
                loadingPhase = .checkingModels
                loadingMessage = loadingPhase.rawValue
                loadingProgress = 0.05

                // Vérifier que les modèles sont téléchargés
                guard modelService.allRequiredModelsDownloaded else {
                    loadingMessage = "Modèles non téléchargés"
                    loadingProgress = 1.0
                    isComplete = true

                    // Attendre un peu puis continuer (l'onboarding s'affichera)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    onComplete()
                    return
                }

                loadingProgress = 0.1

                // Phase 2: Charger les deux modèles EN PARALLÈLE
                loadingPhase = .loadingModels
                loadingMessage = "Chargement des modèles IA (parallèle)..."

                // Lancer les deux chargements simultanément
                async let chandraTask: () = loadChandra()
                async let qwenTask: () = loadQwen()

                // Attendre que les deux soient terminés
                _ = await (chandraTask, qwenTask)

                // Vérifier les erreurs
                if let error = modelState.chandraError ?? modelState.qwenError {
                    throw error
                }

                loadingProgress = 1.0

                // Terminé
                loadingPhase = .ready
                loadingMessage = buildCompletionMessage()
                isComplete = true

                // Petite pause pour montrer "Prêt !"
                try? await Task.sleep(nanoseconds: 300_000_000)

                onComplete()

            } catch {
                loadError = error
                loadingMessage = "Erreur de chargement"
            }
        }
    }

    private func loadChandra() async {
        do {
            try await ChandraMLXService.shared.loadModel()
            modelState.chandraLoaded = true
            updateProgress()
        } catch {
            modelState.chandraError = error
        }
    }

    private func loadQwen() async {
        do {
            try await QwenAnalysisService.shared.loadModel()
            modelState.qwenLoaded = true
            updateProgress()
        } catch {
            modelState.qwenError = error
        }
    }

    private func updateProgress() {
        var progress = 0.1 // Base après vérification
        if modelState.chandraLoaded { progress += 0.45 }
        if modelState.qwenLoaded { progress += 0.45 }
        loadingProgress = progress

        // Mettre à jour le message
        var parts: [String] = []
        if modelState.chandraLoaded { parts.append("Chandra ✓") }
        if modelState.qwenLoaded { parts.append("Qwen ✓") }

        if parts.isEmpty {
            loadingMessage = "Compilation des modèles Metal..."
        } else if parts.count == 1 {
            loadingMessage = "\(parts[0]) — En attente de l'autre modèle..."
        } else {
            loadingMessage = "Tous les modèles chargés !"
        }
    }

    private func buildCompletionMessage() -> String {
        if modelState.chandraLoaded && modelState.qwenLoaded {
            return "Prêt ! (2 modèles chargés)"
        } else if modelState.chandraLoaded {
            return "Prêt ! (Chandra uniquement)"
        } else if modelState.qwenLoaded {
            return "Prêt ! (Qwen uniquement)"
        } else {
            return "Prêt !"
        }
    }
}

#Preview {
    SplashScreenView(onComplete: {})
}
