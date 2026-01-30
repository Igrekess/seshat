import Foundation
import Hub
import MLXLMCommon

/// Définition des modèles requis par Seshat
enum SeshatModel: String, CaseIterable, Identifiable {
    case chandra = "mlx-community/chandra-4bit"
    case qwenAnalysis = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chandra: return "Chandra HTR"
        case .qwenAnalysis: return "Qwen 2.5 Analysis (7B)"
        }
    }

    var description: String {
        switch self {
        case .chandra:
            return "Modèle de reconnaissance d'écriture manuscrite (9B params)"
        case .qwenAnalysis:
            return "Modèle d'analyse linguistique pour correction grammaticale (7B params)"
        }
    }

    var estimatedSize: String {
        switch self {
        case .chandra: return "~6 GB"
        case .qwenAnalysis: return "~4.5 GB"
        }
    }

    var estimatedSizeBytes: Int64 {
        switch self {
        case .chandra: return 6_000_000_000
        case .qwenAnalysis: return 4_500_000_000
        }
    }

    var isRequired: Bool {
        true // Both models are required for full functionality
    }
}

/// État du téléchargement d'un modèle
struct ModelDownloadState: Identifiable {
    let id: SeshatModel
    var status: DownloadStatus
    var progress: Double
    var error: Error?

    enum DownloadStatus {
        case notStarted
        case downloading
        case completed
        case failed
    }
}

/// Service de téléchargement et gestion des modèles MLX
@MainActor
final class ModelDownloadService: ObservableObject {
    static let shared = ModelDownloadService()

    @Published var downloadStates: [SeshatModel: ModelDownloadState] = [:]
    @Published var isDownloading = false
    @Published var currentDownload: SeshatModel?
    @Published var overallProgress: Double = 0

    private let hubApi: HubApi
    private let modelsDirectory: URL

    private init() {
        self.hubApi = HubApi()

        // Répertoire des modèles : ~/Library/Application Support/Seshat/Models/
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.modelsDirectory = appSupport.appendingPathComponent("Seshat/Models")

        // Créer le répertoire si nécessaire
        try? FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )

        // Initialiser les états
        for model in SeshatModel.allCases {
            downloadStates[model] = ModelDownloadState(
                id: model,
                status: isModelDownloaded(model) ? .completed : .notStarted,
                progress: isModelDownloaded(model) ? 1.0 : 0.0
            )
        }
    }

    // MARK: - Public API

    /// Vérifie si un modèle est téléchargé
    func isModelDownloaded(_ model: SeshatModel) -> Bool {
        let modelDir = modelDirectory(for: model)
        let configPath = modelDir.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configPath.path)
    }

    /// Vérifie si tous les modèles requis sont téléchargés
    var allRequiredModelsDownloaded: Bool {
        SeshatModel.allCases
            .filter { $0.isRequired }
            .allSatisfy { isModelDownloaded($0) }
    }

    /// Retourne le chemin local d'un modèle
    func modelDirectory(for model: SeshatModel) -> URL {
        // HubApi stocke les modèles dans son cache
        let repo = Hub.Repo(id: model.rawValue)
        return hubApi.localRepoLocation(repo)
    }

    /// Télécharge un modèle spécifique
    func downloadModel(_ model: SeshatModel) async throws {
        guard !isModelDownloaded(model) else { return }

        isDownloading = true
        currentDownload = model
        downloadStates[model]?.status = .downloading
        downloadStates[model]?.progress = 0

        do {
            let configuration = ModelConfiguration(id: model.rawValue)

            _ = try await MLXLMCommon.downloadModel(
                hub: hubApi,
                configuration: configuration
            ) { [weak self] progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    self?.downloadStates[model]?.progress = fraction
                    self?.updateOverallProgress()
                }
            }

            downloadStates[model]?.status = .completed
            downloadStates[model]?.progress = 1.0

        } catch {
            downloadStates[model]?.status = .failed
            downloadStates[model]?.error = error
            throw error
        }

        isDownloading = false
        currentDownload = nil
        updateOverallProgress()
    }

    /// Télécharge tous les modèles requis
    func downloadAllRequiredModels() async throws {
        let modelsToDownload = SeshatModel.allCases.filter {
            $0.isRequired && !isModelDownloaded($0)
        }

        for model in modelsToDownload {
            try await downloadModel(model)
        }
    }

    /// Supprime un modèle téléchargé
    func deleteModel(_ model: SeshatModel) throws {
        let modelDir = modelDirectory(for: model)
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        downloadStates[model]?.status = .notStarted
        downloadStates[model]?.progress = 0
    }

    /// Calcule l'espace disque utilisé par les modèles
    var totalDiskUsage: Int64 {
        SeshatModel.allCases.reduce(0) { total, model in
            total + diskUsage(for: model)
        }
    }

    func diskUsage(for model: SeshatModel) -> Int64 {
        let modelDir = modelDirectory(for: model)
        return directorySize(at: modelDir)
    }

    // MARK: - Private Helpers

    private func updateOverallProgress() {
        let total = Double(SeshatModel.allCases.count)
        let completed = SeshatModel.allCases.reduce(0.0) { sum, model in
            sum + (downloadStates[model]?.progress ?? 0)
        }
        overallProgress = completed / total
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }
}

// MARK: - Formatted Helpers

extension ModelDownloadService {
    func formattedDiskUsage(for model: SeshatModel) -> String {
        let bytes = diskUsage(for: model)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var formattedTotalDiskUsage: String {
        ByteCountFormatter.string(fromByteCount: totalDiskUsage, countStyle: .file)
    }
}
