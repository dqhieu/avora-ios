create or replace function public.refund_credit_direct(p_uid uuid, p_bucket text, p_amount int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_bucket = 'weekly' then
    update public.profiles set weekly_credits = weekly_credits + p_amount where id = p_uid;
  else
    update public.profiles set extra_credits = extra_credits + p_amount where id = p_uid;
  end if;
end; $$;

create or replace function public.pgmq_send(queue_name text, msg jsonb)
returns bigint language sql security definer set search_path = pgmq, public as $$
  select pgmq.send(queue_name, msg);
$$;

revoke all on function public.refund_credit_direct(uuid,text,int) from public, anon, authenticated;
revoke all on function public.pgmq_send(text,jsonb)              from public, anon, authenticated;
