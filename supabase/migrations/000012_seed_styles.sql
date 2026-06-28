insert into public.styles (id, name, prompt_template, sample_image_path) values
('ghibli','Studio Anime',
 'Restyle the entire photo as a hand-painted Japanese animation cel: soft cel shading, '
 'warm painterly lighting, gentle color grading, clean line art, preserve the subject''s '
 'pose and composition, no text, no watermark.', 'samples/ghibli.png'),
('oil','Oil Painting',
 'Repaint the whole image as a textured oil painting with visible brush strokes, rich impasto, '
 'classical warm palette, dramatic lighting, preserve composition and subject likeness, '
 'no text, no watermark.', 'samples/oil.png'),
('cyberpunk','Neon Cyberpunk',
 'Transform the scene into a neon-lit cyberpunk aesthetic: saturated magenta and cyan rim '
 'lighting, rain-slick reflections, futuristic signage bokeh, cinematic contrast, preserve '
 'subject pose and framing, no text, no watermark.', 'samples/cyberpunk.png')
on conflict (id) do nothing;
