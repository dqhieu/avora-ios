begin;
select plan(3);

insert into auth.users (id, email) values
  ('d1111111-1111-1111-1111-111111111111', 'd1@test.dev'),
  ('d2222222-2222-2222-2222-222222222222', 'd2@test.dev');
insert into public.styles (id, name, prompt_template) values ('ds1','Style 1','SECRET');

-- user D1 owns a shared creation; user D2 has liked it
insert into public.generations
  (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality,
   output_path, status, shared_at, like_count)
values
  ('daaaaaaa-0000-0000-0000-000000000001',
   'd1111111-1111-1111-1111-111111111111','ds1','extra',25,'in/a.png','medium',
   'out/a.png','completed', now(), 1);
insert into public.likes (user_id, generation_id) values
  ('d2222222-2222-2222-2222-222222222222',
   'daaaaaaa-0000-0000-0000-000000000001');

-- act as owner and delete the row (mirrors what the Edge Function does with
-- service role: a plain delete on generations)
delete from public.generations
  where id = 'daaaaaaa-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  0, 'generation row is gone');
select is(
  (select count(*)::int from public.likes
     where generation_id = 'daaaaaaa-0000-0000-0000-000000000001'),
  0, 'likes cascade-deleted with the generation');
select is(
  (select count(*)::int from public.community_feed
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  0, 'creation no longer appears in the community feed');

select * from finish();
rollback;
