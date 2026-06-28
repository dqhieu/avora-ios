# Deploy

## Secrets (Edge Functions)
supabase secrets set OPENAI_API_KEY=sk-...
supabase secrets set REVENUECAT_WEBHOOK_TOKEN=...

## Database settings for cron worker pump (pg_net target)
alter database postgres set "app.functions_url"   = 'https://<ref>.supabase.co/functions/v1';
alter database postgres set "app.service_role_key" = '<service_role_key>';

## Deploy functions
supabase functions deploy submit-generation get-generation list-generations process-queue revenuecat-webhook

## Apply migrations
supabase db push

## RevenueCat dashboard
- Webhook URL: https://<ref>.supabase.co/functions/v1/revenuecat-webhook
- Authorization header: Bearer <REVENUECAT_WEBHOOK_TOKEN>

## Worker concurrency
- Set WORKER_MAX_BATCH <= current OpenAI tier IPM (Tier 1=5, Tier 3=50).
- Set DAILY_TOKEN_CAP to the daily spend ceiling in tokens.
