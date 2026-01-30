import SwiftUI

/// Vue d'onboarding pour le téléchargement initial des modèles
struct OnboardingView: View {
    @ObservedObject private var modelService = ModelDownloadService.shared
    @State private var isDownloading = false
    @State private var currentModel: SeshatModel?
    @State private var downloadError: Error?
    @State private var downloadComplete = false

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("Bienvenue dans Seshat")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Aide à la correction")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Description
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "text.viewfinder",
                    title: "Transcription manuscrite",
                    description: "Reconnaissance d'écriture avec Chandra HTR"
                )

                FeatureRow(
                    icon: "magnifyingglass",
                    title: "Analyse linguistique",
                    description: "Détection d'erreurs avec Qwen 2.5"
                )

                FeatureRow(
                    icon: "lock.shield.fill",
                    title: "100% local",
                    description: "Aucune donnée envoyée sur internet"
                )
            }
            .padding(.horizontal, 32)

            Divider()
                .padding(.horizontal, 32)

            // Models status
            VStack(spacing: 16) {
                Text("Modèles à télécharger")
                    .font(.headline)

                ForEach(SeshatModel.allCases) { model in
                    OnboardingModelRow(
                        model: model,
                        state: modelService.downloadStates[model],
                        isCurrent: currentModel == model
                    )
                }

                if let error = downloadError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                if downloadComplete {
                    Button(action: onComplete) {
                        Text("Commencer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(action: startDownload) {
                        if isDownloading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Téléchargement en cours...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Télécharger les modèles (~8 GB)")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isDownloading)

                    if !isDownloading {
                        Button("Passer (fonctionnalités limitées)", action: onComplete)
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 500, height: 650)
        .onAppear {
            checkDownloadStatus()
        }
    }

    private func checkDownloadStatus() {
        downloadComplete = modelService.allRequiredModelsDownloaded
    }

    private func startDownload() {
        Task {
            isDownloading = true
            downloadError = nil

            for model in SeshatModel.allCases {
                if !modelService.isModelDownloaded(model) {
                    currentModel = model
                    do {
                        try await modelService.downloadModel(model)
                    } catch {
                        downloadError = error
                        isDownloading = false
                        return
                    }
                }
            }

            currentModel = nil
            isDownloading = false
            downloadComplete = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct OnboardingModelRow: View {
    let model: SeshatModel
    let state: ModelDownloadState?
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .fontWeight(.medium)
                Text(model.estimatedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusIcon
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state?.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("\(Int((state?.progress ?? 0) * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)

        case .notStarted, .none:
            Image(systemName: "arrow.down.circle")
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
