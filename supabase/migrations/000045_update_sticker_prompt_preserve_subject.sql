-- Improve subject fidelity: reframe as a purely additive compositing task (border +
-- background only, nothing applied to the subject) and drop the gloss-on-subject that
-- was causing the object to be re-rendered. Seed insert is a no-op, so update in place.
update public.styles set prompt_template =
 'Keep the uploaded photo of the subject exactly as it is — this is a compositing '
 'task, not a generation task. Do not redraw, repaint, restyle, cartoonify, '
 'regenerate, or re-render the subject in any way. Every pixel of the subject must '
 'stay identical to the original: same colors, lighting, texture, sharpness, fine '
 'details, pose, and expression. Only add elements around the subject, never on it. '
 'Cleanly isolate the subject along its silhouette and wrap it in a bold, uniform, '
 'thick solid white die-cut sticker border — an even white outline offset all the way '
 'around the subject like a real vinyl sticker, consistent in thickness on every side. '
 'Place it on a fully transparent background (transparent alpha, nothing behind the '
 'sticker). Do not apply any gloss, sheen, gradient, filter, shadow, or lighting '
 'effect to the subject. No drop shadow, no cast shadow, no text, no watermark.'
where id = 'sticker';
