-- Curated promotional badge shown on the styles grid (e.g. "Hot 🔥").
-- Free-form text rendered verbatim by the app; null means no badge.
alter table public.styles add column badge_text text;

-- Expose badge_text through the public view (security_invoker => relies on the
-- column grant below). Columns are appended after the existing set so the
-- view's leading columns stay unchanged.
create or replace view public.styles_public
  with (security_invoker = true) as
  select id, name, sample_image_path, active, sort_order, badge_text
  from public.styles where active = true;

grant select (badge_text) on public.styles to authenticated, anon;
