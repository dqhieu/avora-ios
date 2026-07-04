begin;
select plan(6);

insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666','f@test.dev');
-- profile auto-created: extra=50 (config signup_extra), weekly=0

-- initial purchase sets weekly to config weekly_amount (1200) and activates
select is(apply_purchase('tx1','66666666-6666-6666-6666-666666666666','initial', now() + interval '7 days'),
          'applied', 'initial purchase applied');
select is((select weekly_credits from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          1200, 'weekly set to config weekly_amount (1200)');
select is((select subscription_active from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          true, 'subscription activated');

-- duplicate transaction is deduped (idempotent)
select is(apply_purchase('tx1','66666666-6666-6666-6666-666666666666','renewal', now() + interval '7 days'),
          'deduped', 'duplicate transaction id is deduped');

-- extra_pack adds config extra_pack (500) to extra_credits (was 50)
select is(apply_purchase('tx2','66666666-6666-6666-6666-666666666666','extra_pack', null),
          'applied', 'extra_pack applied');
select is((select extra_credits from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          550, 'extra increased by config extra_pack (50 + 500)');

select * from finish();
rollback;
