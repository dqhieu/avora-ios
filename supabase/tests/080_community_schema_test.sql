begin;
select plan(5);

-- Schema existence — checked as the privileged role, so no RLS/grant is involved.
select has_table('public','likes','likes table exists');
select has_column('public','generations','shared_at','generations has shared_at');
select has_column('public','generations','like_count','generations has like_count');

-- Storage policy: a non-owner can read a SHARED output but not a private one.
-- NOTE: this reads storage.objects under the authenticated role. If it errors
-- with "permission denied" in the LOCAL shadow db, that is the same missing-
-- baseline-grant gap that makes 020_rls_test fail locally — it passes against the
-- deployed DB / CI. Do NOT "fix" it by granting; verify remotely.
insert into auth.users (id, email) values
  ('c1111111-1111-1111-1111-111111111111', 'c1@test.dev'),
  ('c2222222-2222-2222-2222-222222222222', 'c2@test.dev');
insert into public.styles (id, name, prompt_template) values ('cs1','Style 1','SECRET');
insert into public.generations
  (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality,
   output_path, status, shared_at)
values
  ('caaaaaaa-0000-0000-0000-000000000001',
   'c1111111-1111-1111-1111-111111111111','cs1','extra',25,'in/a.png','medium',
   'c1111111-1111-1111-1111-111111111111/shared.png','completed', now()),
  ('caaaaaaa-0000-0000-0000-000000000002',
   'c1111111-1111-1111-1111-111111111111','cs1','extra',25,'in/b.png','medium',
   'c1111111-1111-1111-1111-111111111111/private.png','completed', null);
insert into storage.objects (bucket_id, name, owner) values
  ('outputs','c1111111-1111-1111-1111-111111111111/shared.png',
   'c1111111-1111-1111-1111-111111111111'),
  ('outputs','c1111111-1111-1111-1111-111111111111/private.png',
   'c1111111-1111-1111-1111-111111111111');

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"c2222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::int from storage.objects
     where name = 'c1111111-1111-1111-1111-111111111111/shared.png'),
  1, 'non-owner can read a shared output object');

select is(
  (select count(*)::int from storage.objects
     where name = 'c1111111-1111-1111-1111-111111111111/private.png'),
  0, 'non-owner cannot read a private (unshared) output object');

select * from finish();
rollback;
