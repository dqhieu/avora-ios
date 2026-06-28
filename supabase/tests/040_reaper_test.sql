begin;
select plan(2);

insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555','e@test.dev');
update public.profiles set extra_credits = 25 where id='55555555-5555-5555-5555-555555555555';
insert into public.styles (id, name, prompt_template) values ('s1','S1','x');
insert into public.generations
  (id, user_id, style_id, status, charged_bucket, charged_amount, input_path, quality, created_at)
  values ('cccccccc-0000-0000-0000-000000000001',
          '55555555-5555-5555-5555-555555555555','s1','pending','extra',25,'in/x.png','medium',
          now() - interval '6 minutes');

select public.reap_orphans();

select is((select status from public.generations where id='cccccccc-0000-0000-0000-000000000001'),
          'failed', 'reaper fails orphaned pending row');
select is((select extra_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          50, 'reaper refunds the charged bucket');

select * from finish();
rollback;
