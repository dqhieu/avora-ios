-- Per-quality generation pricing. credit_config gains one column per quality
-- level; submit_generations_batch derives cost from the (validated) quality the
-- client chose instead of the flat generation_cost. Costs: low=20, medium=30, high=100.
-- generation_cost is left in place (still read by the single-image path).

alter table public.credit_config
  add column cost_low    int not null default 20,
  add column cost_medium int not null default 30,
  add column cost_high   int not null default 100;

-- Backfill the singleton row explicitly (defaults already cover it; explicit is clearer).
update public.credit_config set cost_low = 20, cost_medium = 30, cost_high = 100;

create or replace function public.submit_generations_batch(
  p_uid uuid,
  p_style_id text,
  p_input_paths text[],
  p_quality text
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
      (user_id, style_id, status, charged_bucket, charged_amount, input_path, quality)
      values (p_uid, p_style_id, 'pending', v_bucket, v_cost, v_path, p_quality)
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

revoke all on function public.submit_generations_batch(uuid, text, text[], text)
  from public, anon, authenticated;
-- only the service role (used by Edge Functions) may call this.
