-- Client-facing username RPCs. profiles is owner-read-only with no client write
-- policy, so the app changes its username only through set_username, and can
-- only check availability of others' names through is_username_available.

create or replace function public.is_username_available(candidate text)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if candidate !~ '^[a-z0-9_]{3,20}$' or candidate !~ '[a-z]' then
    return false;
  end if;
  return not exists (
    select 1 from public.profiles
      where username = candidate and id is distinct from v_uid
  );
end;
$$;

create or replace function public.set_username(new_username text)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return 'invalid';
  end if;
  if new_username !~ '^[a-z0-9_]{3,20}$' or new_username !~ '[a-z]' then
    return 'invalid';
  end if;
  update public.profiles set username = new_username where id = v_uid;
  return 'ok';
exception
  when unique_violation then
    return 'taken';
end;
$$;

revoke all on function public.is_username_available(text) from public, anon;
revoke all on function public.set_username(text)          from public, anon;
grant execute on function public.is_username_available(text) to authenticated;
grant execute on function public.set_username(text)          to authenticated;
