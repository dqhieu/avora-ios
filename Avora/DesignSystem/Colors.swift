import SwiftUI

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

    static let avoraBackground      = Color(hex: 0x0A0A0B)
    static let avoraSurface         = Color(hex: 0x161618)
    static let avoraSurfaceElevated = Color(hex: 0x212124)
    static let avoraTextPrimary     = Color(hex: 0xFAFAFA)
    static let avoraTextSecondary   = Color(hex: 0x9A9AA0)
    static let avoraTextTertiary    = Color(hex: 0x5E5E64)
    static let avoraBorder          = Color(hex: 0x29292E)
    static let avoraBorderHighlight = Color(white: 1.0, opacity: 0.06)
    static let avoraAccent          = Color(hex: 0xFAFAFA)
    static let avoraOnAccent        = Color(hex: 0x0A0A0B)
    static let avoraError           = Color(hex: 0xE5564B)
    static let avoraSuccess         = Color(hex: 0x4FB286)
}

extension LinearGradient {
    static let avoraBackgroundGradient = LinearGradient(
        colors: [Color(hex: 0x121215), Color(hex: 0x0B0B0D)],
        startPoint: .top, endPoint: .bottom
    )
    static let avoraSurfaceGradient = LinearGradient(
        colors: [Color(hex: 0x1C1C20), Color(hex: 0x151517)],
        startPoint: .top, endPoint: .bottom
    )
}
