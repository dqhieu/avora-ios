begin;
select plan(2);

insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444','d@test.dev');
-- profile auto-created with extra=50 (from config signup_extra), weekly=0
insert into public.styles (id, name, prompt_template) values ('s1','S1','x');

-- refund returns the stored charged_amount to the charged bucket
insert into public.generations (id, user_id, style_id, status, charged_bucket, charged_amount, input_path, quality)
  values ('bbbbbbbb-0000-0000-0000-000000000001',
          '44444444-4444-4444-4444-444444444444','s1','pending','extra',20,'in/x.png','medium');
select refund_credit('bbbbbbbb-0000-0000-0000-000000000001');
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          70, 'refund returns 20 to extra (was 50)');
select refund_credit('bbbbbbbb-0000-0000-0000-000000000001'); -- second call: no-op
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          70, 'refund is idempotent (still 70)');

select * from finish();
rollback;
