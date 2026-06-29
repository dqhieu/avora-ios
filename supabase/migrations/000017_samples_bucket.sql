-- Public bucket for shared, non-user-specific assets (e.g. style sample thumbnails).
-- Objects live under a "samples/" prefix matching styles.sample_image_path.
-- Public bucket => objects are world-readable by URL, so no storage.objects RLS
-- policy is required for reads. Uploads are done out-of-band (dashboard / service role).
insert into storage.buckets (id, name, public) values
  ('assets','assets', true)
  on conflict (id) do nothing;
