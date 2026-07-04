import SwiftUI
import UIKit

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue:  CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Resolves `light`/`dark` hex values against the active interface style.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    static let avoraBackground      = Color(light: 0xF4F4F7, dark: 0x0A0A0B)
    static let avoraSurface         = Color(light: 0xFFFFFF, dark: 0x161618)
    static let avoraSurfaceElevated = Color(light: 0xFFFFFF, dark: 0x212124)
    static let avoraTextPrimary     = Color(light: 0x0A0A0B, dark: 0xFAFAFA)
    static let avoraTextSecondary   = Color(light: 0x65656B, dark: 0x9A9AA0)
    static let avoraTextTertiary    = Color(light: 0x9A9AA0, dark: 0x5E5E64)
    static let avoraBorder          = Color(light: 0xE2E2E6, dark: 0x29292E)
    static let avoraBorderHighlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 0, alpha: 0.08)
    })
    static let avoraAccent          = Color(light: 0x0A0A0B, dark: 0xFAFAFA)
    static let avoraOnAccent        = Color(light: 0x0A0A0B, dark: 0xFAFAFA)
    static let avoraError           = Color(hex: 0xE5564B)
    static let avoraSuccess         = Color(hex: 0x4FB286)
    static let avoraTicketYellow    = Color(hex: 0xF2C12E)
    static let avoraTicketInk       = Color(hex: 0x141414)
}

extension LinearGradient {
    static let avoraBackgroundGradient = LinearGradient(
        colors: [Color(light: 0xFFFFFF, dark: 0x121215), Color(light: 0xF1F1F5, dark: 0x0B0B0D)],
        startPoint: .top, endPoint: .bottom
    )
    static let avoraSurfaceGradient = LinearGradient(
        colors: [Color(light: 0xFFFFFF, dark: 0x1C1C20), Color(light: 0xF3F3F7, dark: 0x151517)],
        startPoint: .top, endPoint: .bottom
    )
}
