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

    @State private var confettiTrigger = 0
    @State private var purchasedCredits: Int?
    @State private var showConfirmation = false
    @State private var purchaseError: String?

    private let cols = [GridItem(.flexible(), spacing: Spacing.md),
                        GridItem(.flexible(), spacing: Spacing.md)]

    private var featuredPack: CreditPackOption? { packOptions.first { $0.display.isFeatured } }
    private var standardPacks: [CreditPackOption] { packOptions.filter { !$0.display.isFeatured } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    balanceHeader

                    WeeklyPlanCard(
                        priceString: weeklyPackage?.storeProduct.localizedPriceString,
                        isActive: app.profile?.subscriptionActive ?? false,
                        renewsOn: app.profile?.subscriptionPeriodEnd,
                        onSubscribe: { if let p = weeklyPackage { Task { await buy(p, credits: nil) } } }
                    )

                    if !packOptions.isEmpty {
                        sectionLabel
                        VStack(spacing: Spacing.lg) {
                            if let featuredPack {
                                CreditTicketCard(pack: featuredPack.display, prominent: true) {
                                    Task { await buy(featuredPack.package, credits: featuredPack.display.credits) }
                                }
                            }
                            LazyVGrid(columns: cols, spacing: Spacing.lg) {
                                ForEach(standardPacks) { opt in
                                    CreditTicketCard(pack: opt.display, prominent: false) {
                                        Task { await buy(opt.package, credits: opt.display.credits) }
                                    }
                                }
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
            .overlay { ConfettiView(trigger: confettiTrigger) }
            .alert("Thank you!", isPresented: $showConfirmation) {
                Button("Done", role: .cancel) { }
            } message: {
                if let purchasedCredits {
                    Text("\(purchasedCredits) credits have been added to your balance.")
                } else {
                    Text("Your subscription is now active.")
                }
            }
            .alert("Purchase failed",
                   isPresented: Binding(get: { purchaseError != nil },
                                        set: { if !$0 { purchaseError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }

    private var balanceHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "centsign")
                .font(.largeTitle)
            Text(app.profile?.totalCredits ?? 0, format: .number)
                .font(.avoraHeroSans)
        }
        .foregroundStyle(Color.avoraTextPrimary)
        .padding(.top, Spacing.sm)
    }

    private var sectionLabel: some View {
        Text("One-time packs")
            .font(.avoraCaption)
            .foregroundStyle(Color.avoraTextSecondary)
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

    private func buy(_ package: Package, credits: Int?) async {
        busy = true
        defer { busy = false }
        do {
            let before = app.profile?.totalCredits ?? 0
            let wasActive = app.profile?.subscriptionActive ?? false
            let cancelled = try await AvoraPurchases.purchase(package)
            guard !cancelled else { return }   // cancelled → show nothing

            // Celebrate immediately; the screen stays open.
            purchasedCredits = credits
            confettiTrigger += 1
            showConfirmation = true

            // Credits/subscription arrive via the RevenueCat webhook → backend;
            // poll the profile so the balance header reflects the purchase.
            for _ in 0..<10 {
                await app.refreshProfile()
                let now = app.profile
                if (now?.totalCredits ?? 0) > before
                    || (now?.subscriptionActive ?? false) && !wasActive { break }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}
