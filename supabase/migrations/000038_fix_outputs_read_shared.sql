-- outputs_read_shared originally referenced public.generations directly in its
-- USING clause. generations is owner-read-only under RLS (generations_select_own),
-- and that RLS also applies inside the policy subquery, so a non-owner evaluating
-- the policy could never see another user's shared row: the exists() was always
-- false for other users, and only the owner could mint a signed URL for their own
-- shared output. That made shared photos invisible to everyone but the author.
--
-- Route the shared check through a security-definer function that crosses the
-- generations RLS (the same technique community_feed uses), so any authenticated
-- user can mint a signed URL for a currently-shared output. Private outputs stay
-- hidden, and unshare (shared_at -> null) still immediately revokes new URLs.

create or replace function public.output_is_shared(object_name text)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.generations g
    where g.output_path = object_name and g.shared_at is not null
  );
$$;

revoke all on function public.output_is_shared(text) from public, anon;
grant execute on function public.output_is_shared(text) to authenticated;

drop policy outputs_read_shared on storage.objects;
create policy outputs_read_shared on storage.objects
  for select to authenticated
  using (bucket_id = 'outputs' and public.output_is_shared(name));
