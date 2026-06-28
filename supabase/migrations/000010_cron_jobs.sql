-- Reap orphaned pending generations older than 5 minutes.
-- Calls refund_credit() which atomically flips pending->failed and refunds;
-- we only set error_code beforehand so the update inside refund_credit()
-- can still find the row with status='pending'.
create or replace function public.reap_orphans()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select id from public.generations
    where status = 'pending' and created_at < now() - interval '5 minutes'
    for update skip locked
  loop
    update public.generations set error_code = coalesce(error_code,'timeout') where id = r.id;
    perform public.refund_credit(r.id);   -- flips pending->failed + refunds, idempotent
  end loop;
end; $$;
revoke all on function public.reap_orphans() from public, anon, authenticated;

-- Reaper schedule: fail + refund stuck generations every minute.
select cron.schedule('avora-reaper', '* * * * *', $$ select public.reap_orphans(); $$);

-- Worker-pump schedule: invoke the deployed process-queue Edge Function every minute.
-- Uses current_setting(..., true) (missing-ok form) so that locally — where
-- app.functions_url and app.service_role_key are not configured — the HTTP call
-- resolves to a NULL URL and is silently skipped rather than raising an error.
-- These GUCs are set via `alter database ... set ...` at deploy time.
select cron.schedule(
  'avora-worker',
  '* * * * *',
  $$
  select net.http_post(
    url     := current_setting('app.functions_url', true) || '/process-queue',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.service_role_key', true),
      'Content-Type', 'application/json'),
    body    := '{}'::jsonb
  ) where current_setting('app.functions_url', true) is not null;
  $$
);
