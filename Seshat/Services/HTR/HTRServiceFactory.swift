import Foundation

/// Factory pour créer le meilleur service HTR disponible
///
/// Hiérarchie de priorité (Janvier 2026):
/// 1. Chandra (9B) - Score 83.1 - Mac 16GB+
/// 2. DeepSeek-OCR-2 (3B) - Score 75.4 - Mac 8GB
/// 3. Ollama - Fallback vision model
/// 4. Mock - Développement/démo
///
/// Note: olmOCR-2 (82.4, Apache 2.0) est une alternative à Chandra
/// si une licence 100% libre est requise.
@MainActor
final class HTRServiceFactory {
    private var cachedService: (any HTRServiceProtocol)?
    private var cachedLevel: HTRModelLevel?

    /// RAM système disponible en GB
    private var availableRAM: Double {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        return Double(physicalMemory) / (1024 * 1024 * 1024)
    }

    func createBestAvailableService() async -> (service: any HTRServiceProtocol, level: HTRModelLevel) {
        // Return cached service if available
        if let service = cachedService, let level = cachedLevel {
            return (service, level)
        }

        // Build priority list based on available RAM
        var servicesToTry: [(HTRModelLevel, () -> any HTRServiceProtocol)] = []

        // Chandra MLX requires 16GB+ (6GB model + system overhead)
        if availableRAM >= 16.0 {
            servicesToTry.append((.chandra, { ChandraMLXService.shared }))
        }

        // Ollama as fallback
        servicesToTry.append((.ollama, { OllamaHTRService() }))

        // Mock always available
        servicesToTry.append((.mock, { MockHTRService() }))

        for (level, createService) in servicesToTry {
            let service = createService()
            let available = await service.checkAvailability()
            if available {
                cachedService = service
                cachedLevel = level
                return (service, level)
            }
        }

        // Ultimate fallback - always returns mock
        let fallback = MockHTRService()
        cachedService = fallback
        cachedLevel = .mock
        return (fallback, .mock)
    }

    /// Force l'utilisation d'un niveau spécifique (pour tests/debug)
    func createService(forLevel level: HTRModelLevel) -> any HTRServiceProtocol {
        switch level {
        case .chandra:
            return ChandraMLXService.shared
        case .ollama:
            return OllamaHTRService()
        case .deepseekOCR, .cassVL:
            return MockHTRService() // Pas encore implémenté
        case .mock:
            return MockHTRService()
        }
    }

    func clearCache() {
        cachedService = nil
        cachedLevel = nil
    }

    /// Retourne les modèles compatibles avec la RAM disponible
    func compatibleModels() -> [HTRModelLevel] {
        HTRModelLevel.allCases.filter { level in
            level.estimatedRAM <= availableRAM || level == .mock
        }.sorted(by: >)
    }
}
