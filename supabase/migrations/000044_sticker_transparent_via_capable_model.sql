-- Transparent output is viable again by running flagged styles on a
-- transparency-capable image model (the worker picks the model). Re-add the flag
-- and enable it for the sticker style.
alter table public.styles
  add column transparent boolean not null default false;

update public.styles set transparent = true where id = 'sticker';
