create table public.profiles (
  id                      uuid primary key references auth.users(id) on delete cascade,
  created_at              timestamptz not null default now(),
  weekly_credits          int not null default 0,
  extra_credits           int not null default 50,
  subscription_period_end timestamptz,
  subscription_active     boolean not null default false
);

create table public.styles (
  id                text primary key,
  name              text not null,
  prompt_template   text not null,
  sample_image_path text,
  default_size      text not null default 'auto',
  default_quality   text not null default 'medium',
  active            boolean not null default true
);

create table public.generations (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  style_id       text not null references public.styles(id),
  status         text not null default 'pending'
                   check (status in ('pending','completed','failed')),
  charged_bucket text not null check (charged_bucket in ('weekly','extra')),
  charged_amount int not null,
  input_path     text not null,
  output_path    text,
  size           text,
  quality        text not null,
  input_tokens   int,
  output_tokens  int,
  error_code     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz
);

create index generations_user_created_idx on public.generations (user_id, created_at desc);
create index generations_pending_idx on public.generations (status) where status = 'pending';

create table public.purchases (
  transaction_id text primary key,
  user_id        uuid not null references auth.users(id),
  kind           text not null check (kind in ('renewal','extra_pack','initial')),
  processed_at   timestamptz not null default now()
);

create table public.daily_spend (
  day          date primary key,
  total_tokens bigint not null default 0,
  est_cost_usd numeric not null default 0
);
