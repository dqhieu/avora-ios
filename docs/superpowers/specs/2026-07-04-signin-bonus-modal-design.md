# Sign-In Bonus Modal — Design

**Date:** 2026-07-04
**Status:** Approved (design), pending implementation plan

## Summary

The first time a user signs in, present a celebratory centered-dialog overlay
that reveals the free sign-in bonus they received (60 credits, read dynamically
from `credit_config.signup_extra`). The bonus itself is already granted
server-side by an existing Supabase trigger — this feature only *presents* it.
The card uses the existing `CreditTicketCard` ticket aesthetic (a new
non-interactive variant). Shown exactly once per account, tracked by a backend
flag, so it survives reinstalls and new devices.

## Goals

- Reveal the sign-in bonus once, with a celebratory moment (confetti + haptic).
- Show the real granted amount, never a hardcoded number.
- Show it to every account — existing users included — exactly once.
- Guarantee "shown once" even if the app is killed before the user dismisses it.

## Non-goals

- Granting the credits (already handled by the `handle_new_user` DB trigger).
- Changing the bonus amount (already set to 60 in `credit_config.signup_extra`).
- Any change to the login screen itself.

## Decisions

| Question | Decision |
|----------|----------|
| How to trigger / show-once | Backend flag on the profile (source of truth) |
| Bonus amount source | `credit_config.signup_extra` via `CreditConfig.signupExtra` |
| Card | New standalone non-interactive `SignupBonusCard` (ticket style) |
| Presentation | Centered dialog overlay over a dimmed backdrop + confetti |
| Who sees it | Every account, once — existing rows backfilled to `false` |
| Title copy | "Welcome to Avora!" |

## Architecture

### Backend (Supabase migration)

New migration adds a flag to `public.profiles` **and** a `security definer`
function to flip it. The `profiles` table is owner-read-only with **no client
write policy** (all mutations go through `security definer` functions), so the
client cannot `UPDATE profiles` directly — it must call an RPC.

