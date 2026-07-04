# Sign in with Google — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Continue with Google" sign-in option to the Avora iOS app that authenticates through the existing Supabase backend, alongside the current Sign in with Apple.

**Architecture:** Use the native GoogleSignIn SDK to obtain a Google ID token, then exchange it with Supabase via `signInWithIdToken(OpenIDConnectCredentials(provider: .google, …))` — the same server-verified OIDC flow already used for Apple. `AppState` is untouched; the existing `on_auth_user_created` DB trigger auto-provisions the profile + starter credits for the new user.

**Tech Stack:** Swift / SwiftUI, Xcode (project `Avora.xcodeproj`, scheme `Avora`), Supabase Swift SDK 2.48.0, GoogleSignIn-iOS SDK, RevenueCat.

**Spec:** `docs/superpowers/specs/2026-07-04-google-signin-design.md`

## Global Constraints

- Bundle identifier: `com.hieudinh.Avora` (both Debug and Release configs).
- Project generates its Info.plist (`GENERATE_INFOPLIST_FILE = YES`); there is no physical Info.plist yet.
- Reuse the existing private `randomNonce()` / `sha256()` helpers in `AuthService` — do not duplicate nonce logic.
- Reuse the existing `AvoraPrimaryButton` component for the Google button — do not introduce a new button style.
- Do NOT modify `Avora/State/AppState.swift` — sign-out, bootstrap, and RevenueCat config are already provider-agnostic.
- No secret ships in the app binary. Only the iOS OAuth client ID (not sensitive) enters the app.
- Build/compile check command (used throughout):
  `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  (Equivalent: XcodeBuildMCP `build_sim` with scheme `Avora`.)

## File Structure

- `Avora/Info.plist` — **create.** Partial plist holding only `GIDClientID` + `CFBundleURLTypes` (reversed client ID URL scheme); Xcode merges generated keys on top of it.
- `Avora.xcodeproj/project.pbxproj` — **modify.** Add the GoogleSignIn SPM package + product dependency; set `INFOPLIST_FILE` for both build configs.
- `Avora/Services/AuthService.swift` — **modify.** Add `signInWithGoogle(presenting:)`.
- `Avora/LoginView.swift` — **modify.** Add the Google button; extract a shared post-auth helper.
- `Avora/AvoraApp.swift` — **modify.** Route the OAuth callback URL into the GoogleSignIn SDK.

## A Note on Testing

The core deliverable is a live OAuth handshake between the GoogleSignIn SDK, Google's servers, and Supabase. There is no meaningful pure-unit-test seam for it without mocking three external systems (not worth it — YAGNI). Therefore each code task is verified by a **clean compile** (the build command above), and the end-to-end behavior is verified once, manually, in the final task. Where the spec's behavior can only be confirmed by running the app, the task says so explicitly rather than faking a test.

---

### Task 1: Backend setup (Google Cloud + Supabase) — manual, no code

**Files:** none (external consoles). This task produces two values that Task 3 needs:
- `IOS_CLIENT_ID` — e.g. `1234567890-abcdef.apps.googleusercontent.com`
- `REVERSED_CLIENT_ID` — the iOS client ID with segments reversed, e.g. `com.googleusercontent.apps.1234567890-abcdef`

**Interfaces:**
- Produces: `IOS_CLIENT_ID`, `REVERSED_CLIENT_ID` (record these — Task 3 hardcodes them into `Info.plist`).

- [ ] **Step 1: Create the Google Cloud project + consent screen**
  In the [Google Cloud Console](https://console.cloud.google.com/): create a project, then configure the OAuth consent screen (External, app name "Avora", support email). Add yourself as a test user.

- [ ] **Step 2: Create the iOS OAuth client ID**
  APIs & Services → Credentials → Create Credentials → OAuth client ID → Application type **iOS** → Bundle ID `com.hieudinh.Avora`.
  Record the **Client ID** as `IOS_CLIENT_ID`. Google also shows the **iOS URL scheme** — record it as `REVERSED_CLIENT_ID` (it is the client ID reversed, prefixed `com.googleusercontent.apps.`).

- [ ] **Step 3: Create the Web application OAuth client ID**
  Create Credentials → OAuth client ID → Application type **Web application** → name "Avora Supabase".
  Record the **Client ID** and **Client secret** (`WEB_CLIENT_ID`, `WEB_CLIENT_SECRET`).

- [ ] **Step 4: Enable Google in Supabase**
  Supabase Dashboard → Authentication → Providers → Google → Enable.
  - Paste `WEB_CLIENT_ID` and `WEB_CLIENT_SECRET`.
  - In **Authorized Client IDs**, add `IOS_CLIENT_ID` (comma-separated if others exist). This lets Supabase accept native ID tokens whose `aud` is the iOS client ID.
  - Save.

- [ ] **Step 5: Record values for later tasks**
  Confirm you have `IOS_CLIENT_ID` and `REVERSED_CLIENT_ID` written down. No commit (nothing changed in the repo).

---

### Task 2: Add the GoogleSignIn SPM dependency

**Files:**
- Modify: `Avora.xcodeproj/project.pbxproj` (Xcode manages this + `Package.resolved` when you add the package via the UI)

**Interfaces:**
- Produces: the `GoogleSignIn` module, importable as `import GoogleSignIn`.

- [ ] **Step 1: Add the package in Xcode**
  Open `Avora.xcodeproj`. File → Add Package Dependencies… → enter `https://github.com/google/GoogleSignIn-iOS` → Dependency Rule "Up to Next Major Version" → Add Package → check the **`GoogleSignIn`** product (not `GoogleSignInSwift`) and add it to the **Avora** target → Add Package.

