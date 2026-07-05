# New Restyle Styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seed five new restyle styles (Doodle Product, Crayon Portrait, Moss Editorial, Felt Art, Pro Headshot) into the Supabase `styles` table so they appear in the app's styles grid.

**Architecture:** A single idempotent SQL seed migration inserts five rows into `public.styles`, mirroring the existing seed migration `000024_seed_imagegen_template_styles.sql`. No app/client code changes — the iOS grid renders new active rows automatically via the `styles_public` view. Preview thumbnails are uploaded separately by the user.

**Tech Stack:** PostgreSQL / Supabase migrations, Supabase CLI.

## Global Constraints

- File name: `supabase/migrations/000032_seed_editorial_and_portrait_styles.sql` (next sequential number).
- Insert form: `insert into public.styles (...) values (...) on conflict (id) do nothing;` (idempotent, matches 000024).
- SQL string literals escape apostrophes as `''`.
- Every prompt ends with "no text, no watermark" (house convention).
- `sample_image_path` = `samples/<id>.png` for each style.
- `sort_order` is left at its column default (0) — not set explicitly, matching 000024.
- The five ids, names, and prompt templates are copied verbatim from the spec: `docs/superpowers/specs/2026-07-05-new-styles-design.md`.

---

### Task 1: Seed migration for the five new styles

**Files:**
- Create: `supabase/migrations/000032_seed_editorial_and_portrait_styles.sql`

**Interfaces:**
- Consumes: existing `public.styles` table schema (columns `id`, `name`, `prompt_template`, `sample_image_path`, plus defaulted `active`, `sort_order`, `badge_text`).
- Produces: five active style rows with ids `doodleproduct`, `crayonportrait`, `mosseditorial`, `feltart`, `proheadshot`.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/000032_seed_editorial_and_portrait_styles.sql` with exactly this content:

```sql
insert into public.styles (id, name, prompt_template, sample_image_path) values
('doodleproduct','Doodle Product',
 'Place the uploaded product in a clean warm studio scene: textured beige wall '
 'background, soft directional sunlight casting long shadows, simple tabletop '
 'surface, product arranged in a playful concept composition. Overlay a hand-drawn '
 'white line doodle character playfully interacting with the product, mixed-media '
 'look combining real photography and sketch illustration, high-end branding feel, '
 'shallow depth of field, ultra realistic, preserve the product''s exact shape, '
 'proportions, label, and branding, no extra text, no watermark.', 'samples/doodleproduct.png'),
('crayonportrait','Crayon Portrait',
 'Reimagine the subject as a soft wax crayon and colored pencil illustration: '
 'gentle hand-drawn texture with visible crayon strokes and subtle grain, natural '
 'proportions, simplified features, warm rosy tones, calm and cozy mood, off-white '
 'paper background, stylized yet mature and human — not cartoonish, chibi, or '
 'childish. Preserve the subject''s likeness, expression, and framing, no text, no '
 'watermark.', 'samples/crayonportrait.png'),
('mosseditorial','Moss Editorial',
 'Using the uploaded product as the exact reference for shape, material, '
 'proportions, label placement, and branding, create a high-end editorial product '
 'photograph. Place the product on a bed of deep green moss with rich organic '
 'texture, shot top-down with the product precisely centered. Soft natural daylight '
 'from a slight angle creates gentle directional highlights and long, feathered '
 'shadows falling unevenly across the moss for depth, while the product stays evenly '
 'lit. Subtle atmospheric haze adds cinematic softness. Emphasize the tactile '
 'contrast between porous matte moss and the smooth product surface. Scandinavian '
 'eco-luxury aesthetic: minimal, refined, restrained palette, premium skincare '
 'editorial. No text, no watermark.', 'samples/mosseditorial.png'),
('feltart','Felt Art',
 'Reimagine the subject as a handcrafted needle-felt character joyfully riding a '
 'giant plush yellow star through a cosmic felt landscape: swirling purple and blue '
 'felt nebulae, small colorful felt planets in the background, rich textured wool '
 'fibers, dreamy handmade quality, full of wonder and adventure. Preserve the '
 'subject''s likeness and expression, no text, no watermark.', 'samples/feltart.png'),
('proheadshot','Pro Headshot',
 'Create a polished professional headshot of the person in the image: modern '
 'minimalist black long-sleeve top and black tailored trousers, hair with natural '
 'volume, confident yet approachable expression with a subtle warm smile, relaxed '
 'professional pose with the body angled slightly and head gently turned toward '
 'camera. Soft neutral gradient background, soft directional lighting that evenly '
 'illuminates the face while preserving realistic skin texture, no harsh shadows. '
 'Polished yet authentic, LinkedIn-ready. Preserve the person''s likeness, no text, '
 'no watermark.', 'samples/proheadshot.png')
on conflict (id) do nothing;
```

- [ ] **Step 2: Apply the migration locally**

Run: `supabase db reset`
Expected: all migrations replay with no errors; the final migration `000032_seed_editorial_and_portrait_styles.sql` applies cleanly.

(If the local stack isn't running, start it first: `supabase start`.)

- [ ] **Step 3: Verify the five rows exist and are active**

Run:
```bash
supabase db reset >/dev/null 2>&1; \
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" -c \
"select id, name, sample_image_path, active from public.styles where id in ('doodleproduct','crayonportrait','mosseditorial','feltart','proheadshot') order by id;"
```
Expected: exactly 5 rows returned, each with `active = t` and `sample_image_path = samples/<id>.png`.

- [ ] **Step 4: Verify idempotency**

Re-run the migration body against the already-seeded DB (the `on conflict do nothing` guard must prevent duplicates):
```bash
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" -f supabase/migrations/000032_seed_editorial_and_portrait_styles.sql && \
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" -c \
"select count(*) from public.styles where id in ('doodleproduct','crayonportrait','mosseditorial','feltart','proheadshot');"
```
Expected: no error, count = 5 (no duplicates).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000032_seed_editorial_and_portrait_styles.sql
git commit -m "feat: seed five new restyle styles"
```

---

## Post-implementation (manual, out of plan scope)

These are the user's steps, done outside this plan:

1. Upload preview thumbnails to the `assets` bucket at `samples/doodleproduct.png`, `samples/crayonportrait.png`, `samples/mosseditorial.png`, `samples/feltart.png`, `samples/proheadshot.png`.
2. Deploy to production: `supabase db push`.
3. Launch the app and confirm the five styles appear in the grid and generate correctly.

## Self-Review

- **Spec coverage:** All five styles from the spec have exact prompt templates in Task 1. Subject-preserving wording, "no text, no watermark", `sort_order` default, no badges, thumbnails referenced but supplied separately — all reflected. ✓
- **Placeholder scan:** No TBD/TODO; full SQL provided; exact verification commands. ✓
- **Type consistency:** All five ids used consistently across the migration and every verification step. ✓
