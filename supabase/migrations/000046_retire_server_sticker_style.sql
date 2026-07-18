-- The sticker is now an on-device flow, not a server-generated style. Hide it from
-- the styles grid and drop the transparent flag that only it used. The row is kept
-- (test generations reference styles.id via FK) rather than deleted.
update public.styles set active = false where id = 'sticker';

alter table public.styles drop column transparent;
