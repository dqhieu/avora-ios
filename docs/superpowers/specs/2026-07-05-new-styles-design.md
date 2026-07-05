# Design: Five New Restyle Styles

Date: 2026-07-05

## Goal

Add five new image-generation styles to Avora: two product-photography styles,
two portrait/illustration styles, and one whimsical felt-art style. Each ships as
a server-side prompt template plus a grid entry.

## Context

Styles live in Supabase (`public.styles` table) and are seeded via SQL migrations.
The iOS app fetches them from the `styles_public` view and only ever sees
`id`, `name`, `sample_image_path`, `active`, `sort_order`, `badge_text` — the
`prompt_template` stays server-side. Every built-in style is a **restyle transform**:
the user uploads a photo and the prompt transforms it while preserving the subject.

Reference format: `supabase/migrations/000024_seed_imagegen_template_styles.sql`.

## Design decisions

- **Subject-preserving.** The source prompts hard-coded specific subjects (a
  curly-haired woman, a freckled boy) or whole scenes. Each prompt is adapted to
  preserve whatever subject the user uploads, keeping only the aesthetic. Every
  prompt ends with "no text, no watermark" per house convention.
- **`sort_order` default 0.** Consistent with the last seed batch (000024); new
  rows surface at the top of the grid.
- **No badges** by default.
- **Thumbnails supplied separately.** The migration references
  `samples/<id>.png`; the user uploads the five preview images to the `assets`
  bucket. Until then, cards show the empty-photo placeholder.

## The five styles

| id | name | sample path |
|----|------|-------------|
| `doodleproduct` | Doodle Product | `samples/doodleproduct.png` |
| `crayonportrait` | Crayon Portrait | `samples/crayonportrait.png` |
| `mosseditorial` | Moss Editorial | `samples/mosseditorial.png` |
| `feltart` | Felt Art | `samples/feltart.png` |
| `proheadshot` | Pro Headshot | `samples/proheadshot.png` |

### Prompt templates (final)

**doodleproduct**
> Place the uploaded product in a clean warm studio scene: textured beige wall
> background, soft directional sunlight casting long shadows, simple tabletop
> surface, product arranged in a playful concept composition. Overlay a
> hand-drawn white line doodle character playfully interacting with the product,
> mixed-media look combining real photography and sketch illustration, high-end
> branding feel, shallow depth of field, ultra realistic, preserve the product's
> exact shape, proportions, label, and branding, no extra text, no watermark.

**crayonportrait**
> Reimagine the subject as a soft wax crayon and colored pencil illustration:
> gentle hand-drawn texture with visible crayon strokes and subtle grain, natural
> proportions, simplified features, warm rosy tones, calm and cozy mood, off-white
> paper background, stylized yet mature and human — not cartoonish, chibi, or
> childish. Preserve the subject's likeness, expression, and framing, no text, no
> watermark.

**mosseditorial**
> Using the uploaded product as the exact reference for shape, material,
> proportions, label placement, and branding, create a high-end editorial product
> photograph. Place the product on a bed of deep green moss with rich organic
> texture, shot top-down with the product precisely centered. Soft natural
> daylight from a slight angle creates gentle directional highlights and long,
> feathered shadows falling unevenly across the moss for depth, while the product
> stays evenly lit. Subtle atmospheric haze adds cinematic softness. Emphasize the
> tactile contrast between porous matte moss and the smooth product surface.
> Scandinavian eco-luxury aesthetic: minimal, refined, restrained palette, premium
> skincare editorial. No text, no watermark.

**feltart**
> Reimagine the subject as a handcrafted needle-felt character joyfully riding a
> giant plush yellow star through a cosmic felt landscape: swirling purple and
> blue felt nebulae, small colorful felt planets in the background, rich textured
> wool fibers, dreamy handmade quality, full of wonder and adventure. Preserve the
> subject's likeness and expression, no text, no watermark.

**proheadshot**
> Create a polished professional headshot of the person in the image: modern
> minimalist black long-sleeve top and black tailored trousers, hair with natural
> volume, confident yet approachable expression with a subtle warm smile, relaxed
> professional pose with the body angled slightly and head gently turned toward
> camera. Soft neutral gradient background, soft directional lighting that evenly
> illuminates the face while preserving realistic skin texture, no harsh shadows.
> Polished yet authentic, LinkedIn-ready. Preserve the person's likeness, no text,
> no watermark.

## Implementation

Single migration `supabase/migrations/000032_seed_editorial_and_portrait_styles.sql`
inserting the five rows into `public.styles` with
`insert ... on conflict (id) do nothing`, mirroring 000024. SQL string literals
escape apostrophes as `''`.

## Out of scope

- Preview thumbnail generation (user supplies the five `samples/*.png` images).
- No app/client code changes — the grid renders new rows automatically.
- No new schema columns, badges, or category grouping.

## Success criteria

- Migration inserts exactly five rows; re-running is idempotent.
- After deploy, the five styles appear in the app's styles grid.
- Generating with each style transforms the uploaded photo in the intended
  aesthetic while preserving the subject.
