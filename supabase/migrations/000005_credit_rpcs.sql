-- cost per generation
create or replace function public.deduct_credit(p_uid uuid)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_cost int := 25;
  v_bucket text;
begin
  -- lock the row first so concurrent submits serialize on this profile
  perform 1 from public.profiles where id = p_uid for update;

  update public.profiles set weekly_credits = weekly_credits - v_cost
    where id = p_uid and weekly_credits >= v_cost
    returning 'weekly' into v_bucket;

  if v_bucket is null then
    update public.profiles set extra_credits = extra_credits - v_cost
      where id = p_uid and extra_credits >= v_cost
      returning 'extra' into v_bucket;
  end if;

  if v_bucket is null then
    raise exception 'insufficient_credits' using errcode = 'P0001';
  end if;

  return v_bucket;
end;
$$;

create or replace function public.refund_credit(p_generation_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid; v_bucket text; v_amount int;
begin
  -- only refund on the pending -> failed transition; guarantees once-only
  update public.generations
    set status = 'failed', completed_at = now()
    where id = p_generation_id and status = 'pending'
    returning user_id, charged_bucket, charged_amount
    into v_user, v_bucket, v_amount;

  if v_user is null then
    return;  -- already terminal: idempotent no-op
  end if;

  if v_bucket = 'weekly' then
    update public.profiles set weekly_credits = weekly_credits + v_amount where id = v_user;
  else
    update public.profiles set extra_credits = extra_credits + v_amount where id = v_user;
  end if;
end;
$$;

create or replace function public.lazy_weekly_reset(p_uid uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles
    set weekly_credits = 1000
    where id = p_uid
      and subscription_active = true
      and subscription_period_end is not null
      and now() > subscription_period_end;
end;
$$;

revoke all on function public.deduct_credit(uuid)      from public, anon, authenticated;
revoke all on function public.refund_credit(uuid)      from public, anon, authenticated;
revoke all on function public.lazy_weekly_reset(uuid)  from public, anon, authenticated;
-- only service role (used by Edge Functions / cron) may call these.
