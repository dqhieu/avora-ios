import Foundation

/// User-selectable generation quality. Owns the mapping from the UI-facing label
/// to the backend `quality` value sent to the image API. Cost is not encoded here
/// — it is read from `CreditConfig` keyed by `backend`.
enum GenerationQuality: String, CaseIterable, Identifiable {
    case `default`, high, ultra

    var id: String { rawValue }

    /// Value sent to the backend (maps to the OpenAI images `quality` field).
    var backend: String {
        switch self {
        case .default: "low"
        case .high:    "medium"
        case .ultra:   "high"
        }
    }

    /// User-facing label shown in the picker.
    var label: String {
        switch self {
        case .default: "Default"
        case .high:    "High"
        case .ultra:   "Ultra"
        }
    }
}
