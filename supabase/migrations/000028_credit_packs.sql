-- One-time consumable credit packs. product_id → credits is the authoritative
-- mapping the RevenueCat webhook grants from and the app reads to display.
create table public.credit_packs (
  product_id text primary key,
  credits    int  not null,
  active     bool not null default true,
  sort_order int  not null default 0
);

insert into public.credit_packs (product_id, credits, sort_order) values
  ('com.hieudinh.Avora.credits500',  500,  0),
  ('com.hieudinh.Avora.credits1000', 1000, 1),
  ('com.hieudinh.Avora.credits2500', 2500, 2),
  ('com.hieudinh.Avora.credits4000', 4000, 3),
  ('com.hieudinh.Avora.credits6000', 6000, 4);

-- Client-readable (prices come from RevenueCat; only credit amounts live here).
alter table public.credit_packs enable row level security;
revoke all on public.credit_packs from authenticated, anon;
create policy credit_packs_read on public.credit_packs
  for select to authenticated, anon using (true);
grant select on public.credit_packs to authenticated, anon;

-- Raise the weekly grant. Renewal/initial and lazy_weekly_reset already read
-- this value, so subscribers land on 1,200 at their next renewal/reset.
update public.credit_config set weekly_amount = 1200;

-- apply_purchase gains an optional per-purchase credit amount for the
-- extra-pack branch. Unknown/missing amount falls back to config extra_pack.
drop function if exists public.apply_purchase(text, uuid, text, timestamptz);

create or replace function public.apply_purchase(
  p_tx         text,
  p_uid        uuid,
  p_kind       text,          -- 'initial' | 'renewal' | 'extra_pack'
  p_period_end timestamptz,   -- for renewal/initial (ignored for extra_pack)
  p_credits    int default null  -- credits to grant for extra_pack; null → config
)
returns text                  -- 'applied' | 'deduped'
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
      set extra_credits = extra_credits
        + coalesce(p_credits, (select extra_pack from public.credit_config))
      where id = p_uid;
  end if;

  return 'applied';
end;
$$;

revoke all on function public.apply_purchase(text, uuid, text, timestamptz, int)
  from public, anon, authenticated;
