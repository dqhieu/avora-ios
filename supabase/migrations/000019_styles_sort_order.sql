-- Curated ordering for the styles grid. Lower sort_order shows first;
-- ties fall back to name. Default 0 so new rows surface at the top until
-- given an explicit position.
alter table public.styles add column sort_order int not null default 0;

-- Backfill existing styles to preserve the current alphabetical order,
-- spaced by 10 so new styles can be inserted between them.
with ordered as (
  select id, (row_number() over (order by name)) * 10 as rn
  from public.styles
)
update public.styles s
  set sort_order = o.rn
  from ordered o
  where s.id = o.id;

-- Expose sort_order through the public view (security_invoker => relies on the
-- column grant below).
create or replace view public.styles_public
  with (security_invoker = true) as
  select id, name, sample_image_path, active, sort_order
  from public.styles where active = true;

grant select (sort_order) on public.styles to authenticated, anon;
