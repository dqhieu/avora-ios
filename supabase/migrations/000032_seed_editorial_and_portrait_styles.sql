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
