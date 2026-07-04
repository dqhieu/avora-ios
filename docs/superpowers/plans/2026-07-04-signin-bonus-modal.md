# Sign-In Bonus Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first time any account signs in, show a one-time celebratory centered-dialog modal that reveals the free sign-in bonus (amount read live from `credit_config.signup_extra`) using a ticket-styled card, tracked once-per-account by a backend flag.

**Architecture:** Add a `signup_bonus_seen` boolean to `public.profiles` plus a `security definer` RPC to flip it (the table has no client-write RLS policy). Surface the flag on the client `Profile` model, add `AvoraAPI`/`AppState` plumbing to mark it seen, build a non-interactive `SignupBonusCard` (reusing the shared `NotchedRectangle` ticket look) and a `SignupBonusModal` (dimmed backdrop + confetti + Claim button), and host the modal as an overlay in `ContentView` while `profile.signupBonusSeen == false && config.signupExtra > 0`.

**Tech Stack:** SwiftUI, Xcode 26, single `Avora` target. Supabase (Postgres + supabase-swift). Custom fonts via `Font.avora*` tokens.

## Global Constraints

- Title copy is exactly `Welcome to Avora!`.
- Bonus amount is **never hardcoded** — always `app.config.signupExtra` (from `credit_config.signup_extra`, already set to 60 on the remote).
- The modal shows only when `app.profile?.signupBonusSeen == false` **and** `app.config.signupExtra > 0`.
- Backdrop tap must **not** dismiss the modal; only the "Claim" button dismisses.
- `profiles` is owner-read-only with no client write policy — mutate `signup_bonus_seen` only through the `mark_signup_bonus_seen()` RPC, never a direct client `UPDATE`.
- Ticket colors: `avoraTicketYellow` (`#F2C12E`), `avoraTicketInk` (`#141414`), fixed across light/dark. Reuse the shared `NotchedRectangle` shape and existing `ConfettiView`.
- Follow existing design-system usage: `Spacing`, `Radius`, `Color.avora*`, `Font.avora*`, `AvoraPrimaryButton`.
- Migrations are **forward-only**, applied to the linked remote via `supabase db push` (do not edit prior migration files). Next number is `000029`.
- No XCTest target exists in this project. Swift tasks are verified by a compiling build plus a SwiftUI `#Preview` (and a simulator run for the final wiring). Do **not** add a test target or fabricate unit tests.
- iOS build/verify command (resolves SPM packages on first run, may take a few minutes):
  `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  (XcodeBuildMCP `build_sim` is an equivalent alternative.)

---

### Task 1: Migration — `signup_bonus_seen` column + RPC

**Files:**
- Create: `supabase/migrations/000029_signup_bonus_seen.sql`

**Interfaces:**
- Produces: column `public.profiles.signup_bonus_seen boolean not null default false`; function `public.mark_signup_bonus_seen()` (returns void, `security definer`, execute granted to `authenticated`). Consumed by Task 2 (select) and Task 3 (RPC call).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/000029_signup_bonus_seen.sql`:

```sql
-- Sign-in bonus reveal: track whether a user has seen their signup-bonus modal,
-- plus a security definer RPC for the client to mark it seen. profiles has no
-- client write policy (owner read-only; all writes go through definer funcs),
-- so the flag can only be flipped via this function.

alter table public.profiles
  add column signup_bonus_seen boolean not null default false;
-- Adding a NOT NULL DEFAULT false column backfills every existing row to false,
-- so all current accounts see the reveal once on next sign-in. New accounts
-- inserted by handle_new_user() inherit the default too (no trigger change).

create or replace function public.mark_signup_bonus_seen()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles set signup_bonus_seen = true where id = auth.uid();
end;
$$;

revoke all on function public.mark_signup_bonus_seen() from public, anon;
grant execute on function public.mark_signup_bonus_seen() to authenticated;
```

- [ ] **Step 2: Apply the migration locally and verify structure**

Run (requires local stack; `supabase start` once if not already running):

```bash
supabase db reset
```

Expected: all migrations reapply with no errors, including `000029`.

Verify the column and function exist:

```bash
DB_URL="$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '\"')"
psql "$DB_URL" -c "\d public.profiles" | grep signup_bonus_seen
psql "$DB_URL" -c "select proname, prosecdef from pg_proc where proname = 'mark_signup_bonus_seen';"
```

