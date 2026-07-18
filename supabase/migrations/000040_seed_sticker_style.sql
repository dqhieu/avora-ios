insert into public.styles (id, name, prompt_template, sample_image_path) values
('sticker','Sticker',
 'Turn the uploaded image into a die-cut glossy sticker while keeping the original '
 'subject exactly as it is. Do not redraw, restyle, cartoonify, or regenerate the '
 'subject — preserve its exact appearance, colors, texture, details, pose, and '
 'expression pixel-for-pixel. Cleanly cut the subject out from its background along '
 'its silhouette, then wrap the entire silhouette in a bold, uniform, thick solid '
 'white die-cut border — an even white outline offset all the way around the subject '
 'like a real vinyl sticker, clearly visible and consistent in thickness on every '
 'side. Apply a subtle glossy vinyl highlight over the top and place the finished '
 'sticker on a fully transparent background (transparent alpha, nothing behind the '
 'sticker). Change nothing about the subject itself, no text, no watermark.', 'samples/sticker.png')
on conflict (id) do nothing;
