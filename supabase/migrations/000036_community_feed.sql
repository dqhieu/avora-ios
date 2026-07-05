-- The community feed. generations is owner-read-only under RLS, so a plain
-- (security_invoker) view could not return other users' rows. This definer view
-- runs with owner privileges to cross that RLS, but exposes ONLY shared rows and
-- ONLY safe columns (incl. custom_prompt, which becomes public on share, per the
-- reuse decision, and the author's username). auth.uid() still resolves to the
-- caller inside a definer view, so liked_by_me is correct per-user.

create view public.community_feed with (security_invoker = false) as
  select g.id,
         g.output_path,
         g.style_id,
         g.custom_prompt,
         g.like_count,
         g.shared_at,
         p.username,
         exists (
           select 1 from public.likes l
           where l.generation_id = g.id and l.user_id = auth.uid()
         ) as liked_by_me
  from public.generations g
  join public.profiles p on p.id = g.user_id
  where g.shared_at is not null;

revoke all on public.community_feed from public, anon;
grant select on public.community_feed to authenticated;

-- Share / unshare toggle. Owner-checked; sets or clears shared_at. Keeps the
-- "no client writes to generations" invariant. like_count is left untouched, so
-- likes persist across unshare and are restored on re-share.
create or replace function public.share_creation(gen_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.generations
    set shared_at = now()
    where id = gen_id and user_id = auth.uid();
end;
$$;

create or replace function public.unshare_creation(gen_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.generations
    set shared_at = null
    where id = gen_id and user_id = auth.uid();
end;
$$;

revoke all on function public.share_creation(uuid)   from public, anon;
revoke all on function public.unshare_creation(uuid) from public, anon;
grant execute on function public.share_creation(uuid)   to authenticated;
grant execute on function public.unshare_creation(uuid) to authenticated;