Expected: the `\d` output shows `signup_bonus_seen | boolean | not null default false`; the second query returns one row with `prosecdef = t` (security definer).

- [ ] **Step 3: Verify existing rows backfill to false**

```bash
psql "$DB_URL" -c "select count(*) filter (where signup_bonus_seen) as seen, count(*) as total from public.profiles;"
```

Expected: `seen = 0` (every existing profile row is `false`).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/000029_signup_bonus_seen.sql
git commit -m "feat: add signup_bonus_seen column and mark RPC"
```

> Deploy note: apply to the linked remote with `supabase db push` when shipping (forward-only). The remote `credit_config.signup_extra` is already set to 60.

---

### Task 2: Surface `signupBonusSeen` on the `Profile` model

**Files:**
- Modify: `Avora/Models/Profile.swift`
- Modify: `Avora/Services/AvoraAPI.swift:26-34` (the `fetchProfile()` `.select(...)`)

**Interfaces:**
- Consumes: column `profiles.signup_bonus_seen` (Task 1).
- Produces: `Profile.signupBonusSeen: Bool` (mutable `var`). Consumed by Task 3 (`AppState`) and Task 6 (overlay condition).

- [ ] **Step 1: Add the field to the model**

In `Avora/Models/Profile.swift`, add a mutable `signupBonusSeen` property and its coding key. The full file becomes:

```swift
import Foundation

struct Profile: Codable {
    let weeklyCredits: Int
    let extraCredits: Int
    let subscriptionActive: Bool
    let subscriptionPeriodEnd: Date?
    var signupBonusSeen: Bool
    var totalCredits: Int { weeklyCredits + extraCredits }

    enum CodingKeys: String, CodingKey {
        case weeklyCredits = "weekly_credits"
        case extraCredits = "extra_credits"
        case subscriptionActive = "subscription_active"
        case subscriptionPeriodEnd = "subscription_period_end"
        case signupBonusSeen = "signup_bonus_seen"
    }
}
```

(`signupBonusSeen` is a `var` so `AppState` can flip it locally after the RPC.)

- [ ] **Step 2: Add the column to the fetch query**

In `Avora/Services/AvoraAPI.swift`, update `fetchProfile()`'s `.select(...)` to include the new column:

```swift
    func fetchProfile() async throws -> Profile {
        let uid = try await currentUserId()
        return try await db.from("profiles")
            .select("weekly_credits,extra_credits,subscription_active,subscription_period_end,signup_bonus_seen")
            .eq("id", value: uid.uuidString)
            .single()
            .execute()
            .value
    }
```

(The column is required — `signupBonusSeen` is non-optional, so decoding fails if it's missing from the select.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Avora/Models/Profile.swift Avora/Services/AvoraAPI.swift
git commit -m "feat: fetch signup_bonus_seen into Profile"
```

---

### Task 3: Mark-seen plumbing (`AvoraAPI` + `AppState`)

**Files:**
- Modify: `Avora/Services/AvoraAPI.swift` (add method near `fetchProfile`)
- Modify: `Avora/State/AppState.swift` (add method near `refreshProfile`)

**Interfaces:**
- Consumes: RPC `mark_signup_bonus_seen` (Task 1); `Profile.signupBonusSeen` (Task 2).
- Produces: `AvoraAPI.markSignupBonusSeen() async throws`; `AppState.markSignupBonusSeen() async`. Consumed by Task 6 (Claim button).

- [ ] **Step 1: Add the API call**

In `Avora/Services/AvoraAPI.swift`, add this method directly after `fetchProfile()`:

```swift
    func markSignupBonusSeen() async throws {
        try await db.rpc("mark_signup_bonus_seen").execute()
    }
```

(Calls the `security definer` RPC — a direct `db.from("profiles").update(...)` would be blocked by RLS since `profiles` has no client write policy.)

- [ ] **Step 2: Add the AppState wrapper**

In `Avora/State/AppState.swift`, add this method directly after `refreshProfile()`:

