-- Like / unlike toggle. Definer so the client never writes like_count directly.
-- The likes primary key makes a duplicate like a no-op (on conflict do nothing),
-- and FOUND tells us whether the row actually changed, so like_count only moves
-- when the caller's like state actually flips. Returns the resulting count so the
-- client can reconcile its optimistic update with the truth.

create or replace function public.like_creation(gen_id uuid)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_count int;
begin
  insert into public.likes (user_id, generation_id)
    values (v_uid, gen_id)
    on conflict (user_id, generation_id) do nothing;

  if found then
    update public.generations
      set like_count = like_count + 1
      where id = gen_id
      returning like_count into v_count;
  else
    select like_count into v_count from public.generations where id = gen_id;
  end if;

  return coalesce(v_count, 0);
end;
$$;

create or replace function public.unlike_creation(gen_id uuid)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_count int;
begin
  delete from public.likes
    where user_id = v_uid and generation_id = gen_id;

  if found then
    update public.generations
      set like_count = greatest(like_count - 1, 0)
      where id = gen_id
      returning like_count into v_count;
  else
    select like_count into v_count from public.generations where id = gen_id;
  end if;

  return coalesce(v_count, 0);
end;
$$;

revoke all on function public.like_creation(uuid)   from public, anon;
revoke all on function public.unlike_creation(uuid) from public, anon;
grant execute on function public.like_creation(uuid)   to authenticated;
grant execute on function public.unlike_creation(uuid) to authenticated;
