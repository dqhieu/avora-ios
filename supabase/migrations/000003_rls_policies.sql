alter table public.profiles    enable row level security;
alter table public.styles      enable row level security;
alter table public.generations enable row level security;
alter table public.purchases   enable row level security;
alter table public.daily_spend enable row level security;

-- profiles: owner read only; no client writes
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());

-- generations: owner read only; writes go through service role (bypasses RLS)
create policy generations_select_own on public.generations
  for select to authenticated using (user_id = auth.uid());

-- styles base table: no client access at all (no policies + RLS on = deny)
-- expose a column-limited view instead:
create view public.styles_public
  with (security_invoker = true) as
  select id, name, sample_image_path, active from public.styles where active = true;
grant select on public.styles_public to authenticated, anon;

-- Row-level policy permits all rows; column-level GRANTs (below) restrict which columns are visible.
create policy styles_public_read on public.styles
  for select to authenticated, anon using (true);
-- revoke direct column access to prompt_template via column privileges:
revoke all on public.styles from authenticated, anon;
grant select (id, name, sample_image_path, active)
  on public.styles to authenticated, anon;

insert into storage.buckets (id, name, public) values
  ('inputs','inputs', false),
  ('outputs','outputs', false)
  on conflict (id) do nothing;

-- users may read/write only objects under their own uid prefix: "<uid>/..."
create policy inputs_own on storage.objects
  for all to authenticated
  using (bucket_id = 'inputs'  and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'inputs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy outputs_read_own on storage.objects
  for select to authenticated
  using (bucket_id = 'outputs' and (storage.foldername(name))[1] = auth.uid()::text);
-- outputs are written by the worker (service role), so no client insert policy.
