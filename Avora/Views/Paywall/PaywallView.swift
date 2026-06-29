import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var offering: Offering?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section("Get more credits") {
                    ForEach(offering?.availablePackages ?? [], id: \.identifier) { pkg in
                        Button {
                            Task { await buy(pkg) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(pkg.storeProduct.localizedTitle)
                                    Text(pkg.storeProduct.localizedDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(pkg.storeProduct.localizedPriceString).bold()
                            }
                        }
                        .disabled(busy)
                    }
                }
            }
            .navigationTitle("Credits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(busy)
                }
            }
            .task {
                offering = try? await AvoraPurchases.currentOffering()
            }
        }
    }

    private func buy(_ pkg: Package) async {
        busy = true
        defer { busy = false }
        do {
            try await AvoraPurchases.purchase(pkg)
            // Credits arrive via RevenueCat webhook → backend; poll until profile updates
            let before = app.profile?.totalCredits ?? 0
            for _ in 0..<10 {
                await app.refreshProfile()
                if (app.profile?.totalCredits ?? 0) > before { break }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            dismiss()
        } catch {
            // User cancelled or purchase failed; stay on paywall
        }
    }
}
