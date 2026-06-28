create or replace function public.bump_daily_tokens(p_day date, p_tokens bigint)
returns void language sql security definer set search_path = public as $$
  insert into public.daily_spend (day, total_tokens, est_cost_usd)
  values (p_day, p_tokens, 0)
  on conflict (day) do update set total_tokens = public.daily_spend.total_tokens + p_tokens;
$$;
revoke all on function public.bump_daily_tokens(date,bigint) from public, anon, authenticated;
