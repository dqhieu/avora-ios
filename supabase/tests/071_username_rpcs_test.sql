begin;
select plan(7);

-- two users; profiles auto-created by trigger with generated usernames
insert into auth.users (id, email) values
  ('b1111111-1111-1111-1111-111111111111', 'r1@test.dev'),
  ('b2222222-2222-2222-2222-222222222222', 'r2@test.dev');

-- give user B a known username to collide against
update public.profiles set username = 'usertwo1'
  where id = 'b2222222-2222-2222-2222-222222222222';

-- act as user A
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"b1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- availability
select is(public.is_username_available('freshname1'), true,
  'unused valid name is available');
select is(public.is_username_available('usertwo1'), false,
  'name taken by another user is unavailable');
select is(public.is_username_available('AB'), false,
  'malformed candidate is unavailable');

-- set_username happy path
select is(public.set_username('userone1'), 'ok', 'valid change returns ok');

-- verify the write from a privileged role: authenticated has no base-table
-- SELECT grant on profiles in the local shadow db (relies on baseline default
-- privileges in the real environment). auth.uid() in the RPC calls reads from
-- request.jwt.claims, a local setting that survives the role change, so the
-- calls below still resolve to user A.
reset role;
select is(
  (select username from public.profiles
     where id = 'b1111111-1111-1111-1111-111111111111'),
  'userone1', 'username was updated for the caller');
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"b1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- set_username collision + invalid
select is(public.set_username('usertwo1'), 'taken',
  'name taken by another user returns taken');
select is(public.set_username('no'), 'invalid',
  'too-short name returns invalid');

select * from finish();
rollback;
