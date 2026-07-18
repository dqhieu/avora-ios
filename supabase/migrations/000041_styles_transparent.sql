-- Styles whose output should keep a transparent alpha background (e.g. stickers).
-- The worker branches on this to skip JPEG flattening and store a PNG instead.
alter table public.styles
  add column transparent boolean not null default false;

update public.styles set transparent = true where id = 'sticker';