- [ ] **Step 2: Add a temporary import to prove the module resolves**
  In `Avora/Services/AuthService.swift`, add `import GoogleSignIn` under the existing `import Supabase` line.

- [ ] **Step 3: Build to verify the dependency resolves and compiles**
  Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED** (package fetched and linked).

- [ ] **Step 4: Commit**
  ```bash
  git add Avora.xcodeproj Avora/Services/AuthService.swift
  git commit -m "chore: add GoogleSignIn SPM dependency"
  ```
  (`Package.resolved` under `Avora.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` is included by the `Avora.xcodeproj` add.)

---

### Task 3: Add Info.plist with GIDClientID + reversed-client-ID URL scheme

**Files:**
- Create: `Avora/Info.plist`
- Modify: `Avora.xcodeproj/project.pbxproj` (set `INFOPLIST_FILE` for Debug + Release)

**Interfaces:**
- Consumes: `IOS_CLIENT_ID`, `REVERSED_CLIENT_ID` from Task 1.
- Produces: the app now advertises the OAuth callback URL scheme and exposes `GIDClientID`, so the GoogleSignIn SDK self-configures at runtime.

- [ ] **Step 1: Create the partial Info.plist**
  Create `Avora/Info.plist` with exactly these keys (replace the two placeholders with the real values from Task 1). Because `GENERATE_INFOPLIST_FILE = YES`, Xcode layers the generated keys on top of this file — so it only needs the extras:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>GIDClientID</key>
      <string>IOS_CLIENT_ID</string>
      <key>CFBundleURLTypes</key>
      <array>
          <dict>
              <key>CFBundleURLSchemes</key>
              <array>
                  <string>REVERSED_CLIENT_ID</string>
              </array>
          </dict>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Point the target at the Info.plist file**
  In Xcode, select the **Avora** target → Build Settings → search "Info.plist File" → set **Packaging → Info.plist File** to `Avora/Info.plist` for **both** Debug and Release. Leave "Generate Info.plist File" = Yes.
  (In `project.pbxproj` this adds `INFOPLIST_FILE = Avora/Info.plist;` to both build config blocks that already contain `GENERATE_INFOPLIST_FILE = YES;` — near lines 290 and 330.)

- [ ] **Step 3: Build to verify Info.plist merges cleanly**
  Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED** (no "multiple Info.plist" or missing-key errors).

