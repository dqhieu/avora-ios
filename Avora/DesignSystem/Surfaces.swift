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

/// Primary action button: clear Liquid Glass on iOS 26+, translucent material capsule on 18–25.
struct AvoraPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.avoraButton)
            .foregroundStyle(Color.avoraOnAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .opacity(configuration.isPressed ? 0.85 : 1)

        if #available(iOS 26.0, *) {
            return AnyView(label.glassEffect(.regular.interactive(), in: .capsule))
        } else {
            return AnyView(
                label
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().stroke(Color.avoraBorderHighlight, lineWidth: 1) }
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            )
        }
    }
}

struct AvoraCustomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.avoraButton)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .foregroundStyle(Color.avoraOnAccent)
            .opacity(configuration.isPressed ? 0.85 : 1)

        if #available(iOS 26.0, *) {
            return AnyView(label.glassEffect(.regular.interactive(), in: .capsule))
        } else {
            return AnyView(
                label
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().stroke(Color.avoraBorderHighlight, lineWidth: 1) }
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            )
        }
    }
}

struct AvoraPrimaryButton<Label: View>: View {
    private let action: () -> Void
    @ViewBuilder private let label: () -> Label

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(AvoraPrimaryButtonStyle())
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
