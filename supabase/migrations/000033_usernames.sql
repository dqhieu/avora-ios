-- Unique, editable usernames. profiles has no client write policy (owner
-- read-only), so writes happen here (trigger/backfill) and via definer RPCs
-- (migration 000034). Only lowercase is allowed, so uniqueness is naturally
-- case-insensitive without citext.

alter table public.profiles add column username text;

create unique index profiles_username_key on public.profiles (username);

alter table public.profiles add constraint profiles_username_format
  check (username ~ '^[a-z0-9_]{3,20}$' and username ~ '[a-z]');

-- Word-based handle, e.g. "swiftpanda42". Retries on collision; after 10 tries
-- it widens the numeric suffix so the result stays <= 20 chars and terminates.
create or replace function public.generate_username()
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  adjectives text[] := array[
    'swift','clever','brave','calm','bright','bold','cosmic','crimson','dapper','eager',
    'fuzzy','gentle','happy','jolly','keen','lucky','mellow','nimble','plucky','quiet',
    'rapid','shiny','sunny','tidy','vivid','witty','zesty','amber','breezy','curious'];
  nouns text[] := array[
    'panda','otter','fox','hawk','lion','koala','tiger','falcon','badger','beaver',
    'cheetah','dolphin','eagle','gecko','heron','ibis','jaguar','lynx','marmot','newt',
    'osprey','puffin','quokka','raven','seal','toucan','urchin','viper','walrus','yak'];
  base text;
  candidate text;
  tries int := 0;
begin
  loop
    tries := tries + 1;
    base := adjectives[1 + floor(random() * array_length(adjectives, 1))::int]
         || nouns[1 + floor(random() * array_length(nouns, 1))::int];
    if tries < 10 then
      candidate := base || (10 + floor(random() * 90))::int::text;      -- 2 digits
    else
      candidate := base || (1000 + floor(random() * 9000))::int::text;  -- 4 digits, len <= 18
    end if;
    exit when not exists (select 1 from public.profiles where username = candidate);
  end loop;
  return candidate;
end;
$$;

-- New users are named the moment they sign up. Idempotent insert preserved.
-- extra_credits assignment from credit_config (introduced in 000020) is kept.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, extra_credits)
    values (new.id, public.generate_username(), (select signup_extra from public.credit_config))
    on conflict (id) do nothing;
  return new;
end;
$$;

-- One-time backfill for existing accounts. A single UPDATE would evaluate
-- generate_username() against the statement-start snapshot, so two null rows
-- could draw the same name and trip the unique index. Assign row-by-row so
-- each generated name is visible to the next iteration's uniqueness check.
do $$
declare
  r record;
begin
  for r in select id from public.profiles where username is null loop
    update public.profiles set username = public.generate_username() where id = r.id;
  end loop;
end $$;
