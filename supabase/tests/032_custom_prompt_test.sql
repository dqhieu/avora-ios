begin;
select plan(8);

insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666','c@test.dev');
insert into public.styles (id, name, prompt_template) values ('cs1','CS1','x');
-- credit_config seeds cost_low=20

update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '66666666-6666-6666-6666-666666666666';

-- CUSTOM: null style_id + custom_prompt, charged like any low batch.
select is(
  array_length(
    submit_generations_batch('66666666-6666-6666-6666-666666666666', null,
      array['66666666-6666-6666-6666-666666666666/a.png',
            '66666666-6666-6666-6666-666666666666/b.png'],
      'low', 'make it a watercolor sunset'), 1),
  2, 'custom: returns 2 job ids');
select is((select weekly_credits from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          60, 'custom: weekly 100 -> 60 (2 x 20)');
select is((select count(*)::int from public.generations
             where user_id='66666666-6666-6666-6666-666666666666'
               and style_id is null
               and custom_prompt='make it a watercolor sunset'),
          2, 'custom: rows have null style_id and stored prompt');

-- PRESET regression: 4-arg call still resolves (p_custom_prompt defaults null).
delete from public.generations where user_id='66666666-6666-6666-6666-666666666666';
update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '66666666-6666-6666-6666-666666666666';
select is(
  array_length(
    submit_generations_batch('66666666-6666-6666-6666-666666666666', 'cs1',
      array['66666666-6666-6666-6666-666666666666/a.png'], 'low'), 1),
  1, 'preset: 4-arg call still works');
select is((select count(*)::int from public.generations
             where user_id='66666666-6666-6666-6666-666666666666'
               and style_id='cs1' and custom_prompt is null),
          1, 'preset: row has style_id and null custom_prompt');

-- XOR check rejects malformed rows (23514 = check_violation).
select throws_ok(
  $$ insert into public.generations
       (user_id, style_id, custom_prompt, status, charged_bucket, charged_amount, input_path, quality)
     values ('66666666-6666-6666-6666-666666666666','cs1','both','pending','weekly',20,'p','low') $$,
  '23514', null, 'XOR: rejects both style_id and custom_prompt set');
select throws_ok(
  $$ insert into public.generations
       (user_id, style_id, custom_prompt, status, charged_bucket, charged_amount, input_path, quality)
     values ('66666666-6666-6666-6666-666666666666',null,null,'pending','weekly',20,'p','low') $$,
  '23514', null, 'XOR: rejects neither set');

-- Old 4-arg overload must be gone (exactly one function of this name).
select is((select count(*)::int from pg_proc where proname = 'submit_generations_batch'),
          1, 'exactly one submit_generations_batch overload exists');

select * from finish();
rollback;
