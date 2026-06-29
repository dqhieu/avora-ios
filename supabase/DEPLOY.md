# Deploy

## Secrets (Edge Functions)
supabase secrets set OPENAI_API_KEY=sk-...
supabase secrets set REVENUECAT_WEBHOOK_TOKEN=...

## Cron worker pump target (Supabase Vault)
# Hosted Supabase forbids `alter database ... set` for custom GUCs, so the
# worker pump reads its target from Vault (see migration 000014). Create these
# two secrets once via the SQL editor (run each exactly once):
select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'project_url');
select vault.create_secret('<service_role_key>', 'service_role_key');
# To change a value later, use vault.update_secret(<uuid>, '<new value>').

## Deploy functions
supabase functions deploy submit-generation get-generation list-generations process-queue revenuecat-webhook delete-account

## Apply migrations
supabase db push

## RevenueCat dashboard
- Webhook URL: https://<ref>.supabase.co/functions/v1/revenuecat-webhook
- Authorization header: Bearer <REVENUECAT_WEBHOOK_TOKEN>

## Worker concurrency
- Set WORKER_MAX_BATCH <= current OpenAI tier IPM (Tier 1=5, Tier 3=50).
- Set DAILY_TOKEN_CAP to the daily spend ceiling in tokens.
