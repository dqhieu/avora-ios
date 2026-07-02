begin;
select plan(9);

insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555','e@test.dev');
-- profile auto-created; set a balance that forces a batch to straddle both buckets
update public.profiles set weekly_credits = 30, extra_credits = 20
  where id = '55555555-5555-5555-5555-555555555555';
insert into public.styles (id, name, prompt_template) values ('bs1','BS1','x');
-- credit_config.generation_cost defaults to 20

-- batch of 2: needed 40; weekly(30) covers one row, extra(20) covers the other
select is(
  array_length(
    submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
      array['55555555-5555-5555-5555-555555555555/a.png',
            '55555555-5555-5555-5555-555555555555/b.png'], 'medium'), 1),
  2, 'returns 2 job ids');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          10, 'weekly 30 -> 10 (one row charged weekly)');
select is((select extra_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          0, 'extra 20 -> 0 (one row charged extra)');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555'),
          2, 'two generation rows inserted');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_bucket='weekly'),
          1, 'one row charged to weekly bucket');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_bucket='extra'),
          1, 'one row charged to extra bucket');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_amount=20),
          2, 'each row charged the config cost (20)');

-- insufficient: total < needed raises P0001 and deducts nothing
update public.profiles set weekly_credits = 10, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$ select submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
       array['55555555-5555-5555-5555-555555555555/c.png'], 'medium') $$,
  'P0001', 'insufficient_credits', 'raises when total < needed');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          10, 'weekly untouched after failed batch (all-or-nothing)');

select * from finish();
rollback;
