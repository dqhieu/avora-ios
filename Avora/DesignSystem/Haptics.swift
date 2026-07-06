import UIKit

enum Haptics {
    /// Light tap — navigation, generic buttons, card taps, retry.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// Medium — primary/committing actions (Generate, Buy, Subscribe, Login).
    static func impact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    /// Selection — toggles, pickers (quality, sort), tab switches, likes.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    /// Success — completed Save, Share, Generate, purchase, claim bonus.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    /// Warning — destructive confirmation prompts (Delete Account, Unshare).
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    /// Error — failed operations (generation/save/purchase failure).
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
