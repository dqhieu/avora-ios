-- Reschedule the worker pump to read the project URL + service-role key from
-- Supabase Vault. Hosted Supabase does not permit `alter database ... set` for
-- custom GUCs (the postgres role is not a superuser), so the original
-- current_setting('app.*') approach from 000010 cannot be configured in the
-- cloud. Vault is the supported mechanism for cron-driven pg_net calls.
--
-- Required secrets (create once via the SQL editor / vault.create_secret):
--   project_url       e.g. https://<ref>.supabase.co/functions/v1
--   service_role_key  the project's service_role key
-- The cron body no-ops until both secrets exist.

-- Drop the GUC-based worker pump from 000010 if present.
select cron.unschedule('avora-worker')
  where exists (select 1 from cron.job where jobname = 'avora-worker');

-- Recreate it reading from Vault. The body is stored as text and only evaluated
-- when the job fires, so this applies cleanly even where vault has no secrets yet.
select cron.schedule(
  'avora-worker',
  '* * * * *',
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/process-queue',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'),
    body    := '{}'::jsonb
  )
  where exists (select 1 from vault.decrypted_secrets where name = 'project_url');
  $$
);
