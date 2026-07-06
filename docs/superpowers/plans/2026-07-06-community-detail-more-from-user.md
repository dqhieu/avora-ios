# "More from @username" in CommunityDetailView — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "More from @username" grid on `CommunityDetailView` showing the author's other publicly shared creations.

**Architecture:** One new read-only `AvoraAPI` method queries the existing `community_feed` view filtered by `username` (unique) and excluding the current item. `CommunityDetailView`'s body becomes a `ScrollView`; a conditionally-rendered `LazyVGrid` section of tappable thumbnails is appended below the existing content, each cell a `NavigationLink` that recursively pushes another `CommunityDetailView` via the parent stack's existing destination.

**Tech Stack:** Swift, SwiftUI, Supabase Swift SDK (PostgREST query builder), Xcode.

## Global Constraints

- **No test harness for Swift:** the app target has no XCTest bundle. Verification for every task is: the app **compiles** (build succeeds) plus a **simulator visual check**. Do not add a test target — it is out of scope and not the codebase pattern.
- **No schema/migration change.** Reuse the existing `community_feed` view and `CommunityItem` model as-is.
- **Silent failure convention:** network errors in community views are swallowed (feed keeps prior content); mirror this — a failed fetch leaves the section hidden.
- **Design tokens:** use `Spacing.*` and `Radius.*` from `Avora/DesignSystem/Layout.swift`, and `Color.avora*` colors. Never hardcode spacings/colors.
- **File size:** keep `CommunityDetailView.swift` under 200 lines.
- **Build scheme:** `Avora` (`Avora.xcodeproj`). No workspace.

---

### Task 1: Add `communityByUser` query to `AvoraAPI`

**Files:**
- Modify: `Avora/Services/AvoraAPI.swift` (insert after `communityMostLiked(offset:)`, which ends at line 175)

**Interfaces:**
- Consumes: existing `private var db: SupabaseClient`, the `community_feed` view, and the `CommunityItem` model (`Avora/Models/CommunityItem.swift`).
- Produces: `func communityByUser(_ username: String, excluding id: UUID, limit: Int = 12) async throws -> [CommunityItem]` — used by Task 2.

- [ ] **Step 1: Add the method**

Insert this method immediately after the closing brace of `communityMostLiked(offset:)` (after line 175 of `Avora/Services/AvoraAPI.swift`):

```swift
/// Other publicly shared creations by one author, newest first, excluding the
/// creation currently being viewed. Filters by username (unique per profile);
/// no schema change needed. Returns [] when the author has no other shared work.
func communityByUser(_ username: String, excluding id: UUID, limit: Int = 12) async throws
    -> [CommunityItem] {
    try await db.from("community_feed")
        .select("id,output_path,style_id,custom_prompt,like_count,username,liked_by_me,shared_at")
        .eq("username", value: username)
        .neq("id", value: id.uuidString)
        .order("shared_at", ascending: false)
        .limit(limit)
        .execute()
        .value
}
```

- [ ] **Step 2: Verify it compiles**

Run (XcodeBuildMCP): `build_sim` with scheme `Avora` and an available iOS simulator.
Fallback (shell): `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: **BUILD SUCCEEDED**. The method is unused for now — a Swift "unused" warning is not expected for a public-ish struct method, but if one appears it is acceptable and resolved by Task 2.

- [ ] **Step 3: Commit**

```bash
git add Avora/Services/AvoraAPI.swift
git commit -m "feat: add communityByUser query for author's other shared creations"
```

---

### Task 2: Render the "More from @username" section in `CommunityDetailView`

**Files:**
- Modify: `Avora/Views/Community/CommunityDetailView.swift` (replace `body` at lines 24-46; add state + helpers)

**Interfaces:**
- Consumes: `AvoraAPI.shared.communityByUser(_:excluding:limit:)` from Task 1; the existing `navigationDestination(for: CommunityItem.self)` registered on the parent stack in `CommunityView.swift:29`; `RemoteImage`, `Spacing`, `Radius`, `Color.avoraSurface`, `Color.avoraTextSecondary`.
- Produces: nothing consumed by later tasks (terminal task).

- [ ] **Step 1: Add the `more` state property**

In `CommunityDetailView`, add below the existing `@State private var likeCount: Int` (line 11):

```swift
    @State private var more: [CommunityItem] = []