- [ ] **Step 4: Verify the merged plist contains both the generated and custom keys**
  Run: `PLIST=$(find ~/Library/Developer/Xcode/DerivedData -name Info.plist -path '*Avora.app*' 2>/dev/null | head -1); /usr/libexec/PlistBuddy -c "Print :GIDClientID" -c "Print :CFBundleURLTypes" -c "Print :CFBundleIdentifier" "$PLIST"`
  Expected: prints your `IOS_CLIENT_ID`, the URL-types array, and `com.hieudinh.Avora` (proves generated keys still merge in).

- [ ] **Step 5: Commit**
  ```bash
  git add Avora/Info.plist Avora.xcodeproj/project.pbxproj
  git commit -m "chore: configure GoogleSignIn URL scheme and client id"
  ```

---

### Task 4: Add `signInWithGoogle` to AuthService

**Files:**
- Modify: `Avora/Services/AuthService.swift`

**Interfaces:**
- Consumes: existing private `randomNonce()`, `sha256(_:)`; `SupabaseClientProvider.client`; `AvoraError.unauthorized`.
- Produces: `AuthService.signInWithGoogle(presenting: UIViewController) async throws` — mirrors `signInWithApple`.

- [ ] **Step 1: Ensure the imports are present**
  The top of `Avora/Services/AuthService.swift` should read (the `GoogleSignIn` import was added in Task 2 — keep it; add `UIKit` for `UIViewController`):
  ```swift
  import AuthenticationServices
  import CryptoKit
  import GoogleSignIn
  import Supabase
  import UIKit
  ```

- [ ] **Step 2: Add the method inside the `AuthService` enum**
  Add this method directly after `signInWithApple(presentationAnchor:)` (before the private `randomNonce` helper), so it reuses the same private helpers:
  ```swift
  static func signInWithGoogle(presenting: UIViewController) async throws {
      let nonce = randomNonce()
      let result = try await GIDSignIn.sharedInstance.signIn(
          withPresenting: presenting,
          hint: nil,
          additionalScopes: nil,
          nonce: sha256(nonce)
      )
      guard let idToken = result.user.idToken?.tokenString else {
          throw AvoraError.unauthorized
      }
      try await SupabaseClientProvider.client.auth.signInWithIdToken(
          credentials: OpenIDConnectCredentials(provider: .google, idToken: idToken, nonce: nonce)
      )
  }
  ```

- [ ] **Step 3: Build to verify it compiles**
  Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**.

- [ ] **Step 4: Commit**
  ```bash
  git add Avora/Services/AuthService.swift
  git commit -m "feat: add Google sign-in to AuthService"
  ```

---

### Task 5: Add the Google button to LoginView

**Files:**
- Modify: `Avora/LoginView.swift`

**Interfaces:**
- Consumes: `AuthService.signInWithGoogle(presenting:)`; `AppState` (`configureRevenueCat`, `refreshProfile`, `isAuthenticated`).
- Produces: a second sign-in button and a shared `completeSignIn()` helper.

- [ ] **Step 1: Refactor the shared post-auth steps + presenter lookup**
  Replace the existing `logIn()` function in `Avora/LoginView.swift` with the version below, which extracts `completeSignIn()` (reused by both buttons) and a `rootViewController()` helper (Google needs a `UIViewController`; Apple keeps using the window):
  ```swift
  private func logIn() {
      guard let scene = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: { $0.isKeyWindow })
      else { return }

      isLoading = true
      Task {
          defer { isLoading = false }
          do {
              try await AuthService.signInWithApple(presentationAnchor: window)
              await completeSignIn()
          } catch {
              // User cancelled or auth failed — stay on login screen
          }
      }
  }

  private func logInWithGoogle() {
      guard let root = rootViewController() else { return }
      isLoading = true
      Task {
          defer { isLoading = false }
          do {
              try await AuthService.signInWithGoogle(presenting: root)
              await completeSignIn()
          } catch {
              // User cancelled or auth failed — stay on login screen
          }
      }
  }

  private func completeSignIn() async {
      await app.configureRevenueCat()
      await app.refreshProfile()
      app.isAuthenticated = true
  }

  private func rootViewController() -> UIViewController? {
      UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .first { $0.activationState == .foregroundActive }?
          .windows.first { $0.isKeyWindow }?
          .rootViewController
  }
  ```

