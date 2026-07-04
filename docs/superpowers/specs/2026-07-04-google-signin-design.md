# Design: Sign in with Google

**Date:** 2026-07-04
**Status:** Approved — ready for implementation planning

## Overview

Add "Continue with Google" as a second sign-in option on `LoginView`, alongside the
existing Sign in with Apple button. It uses the native GoogleSignIn SDK to obtain a
Google **ID token**, then exchanges that token with Supabase via `signInWithIdToken` —
the same server-verified OpenID Connect flow already used for Apple.

No backend logic changes are required: the existing `on_auth_user_created` trigger
auto-provisions the `profiles` row + starter credits for any new auth user, and
sign-out / bootstrap / RevenueCat configuration are already provider-agnostic
(session-based).

### Chosen approach

Native GoogleSignIn SDK (get ID token → hand to Supabase), rather than the web-based
`signInWithOAuth` / `ASWebAuthenticationSession` flow. Rationale:

- Native account sheet — no browser redirect, no extra "Sign in to avora?" system prompt.
- Structurally identical to the existing Apple flow (`OpenIDConnectCredentials` + nonce),
  so `AuthService` stays consistent and `AppState` is untouched.
- ID token is verified server-side by Supabase.

Cost: one well-maintained SPM dependency and a reversed-client-ID URL scheme in Info.plist.

## Backend setup (one-time, manual — outside the app)

1. **Google Cloud Console**
   - Create a project and configure the OAuth consent screen.
   - Create an **iOS** OAuth client ID (tied to the app bundle ID) → yields the *iOS client ID*
     and its *reversed client ID* (used as the URL scheme).
   - Create a **Web application** OAuth client ID → yields *web client ID* + *secret*
     (required to enable the Supabase Google provider).
2. **Supabase Dashboard → Authentication → Providers → Google**
   - Enable the provider; paste the **web** client ID + secret.
   - Add the **iOS** client ID to *Authorized Client IDs* so Supabase accepts native ID
     tokens (their `aud` claim is the iOS client ID).
3. *(Optional)* Mirror in `supabase/config.toml` under `[auth.external.google]` for
   local-dev parity.

**Secret handling:** the web secret lives only in Supabase. The app carries only the iOS
client ID, which is not a shippable secret. No secret enters the binary.

## App configuration

- **SPM:** add `https://github.com/google/GoogleSignIn-iOS`, product **`GoogleSignIn`**.
- **Info.plist:**
  - `GIDClientID` = iOS client ID (lets the SDK self-configure).
  - Register the *reversed client ID* under `CFBundleURLTypes` for the OAuth callback.
- **`AvoraApp.swift`:** add `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }` to the
  `ContentView` inside `WindowGroup` so the SDK can complete its callback.

## Code changes

### `Avora/Services/AuthService.swift`

Add `signInWithGoogle(presenting: UIViewController)`:

- Reuse the existing private `randomNonce()` / `sha256()` helpers (same nonce discipline
  as Apple — hashed nonce to Google, raw nonce to Supabase).
- Call `GIDSignIn.sharedInstance.signIn(withPresenting:nonce:)`, passing `sha256(nonce)`
  as the nonce.
- Read the ID token from `result.user.idToken?.tokenString`; throw `AvoraError.unauthorized`
  if absent.
- Exchange it:
  `signInWithIdToken(OpenIDConnectCredentials(provider: .google, idToken: idToken, nonce: nonce))`.

### `Avora/LoginView.swift`

- Add a second `AvoraPrimaryButton` labeled "Continue with Google" below the Apple button
  (two identical glass capsules — consistent with the design system; no new button style).
- Extract the shared post-auth steps (`configureRevenueCat` → `refreshProfile` →
  `isAuthenticated = true`) into one private helper reused by both buttons.
- Google needs the key window's `rootViewController` as its presenter (Apple uses the
  `ASPresentationAnchor` window directly).

### `Avora/State/AppState.swift`

**No changes.** `signOut()`, `bootstrap()`, and `configureRevenueCat()` are all
session-based and already work for any provider.

## Error handling & security

- User cancellation or auth failure is caught and leaves the user on the login screen
  (matches the existing Apple `catch`).
- The nonce prevents ID-token replay; Supabase verifies the token server-side against the
  authorized client IDs.
- No secret ships in the binary.

## Verification

- Project compiles.
- Manual: tap "Continue with Google" → native Google sheet → returns authenticated;
  profile + starter credits provisioned; RevenueCat identified with the Supabase user UUID.
- Sign out clears the session; signing back in with Google works.
- The Apple flow still works unchanged.

## Out of scope

- Email/password and other OAuth providers.
- Account-linking UI. A Google login on an email already used by Apple is governed by
  Supabase's own identity-linking rules; we build no custom linking flow.
