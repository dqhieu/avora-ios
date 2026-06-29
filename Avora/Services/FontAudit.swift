import UIKit

/// Verifies that every bundled custom font is registered and resolvable by its
/// PostScript name. A non-empty result means a font file is missing from the
/// bundle or its UIAppFonts registration, or its PostScript name is wrong.
enum FontAudit {
    static let requiredPostScriptNames = [
        "CormorantGaramond-SemiBold",
        "CormorantGaramond-Medium",
        "CormorantGaramond-MediumItalic",
        "BricolageGrotesque-Regular",
        "BricolageGrotesque-Medium",
        "BricolageGrotesque-SemiBold",
        "BricolageGrotesque-Bold",
    ]

    static func missingPostScriptNames() -> [String] {
        requiredPostScriptNames.filter { UIFont(name: $0, size: 12) == nil }
    }
}
