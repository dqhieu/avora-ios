begin;
select plan(10);

insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444','d@test.dev');
-- profile auto-created with extra=50 (from config), weekly=0
update public.profiles set weekly_credits = 20
  where id = '44444444-4444-4444-4444-444444444444';
insert into public.styles (id, name, prompt_template) values ('s1','S1','x');

-- weekly is spent first; cost is 20 (read from credit_config)
select is(deduct_credit('44444444-4444-4444-4444-444444444444'), 'weekly', 'charges weekly first');
select is((select weekly_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          0, 'weekly now 0');

-- next charge falls to extra
select is(deduct_credit('44444444-4444-4444-4444-444444444444'), 'extra', 'falls back to extra');
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          30, 'extra now 30 (was 50, charged 20)');

-- refund is idempotent and returns the stored charged_amount to the charged bucket
insert into public.generations (id, user_id, style_id, status, charged_bucket, charged_amount, input_path, quality)
  values ('bbbbbbbb-0000-0000-0000-000000000001',
          '44444444-4444-4444-4444-444444444444','s1','pending','extra',20,'in/x.png','medium');
select refund_credit('bbbbbbbb-0000-0000-0000-000000000001');
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          50, 'refund returns 20 to extra');
select refund_credit('bbbbbbbb-0000-0000-0000-000000000001'); -- second call: no-op
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          50, 'refund is idempotent (still 50)');

-- insufficient credits raises
update public.profiles set weekly_credits = 0, extra_credits = 0
  where id = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'P0001', 'insufficient_credits', 'raises when no bucket has >= 20');

-- exactly-one semantics: with weekly=20, two deducts -> one ok, one raises
update public.profiles set weekly_credits = 20, extra_credits = 0
  where id = '44444444-4444-4444-4444-444444444444';
select lives_ok($$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'first deduct succeeds');
select throws_ok($$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'P0001', 'insufficient_credits', 'second deduct on drained account raises');

-- cost is read live from config: change it and the next deduct uses the new value
update public.credit_config set generation_cost = 10;
update public.profiles set weekly_credits = 10, extra_credits = 0
  where id = '44444444-4444-4444-4444-444444444444';
select is(deduct_credit('44444444-4444-4444-4444-444444444444'), 'weekly',
  'deduct uses the updated config cost (10)');

select * from finish();
rollback;