```

- [ ] **Step 2: Replace `body` with a scrolling layout that includes the section**

Replace the entire `body` (lines 24-46) with:

```swift
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if let path = item.outputPath {
                    RemoteImage(path: path, contentMode: .fit)
                }
                HStack {
                    Text(item.username.map { "@\($0)" } ?? "@unknown")
                        .font(.avoraHeadline)
                        .foregroundStyle(Color.avoraTextSecondary)
                    Spacer()
                    likeButton
                }
                .padding(.horizontal, Spacing.lg)
                createButton
                moreSection
            }
            .padding(.vertical, Spacing.lg)
        }
        .navigationTitle(style?.name ?? "Creation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await resolveStyle()
            await loadMore()
        }
    }
```

- [ ] **Step 3: Add the `moreSection` view, its columns, thumbnail, and loader**

Add these members inside `CommunityDetailView` (place after the `createButton` computed property, before `resolveStyle()`):

```swift
    private let moreColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    @ViewBuilder
    private var moreSection: some View {
        if !more.isEmpty, let username = item.username {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("More from @\(username)")
                    .font(.avoraHeadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: moreColumns, spacing: Spacing.sm) {
                    ForEach(more) { other in
                        NavigationLink(value: other) { moreThumbnail(other) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func moreThumbnail(_ other: CommunityItem) -> some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Color.avoraSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let path = other.outputPath {
                    RemoteImage(path: path, contentMode: .fill)
                }
            }
            .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    }

    private func loadMore() async {
        guard let username = item.username else { return }
        more = (try? await AvoraAPI.shared.communityByUser(username, excluding: item.id)) ?? []
    }
```

- [ ] **Step 4: Verify it compiles**

Run (XcodeBuildMCP): `build_sim` with scheme `Avora`.
Fallback (shell): `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 5: Simulator visual check**

Run the app (XcodeBuildMCP `build_run_sim`, scheme `Avora`). Navigate: Community tab → tap any card whose author has more than one shared creation.
Verify:
- The "More from @username" header + a 2-column grid of square thumbnails appears below the "Create with this style" button, and the whole screen scrolls.
- Tapping a thumbnail pushes a new detail screen for that creation (back button returns).
- Open a creation by an author with only that one shared item → the section is absent and the screen looks as it did before (no empty header).

- [ ] **Step 6: Commit**

```bash
git add Avora/Views/Community/CommunityDetailView.swift
git commit -m "feat: show author's other shared creations on community detail"
```

---

## Self-Review

**Spec coverage:**
- "More from @username" section, up to 12, newest first, excluding current → Task 1 query (`.limit(12)`, `.order shared_at desc`, `.neq id`).
- Full-screen scroll + 2-col grid (layout choice B) → Task 2 Step 2/3 (`ScrollView` + `LazyVGrid` 2 cols).
- Tap pushes new `CommunityDetailView` (choice A) → Task 2 `NavigationLink(value: other)` + existing stack destination.
- Capped batch, no pagination (choice A) → single query, no load-more.
- Hide section when no others (choice A) → `if !more.isEmpty` guard in `moreSection`.
- No like row in thumbnails → `moreThumbnail` renders image only.
- No schema change / reuse `CommunityItem` → confirmed, view + model untouched except additive.
- Silent failure → `try?` in `loadMore`.

**Placeholder scan:** none — all steps contain concrete code and exact commands.

**Type consistency:** `communityByUser(_:excluding:limit:)` signature identical in Task 1 (definition) and Task 2 (call site). `more: [CommunityItem]`, `moreColumns`, `moreThumbnail`, `moreSection`, `loadMore` names consistent across Task 2 steps. Tokens `Spacing.lg/.sm`, `Radius.md` verified against `Layout.swift`. `RemoteImage(path:contentMode:)` matches `RemoteImage.swift`.
