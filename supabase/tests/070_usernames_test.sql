begin;
select plan(8);

-- schema
select has_column('public', 'profiles', 'username', 'username column exists');
select col_type_is('public', 'profiles', 'username', 'text', 'username is text');
select has_index('public', 'profiles', 'profiles_username_key', 'username');

-- generator output is always valid
select matches(public.generate_username(),
  '^[a-z0-9_]{3,20}$', 'generate_username matches format');
select matches(public.generate_username(),
  '[a-z]', 'generate_username contains a letter');

-- new user gets a username from the trigger
insert into auth.users (id, email)
  values ('a1111111-1111-1111-1111-111111111111', 'u1@test.dev');
select isnt(
  (select username from public.profiles
     where id = 'a1111111-1111-1111-1111-111111111111'),
  null, 'trigger assigns a username to new users');

-- unique index blocks duplicates
insert into auth.users (id, email)
  values ('a2222222-2222-2222-2222-222222222222', 'u2@test.dev');
update public.profiles set username = 'takenname1'
  where id = 'a1111111-1111-1111-1111-111111111111';
select throws_ok(
  $$ update public.profiles set username = 'takenname1'
       where id = 'a2222222-2222-2222-2222-222222222222' $$,
  '23505', null, 'duplicate username is rejected');

-- format CHECK rejects invalid values (uppercase)
select throws_ok(
  $$ update public.profiles set username = 'BadName'
       where id = 'a2222222-2222-2222-2222-222222222222' $$,
  '23514', null, 'invalid format is rejected by CHECK');

select * from finish();
rollback;
