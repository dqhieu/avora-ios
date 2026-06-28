begin;
select plan(6);

-- seed two users + their data as superuser
-- (profiles auto-created by trigger)
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');
insert into public.styles (id, name, prompt_template) values ('s1','Style 1','SECRET');
insert into public.generations (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          '11111111-1111-1111-1111-111111111111','s1','extra',25,'in/a.png','medium'),
         ('bbbbbbbb-0000-0000-0000-000000000002',
          '22222222-2222-2222-2222-222222222222','s1','extra',30,'in/b.png','medium');

-- act as user A
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select count(*)::int from public.generations),
  1, 'user A sees only their own generation');

select is(
  (select count(*)::int from public.generations
     where user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'user A cannot see user B generations');

select is(
  (select count(*)::int from public.styles_public where id = 's1'),
  1, 'user A can read styles_public');

select throws_ok(
  $$ select prompt_template from public.styles where id = 's1' $$,
  '42501', null, 'user A cannot read prompt_template from base styles');

select throws_ok(
  $$ select default_size from public.styles where id = 's1' $$,
  '42501', null, 'user A cannot read default_size from base styles');

select is(
  (select count(*)::int from public.profiles),
  1, 'user A sees only their own profile even though two profiles exist');

select * from finish();
rollback;
