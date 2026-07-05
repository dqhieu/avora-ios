begin;
select plan(7);

insert into auth.users (id, email) values
  ('d1111111-1111-1111-1111-111111111111', 'd1@test.dev'),
  ('d2222222-2222-2222-2222-222222222222', 'd2@test.dev');
insert into public.styles (id, name, prompt_template) values ('ds1','Style 1','SECRET');
update public.profiles set username = 'authorone'
  where id = 'd1111111-1111-1111-1111-111111111111';

-- user A: one shared, one private generation
insert into public.generations
  (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality,
   output_path, status, shared_at, like_count)
values
  ('daaaaaaa-0000-0000-0000-000000000001',
   'd1111111-1111-1111-1111-111111111111','ds1','extra',25,'in/a.png','medium',
   'out/a.png','completed', now(), 3),
  ('daaaaaaa-0000-0000-0000-000000000002',
   'd1111111-1111-1111-1111-111111111111','ds1','extra',25,'in/b.png','medium',
   'out/b.png','completed', null, 0);

-- user B likes A's shared creation (seed via privileged role)
insert into public.likes (user_id, generation_id) values
  ('d2222222-2222-2222-2222-222222222222','daaaaaaa-0000-0000-0000-000000000001');

-- act as user B. Feed reads go through the definer view, which is explicitly
-- granted to authenticated and reads its base tables as the view owner, so it is
-- robust against the local baseline-grant gap. Verification reads on generations
-- use `reset role` (privileged), following the 071_username_rpcs_test pattern.
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"d2222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::int from public.community_feed), 1,
  'feed shows only shared rows');
select is(
  (select username from public.community_feed
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  'authorone', 'feed exposes the author username');
select is(
  (select liked_by_me from public.community_feed
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  true, 'liked_by_me is true for a creation user B liked');

-- user B cannot share a creation they do not own (no-op update)
select public.share_creation('daaaaaaa-0000-0000-0000-000000000002');
reset role;
select is(
  (select shared_at from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000002'),
  null, 'share_creation is a no-op for a non-owner');

-- owner shares that creation
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"d1111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.share_creation('daaaaaaa-0000-0000-0000-000000000002');
reset role;
select isnt(
  (select shared_at from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000002'),
  null, 'owner can share their own creation');

-- owner unshares the first creation; likes are preserved
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"d1111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.unshare_creation('daaaaaaa-0000-0000-0000-000000000001');
reset role;
select is(
  (select shared_at from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  null, 'owner can unshare their own creation');
select is(
  (select like_count from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  3, 'unshare preserves like_count');

select * from finish();
rollback;
