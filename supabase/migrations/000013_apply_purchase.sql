-- Atomic ledger insert + credit grant for RevenueCat webhook events.
-- Ledger insert and the profile grant happen in the same transaction, so a
-- partial failure (insert ok, grant fails) is impossible: both roll back and
-- RevenueCat's retry re-attempts a clean slate (ledger row was never committed).

create or replace function public.apply_purchase(
  p_tx        text,
  p_uid       uuid,
  p_kind      text,         -- 'initial' | 'renewal' | 'extra_pack'
  p_weekly_set int,         -- credits to set for renewal/initial (ignored for extra_pack)
  p_extra_delta int,        -- credits to add for extra_pack (ignored for renewal/initial)
  p_period_end timestamptz  -- subscription_period_end for renewal/initial (ignored for extra_pack)
)
returns text                -- 'applied' | 'deduped'
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted boolean := false;
begin
  -- Attempt ledger insert; ON CONFLICT DO NOTHING leaves v_inserted false.
  insert into public.purchases(transaction_id, user_id, kind)
    values (p_tx, p_uid, p_kind)
    on conflict (transaction_id) do nothing;

  get diagnostics v_inserted = row_count;  -- 1 if newly inserted, 0 if duplicate

  if not v_inserted then
    return 'deduped';
  end if;

  -- Apply grant in the same transaction.
  if p_kind in ('renewal', 'initial') then
    update public.profiles
      set weekly_credits         = p_weekly_set,
          subscription_period_end = p_period_end,
          subscription_active    = true
      where id = p_uid;
  elsif p_kind = 'extra_pack' then
    update public.profiles
      set extra_credits = extra_credits + p_extra_delta
      where id = p_uid;
  end if;

  return 'applied';
end;
$$;

revoke all on function public.apply_purchase(text, uuid, text, int, int, timestamptz)
  from public, anon, authenticated;
-- Only service role (used by Edge Functions) may call this.
