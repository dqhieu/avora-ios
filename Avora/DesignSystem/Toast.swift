import SwiftUI
import UIKit

// MARK: - Toast Window Manager

/// Presents a transient toast in its own passthrough window so it floats above
/// any sheet, tab, or navigation stack. Ported from the Steps app.
@MainActor
final class ToastWindowManager {
    static let shared = ToastWindowManager()

    private var window: UIWindow?
    private var hostingController: UIHostingController<ToastContainerView>?

    private init() {}

    func show(
        title: String,
        systemImage: String = "checkmark.circle.fill",
        tintColor: Color? = nil,
        duration: TimeInterval = 2.0
    ) {
        dismiss()

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let toastWindow = PassthroughWindow(windowScene: windowScene)
        toastWindow.windowLevel = .alert + 1
        toastWindow.backgroundColor = .clear

        let containerView = ToastContainerView(
            title: title,
            systemImage: systemImage,
            tintColor: tintColor ?? .avoraSuccess,
            duration: duration,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingController = UIHostingController(rootView: containerView)
        hostingController.view.backgroundColor = .clear

        toastWindow.rootViewController = hostingController
        toastWindow.isHidden = false

        self.window = toastWindow
        self.hostingController = hostingController

        Haptics.tap()
    }

    func dismiss() {
        window?.isHidden = true
        window = nil
        hostingController = nil
    }
}

// MARK: - Passthrough Window

private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        return hitView == rootViewController?.view ? nil : hitView
    }
}

// MARK: - Toast Container View

struct ToastContainerView: View {
    let title: String
    let systemImage: String
    let tintColor: Color
    let duration: TimeInterval
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        VStack {
            if isVisible {
                ToastView(title: title, systemImage: systemImage, tintColor: tintColor)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity))
                    )
            }
            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .task {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isVisible = false
                } completion: {
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let title: String
    let systemImage: String
    let tintColor: Color

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tintColor)

            Text(title)
                .font(.avoraSubheadline)
                .foregroundStyle(Color.avoraTextPrimary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .avoraGlass(in: .capsule)
    }
}

#if DEBUG
#Preview {
    struct PreviewWrapper: View {
        var body: some View {
            Button("Show Toast") {
                ToastWindowManager.shared.show(title: "Saved to Photos")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient.avoraBackgroundGradient)
        }
    }

    return PreviewWrapper()
}
#endif
