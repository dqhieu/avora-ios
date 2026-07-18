-- Default-quality generations now cost 10 credits (was 20).
-- Also retires the flat generation_cost: per-quality pricing (cost_low/medium/high,
-- migration 000027) fully superseded it. Its only reader, deduct_credit, has no
-- callers — the live path is submit_generations_batch — so both are removed.

update public.credit_config set cost_low = 10;

drop function if exists public.deduct_credit(uuid);

alter table public.credit_config drop column generation_cost;
