insert into public.styles (id, name, prompt_template, sample_image_path) values
('knitted','Knitted',
 'Reimagine the subject as a cozy handmade knitted doll: soft wool yarn texture, visible '
 'stitches and seams, embroidered facial details, chunky rounded proportions, warm soft '
 'lighting, preserve the subject''s pose and composition, no text, no watermark.', 'samples/knitted.png'),
('digitalart','Digital Art',
 'Recreate the image as clean modern digital art: bold flat shapes, smooth vector-like forms, '
 'crisp edges, balanced vivid colors, preserve the subject''s likeness, pose, and composition, '
 'no text, no watermark.', 'samples/digitalart.png'),
('anime','Anime',
 'Reinterpret the image as a cinematic anime illustration: delicate line art, painterly cel '
 'shading, soft atmospheric lighting and gradients, expressive eyes, preserve the subject''s '
 'pose and composition, no text, no watermark.', 'samples/anime.png'),
('futuristic','Futuristic',
 'Transform the scene into a futuristic sci-fi world: cool vibrant blue palette, neon glows and '
 'holographic lighting, smooth gradients, slightly reflective surfaces, high contrast, keep the '
 'subject photorealistic, preserve pose and framing, no text, no watermark.', 'samples/futuristic.png'),
('loficomic','Lo-Fi Comic',
 'Reinterpret the image as a stylish lo-fi comic illustration: clean bold outlines, simplified '
 'flat shading, muted retro colors, soft halftone texture, graphic composition, preserve the '
 'subject''s pose, expression, and framing, no text, no watermark.', 'samples/loficomic.png')
on conflict (id) do nothing;
