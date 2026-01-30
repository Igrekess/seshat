import Foundation

enum SeshatError: LocalizedError, Equatable {
    case modelNotFound(String)
    case transcriptionFailed(underlying: Error)
    case analysisTimeout
    case exportFailed(path: String)
    case invalidImageFormat
    case insufficientMemory(required: Int, available: Int)
    case lowConfidenceWarning(confidence: Double)
    case fileAccessDenied(path: String)
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Modèle '\(name)' introuvable"
        case .transcriptionFailed(let error):
            return "Échec de la transcription: \(error.localizedDescription)"
        case .analysisTimeout:
            return "L'analyse a pris trop de temps"
        case .exportFailed(let path):
            return "Échec de l'export vers: \(path)"
        case .invalidImageFormat:
            return "Format d'image non supporté"
        case .insufficientMemory(let required, let available):
            return "Mémoire insuffisante: \(required)MB requis, \(available)MB disponible"
        case .lowConfidenceWarning(let confidence):
            return "Confiance faible (\(Int(confidence * 100))%) - Vérification approfondie recommandée"
        case .fileAccessDenied(let path):
            return "Accès refusé au fichier: \(path)"
        case .configurationError(let message):
            return "Erreur de configuration: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotFound:
            return "Vérifiez que le modèle est installé dans ~/Library/Application Support/Seshat/Models/"
        case .transcriptionFailed:
            return "Essayez avec une image de meilleure qualité ou relancez la transcription"
        case .analysisTimeout:
            return "Essayez avec un texte plus court ou relancez l'analyse"
        case .exportFailed:
            return "Vérifiez les permissions du dossier de destination"
        case .invalidImageFormat:
            return "Formats supportés: JPEG, PNG, HEIC, PDF"
        case .insufficientMemory:
            return "Fermez d'autres applications pour libérer de la mémoire"
        case .lowConfidenceWarning:
            return "Vérifiez attentivement la transcription avant de valider"
        case .fileAccessDenied:
            return "Vérifiez les permissions du fichier"
        case .configurationError:
            return "Réinitialisez les préférences dans les paramètres"
        }
    }

    var isWarning: Bool {
        switch self {
        case .lowConfidenceWarning:
            return true
        default:
            return false
        }
    }

    static func == (lhs: SeshatError, rhs: SeshatError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
