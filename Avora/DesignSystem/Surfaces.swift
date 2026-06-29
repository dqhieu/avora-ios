import SwiftUI

extension View {
    /// Native Liquid Glass on iOS 26+, translucent material fallback on 18–25.
    @ViewBuilder
    func avoraGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        }
    }

    /// Solid graphite elevated surface: gradient fill + top highlight + soft shadow.
    func avoraElevatedSurface(cornerRadius: CGFloat = Radius.md) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(LinearGradient.avoraSurfaceGradient, in: shape)
            .overlay(shape.strokeBorder(Color.avoraBorderHighlight, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
}

/// Primary action button: Liquid Glass prominent on iOS 26+, white-fill capsule on 18–25.
struct AvoraPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.avoraButton)
            .foregroundStyle(Color.avoraOnAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .opacity(configuration.isPressed ? 0.85 : 1)

        if #available(iOS 26.0, *) {
            return AnyView(label.glassEffect(.regular.tint(Color.avoraAccent).interactive(), in: .capsule))
        } else {
            return AnyView(label.background(Color.avoraAccent, in: Capsule()))
        }
    }
}

#if DEBUG
#Preview("Surfaces") {
    VStack(spacing: Spacing.lg) {
        Text("Elevated surface")
            .foregroundStyle(Color.avoraTextPrimary)
            .frame(maxWidth: .infinity, minHeight: 80)
            .avoraElevatedSurface(cornerRadius: Radius.lg)
        Text("Glass")
            .foregroundStyle(Color.avoraTextPrimary)
            .padding(Spacing.lg)
            .avoraGlass(in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        Button("Generate") {}
            .buttonStyle(AvoraPrimaryButtonStyle())
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