```swift
    /// Marks the signup bonus seen and optimistically clears the flag locally so
    /// the modal dismisses immediately. If the RPC failed, the next profile fetch
    /// re-shows the modal (at-least-once display) rather than losing it silently.
    func markSignupBonusSeen() async {
        try? await AvoraAPI.shared.markSignupBonusSeen()
        profile?.signupBonusSeen = true
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Avora/Services/AvoraAPI.swift Avora/State/AppState.swift
git commit -m "feat: add markSignupBonusSeen plumbing"
```

---

### Task 4: `SignupBonusCard` view

**Files:**
- Create: `Avora/Views/Credits/SignupBonusCard.swift`

**Interfaces:**
- Consumes: shared `NotchedRectangle` (design system); `Color.avoraTicketYellow` / `Color.avoraTicketInk`; `Spacing`; `Font.avora*`.
- Produces: `struct SignupBonusCard: View` with initializer `SignupBonusCard(credits: Int)`. Consumed by `SignupBonusModal` (Task 5).

- [ ] **Step 1: Write the Preview first (the failing "test")**

Create `Avora/Views/Credits/SignupBonusCard.swift` with only the import and a Preview that exercises the not-yet-existing view, so the build fails first:

```swift
import SwiftUI

#if DEBUG
#Preview("Signup bonus card") {
    SignupBonusCard(credits: 60)
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient)
}
#endif
```

- [ ] **Step 2: Build to verify it fails**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD FAILED — "cannot find 'SignupBonusCard' in scope".

- [ ] **Step 3: Implement the card**

Insert above the `#if DEBUG` block in the same file:

```swift
/// Non-interactive admission-ticket card announcing the free sign-in bonus.
/// Mirrors `CreditTicketCard`'s notched-yellow ticket look with no price rail
/// or buy action.
struct SignupBonusCard: View {
    let credits: Int

    private let notch: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            stub("BONUS")
                .frame(width: 34)
            separator
            center
                .frame(maxWidth: .infinity)
            separator
            stub("AVORA")
                .frame(width: 34)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .foregroundStyle(Color.avoraTicketInk)
        .background(Color.avoraTicketYellow, in: NotchedRectangle(notchRadius: notch))
        .overlay(NotchedRectangle(notchRadius: notch).strokeBorder(Color.avoraTicketInk, lineWidth: 2))
        .overlay(
            NotchedRectangle(notchRadius: notch - 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .foregroundStyle(Color.avoraTicketInk.opacity(0.55))
                .padding(6)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sign-in bonus, \(credits) credits")
    }

    private var center: some View {
        VStack(spacing: Spacing.xs) {
            Text("✦  SIGN-IN BONUS  ✦").font(.avoraCaption2).tracking(3)
            rule
            Text(credits, format: .number).font(.avoraLargeTitle.monospacedDigit())
            rule
            Text("FREE CREDITS").font(.avoraCaption2).tracking(2)
        }
        .padding(.horizontal, Spacing.sm)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.avoraTicketInk.opacity(0.35))
            .frame(width: 160, height: 1)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.avoraTicketInk.opacity(0.45))
            .frame(width: 1)
            .padding(.vertical, Spacing.lg)
    }

    private func stub(_ text: String) -> some View {
        Text(text)
            .font(.avoraCaption2)
            .tracking(2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Build to verify it passes**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Inspect the Preview**

In Xcode, open the "Signup bonus card" Preview. Confirm: a yellow ticket with concave notched corners, a solid double border plus a dashed inner border, vertical "BONUS" / "AVORA" side stubs, and centered `✦ SIGN-IN BONUS ✦` / `60` / `FREE CREDITS` with hairline rules above and below the number. Check both light and dark appearance (the ticket stays yellow/black in both).

- [ ] **Step 6: Commit**

```bash
git add Avora/Views/Credits/SignupBonusCard.swift
git commit -m "feat: add SignupBonusCard ticket view"
```

---

### Task 5: `SignupBonusModal` view

**Files:**
- Create: `Avora/Views/Credits/SignupBonusModal.swift`

**Interfaces:**
- Consumes: `SignupBonusCard(credits:)` (Task 4); existing `ConfettiView(trigger:)`; `AvoraPrimaryButton(action:label:)`; `Color.avoraSurface` / `Color.avoraTextSecondary`; `Spacing`, `Radius`, `Font.avora*`.
- Produces: `struct SignupBonusModal: View` with initializer `SignupBonusModal(credits: Int, onClaim: @escaping () -> Void)`. Consumed by `ContentView` (Task 6).

- [ ] **Step 1: Write the Preview first (the failing "test")**

Create `Avora/Views/Credits/SignupBonusModal.swift` with only the import and a Preview that exercises the not-yet-existing view, so the build fails first:

```swift
import SwiftUI