- [ ] **Step 2: Add the Google button to the layout**
  Replace the `VStack { Spacer(); loginButton }` block in `body` with a stack that shows both buttons:
  ```swift
  VStack(spacing: 12) {
      Spacer()
      loginButton
      googleButton
  }
  ```
  Then add the `googleButton` view alongside `loginButton`:
  ```swift
  private var googleButton: some View {
      AvoraPrimaryButton(action: logInWithGoogle) {
          Label("Continue with Google", systemImage: "globe")
      }
      .disabled(isLoading)
      .preferredColorScheme(.light)
  }
  ```

- [ ] **Step 3: Build to verify it compiles**
  Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**.

- [ ] **Step 4: Commit**
  ```bash
  git add Avora/LoginView.swift
  git commit -m "feat: add Continue with Google button to login screen"
  ```

---

### Task 6: Route the OAuth callback into the GoogleSignIn SDK

**Files:**
- Modify: `Avora/AvoraApp.swift`

**Interfaces:**
- Consumes: `GIDSignIn.sharedInstance.handle(_:)`.
- Produces: the app forwards its incoming URL to the SDK so the Google flow can complete.

- [ ] **Step 1: Import the SDK**
  Add `import GoogleSignIn` under `import SwiftUI` in `Avora/AvoraApp.swift`.

- [ ] **Step 2: Handle the callback URL**
  Update the `WindowGroup` body so `ContentView` forwards opened URLs:
  ```swift
  var body: some Scene {
      WindowGroup {
          ContentView()
              .environment(app)
              .onOpenURL { url in
                  GIDSignIn.sharedInstance.handle(url)
              }
      }
  }
  ```

- [ ] **Step 3: Build to verify it compiles**
  Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**.

- [ ] **Step 4: Commit**
  ```bash
  git add Avora/AvoraApp.swift
  git commit -m "feat: forward OAuth callback URL to GoogleSignIn"
  ```

---

### Task 7: End-to-end manual verification

**Files:** none (runtime verification).

This is the real acceptance test for the feature. Run on a booted simulator or a device signed into a Google account.

- [ ] **Step 1: Run the app and open the login screen**
  Build & run the `Avora` scheme. Confirm both "Sign in with Apple" and "Continue with Google" buttons appear.

- [ ] **Step 2: Complete a Google sign-in**
  Tap "Continue with Google". Expected: the native Google account sheet appears, you pick an account, and the app returns **authenticated** (routes past `LoginView`). Verify the account is newly provisioned: the profile loads with starter credits.

- [ ] **Step 3: Verify RevenueCat identity**
  Confirm no crash and that RevenueCat is configured for the session (paywall/credits screen loads). This proves `completeSignIn()` ran `configureRevenueCat()` with the Supabase user UUID.

- [ ] **Step 4: Verify sign-out + re-sign-in**
  Go to Settings → Sign out. Confirm you return to the login screen. Sign in with Google again → returns to the same authenticated account.

- [ ] **Step 5: Regression — Apple still works**
  Sign out, then tap "Sign in with Apple" and complete it. Expected: still authenticates as before, unchanged.

- [ ] **Step 6: Cancel path**
  On the login screen, tap "Continue with Google" then dismiss the Google sheet. Expected: you stay on the login screen, no crash, the button is re-enabled.

---

## Verification checklist (maps to spec)

- [ ] Google provider enabled in Supabase with iOS client ID authorized (Task 1).
- [ ] GoogleSignIn SDK added (Task 2).
- [ ] `GIDClientID` + reversed-client-ID URL scheme present in merged Info.plist (Task 3).
- [ ] `signInWithGoogle` exchanges the ID token via `signInWithIdToken` with the shared nonce (Task 4).
- [ ] "Continue with Google" button wired to the shared post-auth path (Task 5).
- [ ] OAuth callback forwarded to the SDK (Task 6).
- [ ] E2E: Google sign-in provisions a user; sign-out clears session; Apple unchanged (Task 7).
- [ ] `AppState.swift` unchanged; no secret in the binary.
