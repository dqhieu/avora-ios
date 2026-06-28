-- Public wrapper RPCs so Edge Functions can call pgmq without exposing the pgmq schema via PostgREST.
-- (PostgREST only exposes: public, graphql_public — pgmq schema is not reachable via db.schema("pgmq").rpc(...))

create or replace function public.pgmq_read(queue_name text, vt integer, qty integer)
returns jsonb language sql security definer set search_path = pgmq, public as $$
  select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
  from pgmq.read(queue_name, vt, qty) r;
$$;

create or replace function public.pgmq_archive(queue_name text, msg_id bigint)
returns boolean language sql security definer set search_path = pgmq, public as $$
  select pgmq.archive(queue_name, msg_id);
$$;

revoke all on function public.pgmq_read(text,integer,integer)  from public, anon, authenticated;
revoke all on function public.pgmq_archive(text,bigint)        from public, anon, authenticated;
