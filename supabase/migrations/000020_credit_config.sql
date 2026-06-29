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
