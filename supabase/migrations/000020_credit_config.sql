-- Single source of truth for credit economics. One row; all backend credit
-- math reads from it, and the mobile app fetches it (with baked-in fallbacks).

create table public.credit_config (
  id              boolean primary key default true check (id),  -- singleton row
  weekly_amount   int not null,   -- weekly bucket granted on subscription/renewal
  signup_extra    int not null,   -- free extra credits granted at signup
  generation_cost int not null,   -- credits deducted per generation
  extra_pack      int not null    -- credits added per extra-pack purchase
);

insert into public.credit_config (weekly_amount, signup_extra, generation_cost, extra_pack)
  values (1000, 50, 20, 500);

-- These four numbers are user-facing economics, so clients may read them.
-- Revoke the broad default grants first so clients get SELECT only (writes are
-- also blocked by RLS having no write policy).
alter table public.credit_config enable row level security;
revoke all on public.credit_config from authenticated, anon;
create policy credit_config_read on public.credit_config
  for select to authenticated, anon using (true);
grant select on public.credit_config to authenticated, anon;

-- Starter grant now comes from config; the column default is no longer the source.
alter table public.profiles alter column extra_credits set default 0;

-- New users get their starter extra credits from config.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, extra_credits)
    values (new.id, (select signup_extra from public.credit_config))
    on conflict (id) do nothing;
  return new;
end;
$$;

-- Per-generation cost read from config.
create or replace function public.deduct_credit(p_uid uuid)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_cost int;
  v_bucket text;
begin
  select generation_cost into v_cost from public.credit_config;

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

-- Weekly reset amount read from config.
create or replace function public.lazy_weekly_reset(p_uid uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles
    set weekly_credits = (select weekly_amount from public.credit_config)
    where id = p_uid
      and subscription_active = true
      and subscription_period_end is not null
      and now() > subscription_period_end;
end;
$$;

-- apply_purchase now reads grant amounts from config; the webhook no longer
-- passes them. Drop the old wider signature first (create-or-replace cannot
-- change a function's parameter list).
drop function if exists public.apply_purchase(text, uuid, text, int, int, timestamptz);

create or replace function public.apply_purchase(
  p_tx         text,
  p_uid        uuid,
  p_kind       text,         -- 'initial' | 'renewal' | 'extra_pack'
  p_period_end timestamptz   -- subscription_period_end for renewal/initial (ignored for extra_pack)
)
returns text                 -- 'applied' | 'deduped'
language plpgsql
security definer set search_path = public
as $$
declare
  v_inserted boolean := false;
begin
  insert into public.purchases(transaction_id, user_id, kind)
    values (p_tx, p_uid, p_kind)
    on conflict (transaction_id) do nothing;

  get diagnostics v_inserted = row_count;

  if not v_inserted then
    return 'deduped';
  end if;

  if p_kind in ('renewal', 'initial') then
    update public.profiles
      set weekly_credits          = (select weekly_amount from public.credit_config),
          subscription_period_end = p_period_end,
          subscription_active     = true
      where id = p_uid;
  elsif p_kind = 'extra_pack' then
    update public.profiles
      set extra_credits = extra_credits + (select extra_pack from public.credit_config)
      where id = p_uid;
  end if;

  return 'applied';
end;
$$;

revoke all on function public.apply_purchase(text, uuid, text, timestamptz)
  from public, anon, authenticated;
-- Only the service role (used by the RevenueCat webhook) may call this.