```sql
alter table public.profiles
  add column signup_bonus_seen boolean not null default false;

-- Adding a NOT NULL DEFAULT false column backfills every existing row to false,
-- so all current accounts see the reveal once on next sign-in. New accounts
-- created by the handle_new_user trigger also inherit false (no trigger change).

-- Lets the signed-in user mark their own bonus seen (profiles has no client
-- write policy, so this must be security definer, scoped to auth.uid()).
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

### Client model & API

- `Profile` (`Avora/Models/Profile.swift`): add `signupBonusSeen: Bool` with
  coding key `signup_bonus_seen`.
- `AvoraAPI.fetchProfile()` (`Avora/Services/AvoraAPI.swift`): add
  `signup_bonus_seen` to the `.select(...)` column list.
- `AvoraAPI.markSignupBonusSeen()` (new): calls the `mark_signup_bonus_seen`
  RPC (a direct `UPDATE` would be blocked by RLS).

```swift
func markSignupBonusSeen() async throws {
    try await db.rpc("mark_signup_bonus_seen").execute()
}
```

- `AppState` (`Avora/State/AppState.swift`): add
  `func markSignupBonusSeen() async` that calls the API and, on success, sets
  `profile?.signupBonusSeen = true` locally so the overlay dismisses reactively.

### Fresh-login config gap (must fix)

`LoginView.completeSignIn()` calls `refreshProfile()` but **not** `loadConfig()`,
so after a brand-new sign-in `AppState.config` is still `.fallback`
(`signupExtra == 50`). Add `await app.loadConfig()` **immediately after
`refreshProfile()`** (and before `isAuthenticated = true`) so the live backend
amount (60) is loaded before the overlay can render:

```swift
private func completeSignIn() async {
    await app.configureRevenueCat()
    await app.refreshProfile()
    await app.loadConfig()      // ← added: fresh config before the modal shows
    app.isAuthenticated = true
}
```

`bootstrap()` already loads config after `refreshProfile()` for existing
sessions, so the kill-before-claim relaunch path is covered.

### Components

- **`SignupBonusCard`** (new, `Avora/Views/Credits/SignupBonusCard.swift`):
  a non-interactive ticket card. Reuses the shared `NotchedRectangle` shape and
  `Color.avoraTicketYellow` / `Color.avoraTicketInk` from the design system to
  match `CreditTicketCard`, but shows the bonus amount + a "SIGN-IN BONUS" label
  instead of a price rail and buy button. Input: `credits: Int`.

- **`SignupBonusModal`** (new, `Avora/Views/Credits/SignupBonusModal.swift`):
  the centered dialog. Dimmed full-screen backdrop, a card containing the title
  "Welcome to Avora!", a short subtitle, the `SignupBonusCard`, and a single
  "Claim" button. Hosts `ConfettiView` and bumps its trigger on appear (same
  pattern as `CreditsView`). Backdrop tap does **not** dismiss — only "Claim"
  does — so the "mark seen" acknowledgement is guaranteed to run.

### Presentation & flow

The overlay is attached at the main-app level in `ContentView` on the
authenticated branch (so it renders over `RootTabView`, never over `LoginView`):

```swift
if app.isAuthenticated {
    RootTabView()
        .overlay {
            if app.profile?.signupBonusSeen == false, app.config.signupExtra > 0 {
                SignupBonusModal(credits: app.config.signupExtra) {
                    Task { await app.markSignupBonusSeen() }
                }
            }
        }
}
```

The `signupExtra > 0` guard prevents announcing a "0 credit" bonus if the config
is misconfigured or hasn't loaded yet. Because the condition is reactive, once
`loadConfig()` populates a positive amount the overlay appears; the flag is only
marked seen when the user taps "Claim", so a transient 0 never burns the reveal.

Flow:
1. User signs in → `completeSignIn()` refreshes profile + config, sets
   `isAuthenticated = true`.
2. `ContentView` shows `RootTabView`; the overlay condition
   `profile?.signupBonusSeen == false` is true → modal appears, confetti fires,
   success haptic plays.
3. User taps "Claim" → `AppState.markSignupBonusSeen()` writes the flag and sets
   `profile?.signupBonusSeen = true` → overlay condition flips false →
   modal dismisses.

## Edge cases

- **App killed before claiming:** flag still `false` server-side → `bootstrap()`
  refetches profile (and config) on next launch → modal shows again. Correct.
- **Config not yet loaded / misconfigured:** the `signupExtra > 0` guard means the
  modal never announces a 0-credit bonus. `AppState.config` is never nil (seeded
  with `.fallback`, `signupExtra == 50`), and `loadConfig()` in `completeSignIn()`
  / `bootstrap()` refreshes it to the live amount before the modal renders. If the
  live config ever reports `signup_extra == 0`, the modal simply does not show and
  the flag is not marked seen.
- **Ack API fails:** local dismissal still happens (optimistic), but the server
  flag stays `false`, so the modal re-shows on next launch — at-least-once
  display. Acceptable; no error UI needed.
- **`profile == nil`** (e.g. offline first frame): condition is `== false`, which
  is false when `profile` is nil, so the modal does not show until a profile is
  loaded. Correct.

## Success criteria

- New account → modal appears once, shows the amount from
  `credit_config.signup_extra`, confetti + haptic fire, "Claim" dismisses and
  persists the flag.
- Relaunch after claim → no modal.
- Existing (backfilled) account → sees it exactly once, then never again.
- Kill app before claiming → modal reappears on next launch.
- Backdrop tap does not dismiss the modal.
- `signup_extra == 0` (or config not yet loaded) → modal does not show and the
  flag is not marked seen.

## Files

**Create**
- `supabase/migrations/000029_signup_bonus_seen.sql` — column + `mark_signup_bonus_seen()` RPC
- `Avora/Views/Credits/SignupBonusCard.swift`
- `Avora/Views/Credits/SignupBonusModal.swift`

**Modify**
- `Avora/Models/Profile.swift` — add `signupBonusSeen`
- `Avora/Services/AvoraAPI.swift` — select column + `markSignupBonusSeen()`
- `Avora/State/AppState.swift` — `markSignupBonusSeen()`
- `Avora/LoginView.swift` — `await app.loadConfig()` in `completeSignIn()`
- `Avora/ContentView.swift` — overlay on the authenticated branch
