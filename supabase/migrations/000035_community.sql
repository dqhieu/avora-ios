-- Community feature storage layer. Likes are keyed to the generation and are
-- independent of share state, so they survive unshare/re-share. like_count is a
-- denormalized counter maintained by the like/unlike RPCs so "most liked" can be
-- indexed and sorted without a per-row aggregate. shared_at null means the
-- creation is private; a timestamp means it is in the community feed.

create table public.likes (
  user_id       uuid not null references auth.users(id) on delete cascade,
  generation_id uuid not null references public.generations(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (user_id, generation_id)
);

alter table public.generations add column shared_at  timestamptz;
alter table public.generations add column like_count int not null default 0;

create index generations_shared_at_idx
  on public.generations (shared_at desc) where shared_at is not null;
create index generations_like_count_idx
  on public.generations (like_count desc, shared_at desc) where shared_at is not null;
create index likes_generation_idx on public.likes (generation_id);

-- likes: the client's only direct access to this table is reading its own
-- rows. All like/unlike mutations go through the like_creation/unlike_creation
-- definer RPCs, which keep like_count consistent; there are no client write
-- policies so direct inserts/deletes can't drift the counter.
alter table public.likes enable row level security;

create policy likes_select_own on public.likes
  for select to authenticated using (user_id = auth.uid());

-- Image visibility: the outputs bucket is private (owner-only reads via
-- outputs_read_own). This second policy lets ANY authenticated user mint a
-- signed URL for an output whose generation is currently shared. Unshare
-- (shared_at -> null) immediately revokes the ability to mint new URLs.
create policy outputs_read_shared on storage.objects
  for select to authenticated
  using (
    bucket_id = 'outputs'
    and exists (
      select 1 from public.generations g
      where g.output_path = name and g.shared_at is not null
    )
  );
