begin;
select plan(7);

insert into auth.users (id, email) values
  ('e1111111-1111-1111-1111-111111111111', 'e1@test.dev'),
  ('e2222222-2222-2222-2222-222222222222', 'e2@test.dev');
insert into public.styles (id, name, prompt_template) values ('es1','Style 1','SECRET');

-- user A owns a shared creation with 0 likes
insert into public.generations
  (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality,
   output_path, status, shared_at, like_count)
values
  ('eaaaaaaa-0000-0000-0000-000000000001',
   'e1111111-1111-1111-1111-111111111111','es1','extra',25,'in/a.png','medium',
   'out/a.png','completed', now(), 0);

-- act as user B. RPCs are definer and return the resulting count, so those
-- assertions are robust. Table verification reads use `reset role` (privileged),
-- following the 071_username_rpcs_test pattern, to avoid the local grant gap.
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"e2222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(public.like_creation('eaaaaaaa-0000-0000-0000-000000000001'), 1,
  'first like returns count 1');
select is(public.like_creation('eaaaaaaa-0000-0000-0000-000000000001'), 1,
  'liking again is idempotent — count stays 1');

reset role;
select is(
  (select count(*)::int from public.likes
     where generation_id = 'eaaaaaaa-0000-0000-0000-000000000001'
       and user_id = 'e2222222-2222-2222-2222-222222222222'),
  1, 'exactly one like row exists for the user');

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"e2222222-2222-2222-2222-222222222222","role":"authenticated"}';
select is(public.unlike_creation('eaaaaaaa-0000-0000-0000-000000000001'), 0,
  'unlike returns count 0');
select is(public.unlike_creation('eaaaaaaa-0000-0000-0000-000000000001'), 0,
  'unliking again is idempotent and floored at 0');

-- likes persist across unshare/re-share: like (B), unshare + re-share (A)
select public.like_creation('eaaaaaaa-0000-0000-0000-000000000001');
set local request.jwt.claims =
  '{"sub":"e1111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.unshare_creation('eaaaaaaa-0000-0000-0000-000000000001');
select public.share_creation('eaaaaaaa-0000-0000-0000-000000000001');
reset role;
select is(
  (select like_count from public.generations
     where id = 'eaaaaaaa-0000-0000-0000-000000000001'),
  1, 'like_count survives unshare then re-share');
select is(
  (select count(*)::int from public.likes
     where generation_id = 'eaaaaaaa-0000-0000-0000-000000000001'),
  1, 'like row survives unshare then re-share');

select * from finish();
rollback;
