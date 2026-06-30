insert into public.styles (id, name, prompt_template, sample_image_path, badge_text) values
('fairytaleprincess','Fairytale Princess',
 'Reimagine the subject as a fairytale princess in a classic animated storybook style: flowing '
 'royal ballgown, sparkling tiara, soft glowing skin, big expressive eyes, magical golden '
 'highlights, dreamy enchanted-castle backdrop with delicate bokeh, preserve the subject''s '
 'likeness and pose, no text, no watermark.', 'samples/fairytaleprincess.png', 'New ✨')
on conflict (id) do nothing;