#if DEBUG
#Preview("Signup bonus modal") {
    ZStack {
        LinearGradient.avoraBackgroundGradient.ignoresSafeArea()
        SignupBonusModal(credits: 60) {}
    }
}
#endif
```

- [ ] **Step 2: Build to verify it fails**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD FAILED — "cannot find 'SignupBonusModal' in scope".

- [ ] **Step 3: Implement the modal**

Insert above the `#if DEBUG` block in the same file:

```swift
/// One-time celebratory reveal of the sign-in bonus. A centered dialog over a
/// dimmed backdrop; only the "Claim" button dismisses (so the caller's
/// acknowledgement always runs — backdrop taps are ignored). Fires a confetti
/// burst + success haptic on appear (haptic is played inside ConfettiView).
struct SignupBonusModal: View {
    let credits: Int
    let onClaim: () -> Void

    @State private var confettiTrigger = 0

    var body: some View {
        ZStack {
            // Dimmed backdrop. contentShape + a no-op-free gesture is avoided on
            // purpose: the backdrop swallows taps but never dismisses.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                VStack(spacing: Spacing.xs) {
                    Text("Welcome to Avora!")
                        .font(.avoraTitle)
                        .foregroundStyle(Color.avoraTextPrimary)
                    Text("Here's a little something to get you started.")
                        .font(.avoraSubheadline)
                        .foregroundStyle(Color.avoraTextSecondary)
                        .multilineTextAlignment(.center)
                }

                SignupBonusCard(credits: credits)

                AvoraPrimaryButton(action: onClaim) {
                    Text("Claim")
                }
            }
            .padding(Spacing.xl)
            .background(Color.avoraSurface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .padding(.horizontal, Spacing.xl)

            ConfettiView(trigger: confettiTrigger)
                .allowsHitTesting(false)
        }
        .onAppear { confettiTrigger += 1 }
    }
}
```

(`ConfettiView` fires on a *change* to `trigger`; bumping `0 → 1` in `onAppear` triggers the burst, matching the `CreditsView` pattern.)

- [ ] **Step 4: Build to verify it passes**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Inspect the Preview**

In Xcode, open the "Signup bonus modal" Preview (use the interactive/live preview so `onAppear` runs). Confirm: a dimmed backdrop; a centered surface card containing the "Welcome to Avora!" title, the subtitle, the yellow `SignupBonusCard` showing `60`, and a full-width "Claim" button; a confetti burst plays once when the preview appears. Tapping outside the card does nothing; tapping "Claim" invokes the closure (no-op in the preview).

- [ ] **Step 6: Commit**

```bash
git add Avora/Views/Credits/SignupBonusModal.swift
git commit -m "feat: add SignupBonusModal celebratory dialog"
```

---

### Task 6: Wire the overlay + fresh config on login

**Files:**
- Modify: `Avora/ContentView.swift`
- Modify: `Avora/LoginView.swift:140-144` (`completeSignIn()`)

**Interfaces:**
- Consumes: `SignupBonusModal(credits:onClaim:)` (Task 5); `AppState.markSignupBonusSeen()` (Task 3); `AppState.loadConfig()` (existing); `AppState.profile`, `AppState.config` (existing/Task 2).

- [ ] **Step 1: Load fresh config on fresh sign-in**

In `Avora/LoginView.swift`, update `completeSignIn()` to load the live credit config right after refreshing the profile (so `config.signupExtra` is the backend value, not the `.fallback` 50, before the overlay can render):

```swift
    private func completeSignIn() async {
        await app.configureRevenueCat()
        await app.refreshProfile()
        await app.loadConfig()
        app.isAuthenticated = true
    }
```

- [ ] **Step 2: Host the modal overlay in ContentView**

Replace the entire contents of `Avora/ContentView.swift` with:

```swift
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app

    private var showSignupBonus: Bool {
        app.profile?.signupBonusSeen == false && app.config.signupExtra > 0
    }

    var body: some View {
        Group {
            if app.isAuthenticated {
                RootTabView()
                    .overlay {
                        if showSignupBonus {
                            SignupBonusModal(credits: app.config.signupExtra) {
                                Task { await app.markSignupBonusSeen() }
                            }
                            .transition(.opacity)
                        }
                    }
            } else {
                LoginView()
            }
        }
        .font(.avoraBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: showSignupBonus)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
```

(The condition is reactive: `signupExtra` starts at the `.fallback` 50 but is refreshed by `loadConfig()`; the flag is only cleared on "Claim", so a transient value never burns the reveal. The `> 0` guard prevents ever announcing a 0-credit bonus.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run in the simulator and verify the flow**

Run the Avora scheme on an iOS simulator (Xcode Run, or XcodeBuildMCP `build_run_sim`).

To exercise the reveal for a signed-in test user, reset the flag in the DB (SQL editor on the remote, or local `psql`), then relaunch the app:

```sql
update public.profiles set signup_bonus_seen = false where id = '<your-test-user-uuid>';
```

Confirm:
1. On launch (already authenticated), the modal appears over the tab bar with "Welcome to Avora!", the ticket showing the real `signup_extra` amount (60), confetti + haptic.
2. Tapping outside the card does **not** dismiss it.
3. Tapping "Claim" dismisses the modal (fade out).
4. Force-quit and relaunch → **no** modal (flag persisted server-side).
5. (Optional) Re-run the `update ... = false` SQL and relaunch → modal shows again, confirming it's driven by the backend flag.

- [ ] **Step 5: Commit**

```bash
git add Avora/ContentView.swift Avora/LoginView.swift
git commit -m "feat: present sign-in bonus modal on first login"
```

---

## Self-Review

**Spec coverage:**
- Backend flag `signup_bonus_seen` + backfill existing rows to false → Task 1 (NOT NULL DEFAULT false backfills). ✓
- No-client-write RLS → `mark_signup_bonus_seen()` security definer RPC → Task 1; called via `db.rpc` in Task 3. ✓
- Amount from `credit_config.signup_extra` via `CreditConfig.signupExtra`, never hardcoded → Task 6 passes `app.config.signupExtra`. ✓
- Fresh-login config gap (loadConfig after refreshProfile, before isAuthenticated) → Task 6 Step 1. ✓
- `Profile.signupBonusSeen` + fetch column → Task 2. ✓
- `AvoraAPI.markSignupBonusSeen()` + `AppState.markSignupBonusSeen()` (optimistic local clear) → Task 3. ✓
- Standalone non-interactive `SignupBonusCard` reusing ticket look → Task 4. ✓
- Centered dialog overlay + confetti + haptic, "Welcome to Avora!" title, Claim-only dismiss (backdrop inert) → Task 5. ✓
- Overlay at main-app level, condition `signupBonusSeen == false && signupExtra > 0` → Task 6. ✓
- Edge cases: kill-before-claim re-shows (backend flag, Task 6 Step 4.4), signupExtra==0 hidden (Task 6 guard), config-not-loaded (loadConfig + fallback never nil), profile==nil → `== false` is false so hidden. ✓
- Success criteria mapped to Task 6 Step 4 manual checks. ✓

**Type consistency:** `SignupBonusCard(credits: Int)` defined in Task 4, called identically in Task 5 and (indirectly) Task 6. `SignupBonusModal(credits: Int, onClaim: () -> Void)` defined in Task 5, called identically in Task 6. `AppState.markSignupBonusSeen() async` (Task 3) matches the `Task { await ... }` call in Task 6. `Profile.signupBonusSeen` is a `var Bool` (Task 2), mutated in Task 3. `db.rpc("mark_signup_bonus_seen")` name matches the function created in Task 1. Design-system tokens (`avoraTicketYellow`, `avoraTicketInk`, `avoraSurface`, `avoraTextSecondary`, `avoraTextPrimary`, `Spacing.*`, `Radius.lg`, `Font.avoraTitle/.avoraSubheadline/.avoraLargeTitle/.avoraCaption2`, `AvoraPrimaryButton`, `NotchedRectangle`, `ConfettiView`) all verified against the current codebase.

**Placeholder scan:** No TBD/TODO; all code shown in full. Verification adapted to the no-test-target reality (build + Preview + simulator) per Global Constraints — honest, not fabricated.
