begin;
select plan(6);

select has_table('public', 'credit_packs', 'credit_packs exists');
select table_privs_are('public', 'credit_packs', 'anon', ARRAY['SELECT'], 'anon can read credit_packs');
select is((select count(*)::int from public.credit_packs), 5, 'five packs seeded');
select is((select credits from public.credit_packs where product_id='com.hieudinh.Avora.credits6000'),
          6000, 'credits6000 pack maps to 6000 credits');

-- variable extra-pack grant: explicit p_credits overrides the config default
insert into auth.users (id, email) values ('77777777-7777-7777-7777-777777777777','g@test.dev');
select is(apply_purchase('tx-var','77777777-7777-7777-7777-777777777777','extra_pack', null, 2500),
          'applied', 'extra_pack with explicit credits applied');
select is((select extra_credits from public.profiles where id='77777777-7777-7777-7777-777777777777'),
          2550, 'extra_pack grants explicit p_credits (50 starter + 2500)');

select * from finish();
rollback;
