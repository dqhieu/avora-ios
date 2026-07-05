begin;
select plan(14);

insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555','e@test.dev');
insert into public.styles (id, name, prompt_template) values ('bs1','BS1','x');
-- credit_config seeds cost_low=20, cost_medium=30, cost_high=120

-- LOW: 20/img. weekly 100, batch of 2 low = 40 -> weekly 60.
update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select is(
  array_length(
    submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
      array['55555555-5555-5555-5555-555555555555/a.png',
            '55555555-5555-5555-5555-555555555555/b.png'], 'low'), 1),
  2, 'low: returns 2 job ids');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          60, 'low: weekly 100 -> 60 (2 x 20)');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555'
               and charged_amount=20 and quality='low'),
          2, 'low: each row charged 20 and stored quality low');

-- MEDIUM: 30/img. reset weekly 100, batch of 2 medium = 60 -> weekly 40.
delete from public.generations where user_id='55555555-5555-5555-5555-555555555555';
update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select is(
  array_length(
    submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
      array['55555555-5555-5555-5555-555555555555/a.png',
            '55555555-5555-5555-5555-555555555555/b.png'], 'medium'), 1),
  2, 'medium: returns 2 job ids');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          40, 'medium: weekly 100 -> 40 (2 x 30)');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555'
               and charged_amount=30 and quality='medium'),
          2, 'medium: each row charged 30 and stored quality medium');

-- HIGH: 120/img. reset weekly 120, batch of 1 high = 120 -> weekly 0.
delete from public.generations where user_id='55555555-5555-5555-5555-555555555555';
update public.profiles set weekly_credits = 120, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select is(
  array_length(
    submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
      array['55555555-5555-5555-5555-555555555555/a.png'], 'high'), 1),
  1, 'high: returns 1 job id');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          0, 'high: weekly 120 -> 0 (1 x 120)');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555'
               and charged_amount=120 and quality='high'),
          1, 'high: row charged 120 and stored quality high');

-- STRADDLE at medium: weekly 30 + extra 30, batch of 2 medium = 60 -> one weekly, one extra.
delete from public.generations where user_id='55555555-5555-5555-5555-555555555555';
update public.profiles set weekly_credits = 30, extra_credits = 30
  where id = '55555555-5555-5555-5555-555555555555';
do $$ begin
  perform submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
    array['55555555-5555-5555-5555-555555555555/a.png',
          '55555555-5555-5555-5555-555555555555/b.png'], 'medium');
end $$;
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_bucket='weekly'),
          1, 'straddle: one row charged to weekly');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_bucket='extra'),
          1, 'straddle: one row charged to extra');

-- BAD QUALITY: raises before any credit math (fires even with 0 credits).
select throws_ok(
  $$ select submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
       array['55555555-5555-5555-5555-555555555555/c.png'], 'ultra') $$,
  'P0001', 'bad_quality', 'unknown quality raises bad_quality');

-- INSUFFICIENT: high needs 120, only 50 available -> raises and deducts nothing.
delete from public.generations where user_id='55555555-5555-5555-5555-555555555555';
update public.profiles set weekly_credits = 50, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$ select submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
       array['55555555-5555-5555-5555-555555555555/d.png'], 'high') $$,
  'P0001', 'insufficient_credits', 'high raises when total < needed');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          50, 'weekly untouched after failed high batch (all-or-nothing)');

select * from finish();
rollback;
