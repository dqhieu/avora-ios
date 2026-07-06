import SwiftUI

/// Renders a full-color 3D "thiings" raster icon at a fixed square size.
/// `active` drives the shared dim-when-inactive treatment used by the like,
/// save, and share controls.
struct ThiingIcon: View {
    let name: String
    var size: CGFloat
    var active: Bool = true

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(active ? 1 : 0.4)
    }
}

#if DEBUG
#Preview("ThiingIcon") {
    HStack(spacing: Spacing.lg) {
        ThiingIcon(name: "ActionLike", size: 32)
        ThiingIcon(name: "ActionLike", size: 32, active: false)
        ThiingIcon(name: "ActionSave", size: 32)
        ThiingIcon(name: "ActionShare", size: 32)
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
