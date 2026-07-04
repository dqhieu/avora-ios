-- Sign-in bonus reveal: track whether a user has seen their signup-bonus modal,
-- plus a security definer RPC for the client to mark it seen. profiles has no
-- client write policy (owner read-only; all writes go through definer funcs),
-- so the flag can only be flipped via this function.

alter table public.profiles
  add column signup_bonus_seen boolean not null default false;
-- Adding a NOT NULL DEFAULT false column backfills every existing row to false,
-- so all current accounts see the reveal once on next sign-in. New accounts
-- inserted by handle_new_user() inherit the default too (no trigger change).

create or replace function public.mark_signup_bonus_seen()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles set signup_bonus_seen = true where id = auth.uid();
end;
$$;

revoke all on function public.mark_signup_bonus_seen() from public, anon;
grant execute on function public.mark_signup_bonus_seen() to authenticated;
