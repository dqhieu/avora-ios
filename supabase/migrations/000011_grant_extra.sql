create or replace function public.grant_extra(p_uid uuid, p_amount int)
returns void language sql security definer set search_path = public as $$
  update public.profiles set extra_credits = extra_credits + p_amount where id = p_uid;
$$;
revoke all on function public.grant_extra(uuid,int) from public, anon, authenticated;
