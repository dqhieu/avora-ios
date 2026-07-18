-- The image model in use (gpt-image-2) does not support transparent output, so the
-- per-style transparent flag is unused. Drop it; sticker output stays opaque JPEG
-- like every other style.
alter table public.styles drop column transparent;
