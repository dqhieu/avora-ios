import SwiftUI
import RevenueCat

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    @State private var offering: Offering?
    @State private var packOptions: [CreditPackOption] = []
    @State private var weeklyPackage: Package?
    @State private var busy = false
    @State private var loadFailed = false

    private let cols = [GridItem(.flexible(), spacing: Spacing.sm),
                        GridItem(.flexible(), spacing: Spacing.sm)]

    private var featured: CreditPackOption? { packOptions.first { $0.display.isFeatured } }
    private var gridPacks: [CreditPackOption] { packOptions.filter { !$0.display.isFeatured } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    balanceHeader

                    WeeklyPlanCard(
                        priceString: weeklyPackage?.storeProduct.localizedPriceString,
                        isActive: app.profile?.subscriptionActive ?? false,
                        renewsOn: app.profile?.subscriptionPeriodEnd,
                        onSubscribe: { if let p = weeklyPackage { Task { await buy(p) } } }
                    )

                    if let featured {
                        sectionLabel
                        FeaturedPackCard(pack: featured.display) { Task { await buy(featured.package) } }
                        LazyVGrid(columns: cols, spacing: Spacing.sm) {
                            ForEach(gridPacks) { opt in
                                PackGridCell(pack: opt.display) { Task { await buy(opt.package) } }
                            }
                        }
                    } else if loadFailed {
                        retry
                    }
                }
                .padding(Spacing.lg)
                .disabled(busy)
            }
            .background(LinearGradient.avoraBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(busy)
                }
            }
            .task { await load() }
        }
    }

    private var balanceHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "centsign")
            Text(app.profile?.totalCredits ?? 0, format: .number)
        }
        .font(.avoraLargeTitleSans)
        .foregroundStyle(Color.avoraTextPrimary)
        .padding(.top, Spacing.sm)
    }

    private var sectionLabel: some View {
        Text("One-time packs")
            .font(.avoraCaption)
            .foregroundStyle(Color.avoraTextTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var retry: some View {
        ContentUnavailableView {
            Label("Couldn’t load packs", systemImage: "exclamationmark.triangle")
        } actions: {
            Button("Retry") { Task { await load() } }
        }
    }

    private func load() async {
        loadFailed = false
        async let offeringTask = AvoraPurchases.currentOffering()
        async let packsTask = AvoraAPI.shared.fetchCreditPacks()
        let off = try? await offeringTask
        let packs = (try? await packsTask) ?? []
        guard let off else { loadFailed = true; return }
        offering = off
        weeklyPackage = CreditsCatalog.weeklyPackage(offering: off)
        packOptions = CreditsCatalog.packOptions(packs: packs, offering: off)
        if packOptions.isEmpty { loadFailed = true }
    }

    private func buy(_ package: Package) async {
        busy = true
        defer { busy = false }
        do {
            let before = app.profile?.totalCredits ?? 0
            let wasActive = app.profile?.subscriptionActive ?? false
            try await AvoraPurchases.purchase(package)
            // Credits/subscription arrive via the RevenueCat webhook → backend;
            // poll the profile until it reflects the purchase.
            for _ in 0..<10 {
                await app.refreshProfile()
                let now = app.profile
                if (now?.totalCredits ?? 0) > before
                    || (now?.subscriptionActive ?? false) && !wasActive { break }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            dismiss()
        } catch {
            // User cancelled or purchase failed; stay on the screen.
        }
    }
}
