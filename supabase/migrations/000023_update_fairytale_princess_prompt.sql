-- Re-seed inserts use `on conflict do nothing`, so the already-seeded row needs
-- an explicit UPDATE. Revised prompt leads with identity preservation and only
-- restyles wardrobe/setting, keeping the result photographic so the face stays
-- recognizable instead of drifting into a cartoon.
update public.styles
set prompt_template =
 'Keep the exact same real person from the photo: identical face, facial features, '
 'skin tone, hairstyle, and expression. Do not stylize, cartoonify, or alter their '
 'identity — keep the face fully photographic and realistic. Only change the wardrobe '
 'and setting: dress the subject in an elegant fairytale princess ballgown with a '
 'sparkling tiara, and place them in a softly lit enchanted-castle scene with warm '
 'cinematic lighting and gentle background bokeh. Preserve the original framing, pose, '
 'and camera angle. Photorealistic, no illustration or cartoon look, no text, no watermark.'
where id = 'fairytaleprincess';
