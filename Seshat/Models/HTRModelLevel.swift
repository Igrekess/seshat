import Foundation

/// Hiérarchie des modèles HTR pour Seshat
/// Basée sur les benchmarks olmOCR-bench (Janvier 2026)
///
/// Scores manuscrit:
/// - Chandra: 83.1 (meilleur)
/// - olmOCR-2: 82.4 (alternative Apache 2.0)
/// - DeepSeek-OCR-2: 75.4 (léger, 3B)
/// - GutenOCR: ~75 (ancien choix, remplacé)
enum HTRModelLevel: Int, Codable, CaseIterable, Comparable {
    /// Niveau 1: Chandra (Datalab) - 9B params
    /// Score: 83.1 | RAM: ~6GB (4-bit) | Mac 16GB+
    /// Licence: OK pour usage éducatif non-commercial
    case chandra = 4

    /// Niveau 2: DeepSeek-OCR-2 - 3B params
    /// Score: 75.4 | RAM: ~2.5GB | Mac 8GB OK
    /// Licence: Apache 2.0
    case deepseekOCR = 3

    /// Niveau 3: Ollama (vision model local)
    /// Fallback si modèles MLX indisponibles
    case ollama = 2

    /// Futur: CASS-VL fine-tuné sur copies réelles
    case cassVL = 1

    /// Fallback ultime: Mock/développement
    case mock = 0

    static func < (lhs: HTRModelLevel, rhs: HTRModelLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .chandra: return "Chandra MLX"
        case .deepseekOCR: return "DeepSeek-OCR-2 MLX"
        case .ollama: return "Ollama"
        case .cassVL: return "CASS-VL"
        case .mock: return "Mock (Dev)"
        }
    }

    var description: String {
        switch self {
        case .chandra:
            return "Modèle HTR #1 manuscrit (83.1) - 9B params - Mac 16GB+"
        case .deepseekOCR:
            return "Modèle HTR léger (75.4) - 3B params - Mac 8GB"
        case .ollama:
            return "Modèle de fallback via Ollama local"
        case .cassVL:
            return "Modèle CASS-VL fine-tuné pour copies françaises (futur)"
        case .mock:
            return "Modèle mock pour développement"
        }
    }

    /// RAM requise en GB (estimation 4-bit quantization)
    var estimatedRAM: Double {
        switch self {
        case .chandra: return 6.0
        case .deepseekOCR: return 2.5
        case .ollama: return 4.0
        case .cassVL: return 4.0
        case .mock: return 0.0
        }
    }

    /// Score benchmark olmOCR-bench (manuscrit)
    var benchmarkScore: Double? {
        switch self {
        case .chandra: return 83.1
        case .deepseekOCR: return 75.4
        case .ollama: return nil
        case .cassVL: return nil
        case .mock: return nil
        }
    }

    var isAvailable: Bool {
        // In production, this would check if the model files exist
        switch self {
        case .chandra: return false // Requires MLX conversion
        case .deepseekOCR: return false // Requires MLX conversion
        case .ollama: return false // Requires local Ollama server
        case .cassVL: return false // Future development
        case .mock: return true // Always available
        }
    }
}
