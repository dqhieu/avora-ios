begin;
select plan(14);

select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'styles', 'styles exists');
select has_table('public', 'generations', 'generations exists');
select has_table('public', 'purchases', 'purchases exists');
select has_table('public', 'daily_spend', 'daily_spend exists');

select col_default_is('public', 'profiles', 'extra_credits', '50', 'starter extra default still 50 (changed in next task)');
select col_has_check('public', 'generations', 'status', 'status is constrained');
select has_column('public', 'generations', 'charged_amount', 'charged_amount column exists');
select col_is_pk('public', 'purchases', 'transaction_id', 'purchases pk is transaction_id');

-- new-user trigger grants 50 starter credits from config, exactly once
insert into auth.users (id, email)
  values ('33333333-3333-3333-3333-333333333333','c@test.dev');
select is(
  (select extra_credits from public.profiles
     where id = '33333333-3333-3333-3333-333333333333'),
  50, 'trigger creates profile with 50 starter credits from config');

-- credit_config is the singleton source of truth, readable by clients
select has_table('public', 'credit_config', 'credit_config exists');
select col_is_pk('public', 'credit_config', 'id', 'credit_config pk is id (singleton)');
select is((select count(*)::int from public.credit_config), 1, 'credit_config has exactly one row');
select table_privs_are('public', 'credit_config', 'anon', ARRAY['SELECT'], 'anon can read credit_config');

select * from finish();
rollback;
