insert into public.styles (id, name, prompt_template, sample_image_path) values
('pixar','3D Animated',
 'Render the subject as a polished 3D animated movie character: soft global illumination, '
 'subsurface skin shading, big expressive eyes, rounded stylized features, cinematic depth of '
 'field, preserve the subject''s pose and composition, no text, no watermark.', 'samples/pixar.png'),
('watercolor','Watercolor',
 'Repaint the whole image as a loose watercolor painting: translucent washes, soft bleeding '
 'edges, visible paper texture, delicate pastel palette, preserve composition and subject '
 'likeness, no text, no watermark.', 'samples/watercolor.png'),
('popart','Pop Art',
 'Transform the image into bold pop-art comic style: thick black outlines, halftone dot '
 'shading, flat saturated primary colors, high contrast, preserve subject pose and framing, '
 'no text, no watermark.', 'samples/popart.png'),
('pixel','Pixel Art',
 'Convert the scene into retro 16-bit pixel art: crisp limited color palette, visible square '
 'pixels, dithered shading, clean sprite-style silhouette, preserve composition and subject '
 'likeness, no text, no watermark.', 'samples/pixel.png'),
('clay','Claymation',
 'Reimagine the subject as a handmade claymation model: soft matte clay texture with fingerprint '
 'detail, rounded sculpted forms, warm studio lighting, shallow depth of field, preserve pose '
 'and composition, no text, no watermark.', 'samples/clay.png'),
('plushie','Plush Toy',
 'Turn the subject into a cute stitched plush toy: soft fuzzy fabric texture, visible seams and '
 'embroidery, chunky rounded proportions, button or felt eyes, cozy soft lighting, preserve the '
 'overall pose, no text, no watermark.', 'samples/plushie.png'),
('vaporwave','Vaporwave',
 'Restyle the scene with a retro 80s vaporwave aesthetic: neon pink and cyan gradients, chrome '
 'and glitch accents, sunset grid horizon, dreamy hazy glow, preserve subject pose and framing, '
 'no text, no watermark.', 'samples/vaporwave.png')
on conflict (id) do nothing;
