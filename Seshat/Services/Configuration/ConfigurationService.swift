import Foundation

/// Service for managing user preferences and configuration
@MainActor
final class ConfigurationService: Sendable {
    static let shared = ConfigurationService()

    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "seshat.user.preferences"

    private init() {}

    // MARK: - Preferences

    func loadPreferences() -> UserPreferences {
        guard let data = userDefaults.data(forKey: preferencesKey),
              let preferences = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return UserPreferences()
        }
        return preferences
    }

    func savePreferences(_ preferences: UserPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        userDefaults.set(data, forKey: preferencesKey)
    }

    func resetPreferences() {
        userDefaults.removeObject(forKey: preferencesKey)
    }

    // MARK: - Export/Import

    nonisolated func exportPreferences(to url: URL, preferences: UserPreferences) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: url)
    }

    nonisolated func importPreferences(from url: URL) throws -> UserPreferences {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UserPreferences.self, from: data)
    }

    // MARK: - Model Paths

    nonisolated var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Seshat/Models")
    }

    nonisolated func ensureModelDirectoryExists() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Temporary Data

    nonisolated var tempDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Seshat")
    }

    nonisolated func clearTempData() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: tempDirectory)
    }

    // MARK: - Storage Info

    nonisolated func getStorageInfo() -> StorageInfo {
        let fileManager = FileManager.default

        // Calculate model size
        var modelSize: Int64 = 0
        if let enumerator = fileManager.enumerator(at: modelDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    modelSize += Int64(size)
                }
            }
        }

        // Calculate temp size
        var tempSize: Int64 = 0
        if let enumerator = fileManager.enumerator(at: tempDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    tempSize += Int64(size)
                }
            }
        }

        return StorageInfo(
            modelStorageBytes: modelSize,
            tempStorageBytes: tempSize,
            preferencesStorageBytes: 0
        )
    }
}

// MARK: - User Preferences
struct UserPreferences: Codable, Sendable {
    var categoryColors: [ErrorCategory: String]
    var predefinedComments: [PredefinedComment]
    var showConfidenceIndicators: Bool
    var autoStartAnalysis: Bool
    var defaultExportPath: String?

    init(
        categoryColors: [ErrorCategory: String] = [:],
        predefinedComments: [PredefinedComment] = [],
        showConfidenceIndicators: Bool = true,
        autoStartAnalysis: Bool = false,
        defaultExportPath: String? = nil
    ) {
        // Use default colors if not specified
        var colors = categoryColors
        for category in ErrorCategory.allCases {
            if colors[category] == nil {
                colors[category] = category.defaultColor
            }
        }
        self.categoryColors = colors
        self.predefinedComments = predefinedComments
        self.showConfidenceIndicators = showConfidenceIndicators
        self.autoStartAnalysis = autoStartAnalysis
        self.defaultExportPath = defaultExportPath
    }
}

struct PredefinedComment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var text: String
    var category: ErrorCategory?

    init(id: UUID = UUID(), title: String, text: String, category: ErrorCategory? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.category = category
    }
}

struct StorageInfo: Sendable {
    let modelStorageBytes: Int64
    let tempStorageBytes: Int64
    let preferencesStorageBytes: Int64

    var totalBytes: Int64 {
        modelStorageBytes + tempStorageBytes + preferencesStorageBytes
    }

    var formattedModelStorage: String {
        ByteCountFormatter.string(fromByteCount: modelStorageBytes, countStyle: .file)
    }

    var formattedTempStorage: String {
        ByteCountFormatter.string(fromByteCount: tempStorageBytes, countStyle: .file)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}
