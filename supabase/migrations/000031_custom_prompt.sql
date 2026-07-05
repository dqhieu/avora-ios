-- Custom generations describe their style in free text instead of pointing at a
-- preset. style_id becomes nullable (FK kept: NULLs skip the FK check, so preset
-- jobs are still validated against styles(id)); custom_prompt carries the words.

alter table public.generations
  alter column style_id drop not null;

alter table public.generations
  add column custom_prompt text;

-- A job is EITHER preset (style_id, no custom_prompt) OR custom (custom_prompt,
-- no style_id) — never both, never neither.
alter table public.generations
  add constraint generations_style_xor_prompt check (
    (style_id is not null and custom_prompt is null) or
    (style_id is null and custom_prompt is not null)
  );

-- Adding a defaulted parameter creates a NEW overload rather than replacing, so
-- drop the old 4-arg function first to avoid an ambiguous call.
drop function if exists public.submit_generations_batch(uuid, text, text[], text);

create or replace function public.submit_generations_batch(
  p_uid uuid,
  p_style_id text,
  p_input_paths text[],
  p_quality text,
  p_custom_prompt text default null
)
returns uuid[]
language plpgsql
security definer set search_path = public
as $$
declare
  v_cost   int;
  v_count  int := coalesce(array_length(p_input_paths, 1), 0);
  v_needed int;
  v_weekly int;
  v_extra  int;
  v_path   text;
  v_bucket text;
  v_id     uuid;
  v_ids    uuid[] := '{}';
begin
  if v_count < 1 or v_count > 4 then
    raise exception 'bad_batch_size' using errcode = 'P0001';
  end if;

  if p_quality not in ('low', 'medium', 'high') then
    raise exception 'bad_quality' using errcode = 'P0001';
  end if;

  select case p_quality
           when 'low'    then cost_low
           when 'medium' then cost_medium
           when 'high'   then cost_high
         end
    into v_cost
    from public.credit_config;
  v_needed := v_count * v_cost;

  -- lock the profile so concurrent submits serialize on this row
  select weekly_credits, extra_credits into v_weekly, v_extra
    from public.profiles where id = p_uid for update;

  if v_weekly + v_extra < v_needed then
    raise exception 'insufficient_credits' using errcode = 'P0001';
  end if;

  foreach v_path in array p_input_paths loop
    if v_weekly >= v_cost then
      v_weekly := v_weekly - v_cost;
      v_bucket := 'weekly';
    else
      v_extra := v_extra - v_cost;
      v_bucket := 'extra';
    end if;

    insert into public.generations
      (user_id, style_id, custom_prompt, status, charged_bucket,
       charged_amount, input_path, quality)
      values (p_uid, p_style_id, p_custom_prompt, 'pending', v_bucket,
              v_cost, v_path, p_quality)
      returning id into v_id;

    perform public.pgmq_send('generations', jsonb_build_object('job_id', v_id));
    v_ids := array_append(v_ids, v_id);
  end loop;

  update public.profiles
    set weekly_credits = v_weekly, extra_credits = v_extra
    where id = p_uid;

  return v_ids;
end;
$$;

revoke all on function
  public.submit_generations_batch(uuid, text, text[], text, text)
  from public, anon, authenticated;
