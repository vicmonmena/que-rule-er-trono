begin;

-- Run as postgres in the Supabase SQL Editor.
create role trono_rpc_owner
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
grant trono_rpc_owner to postgres;

create schema trono_private;
revoke all on schema trono_private from public, anon, authenticated, service_role;

create collation trono_private.names_es (provider = icu, locale = 'es');

create table trono_private.game_settings (
  singleton boolean primary key default true check (singleton),
  start_date date not null
);
insert into trono_private.game_settings (start_date)
values ((pg_catalog.clock_timestamp() at time zone 'Europe/Madrid')::date);

create table trono_private.participants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  display_name text not null check (char_length(display_name) between 1 and 60),
  normalized_name text collate pg_catalog."C" not null unique,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  active boolean not null default true
);

create table trono_private.registrations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  participant_id uuid not null references trono_private.participants (id),
  office_date date not null check (extract(isodow from office_date) between 1 and 5),
  status text not null check (status in ('registered', 'cancelled', 'invalidated')),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  unique (participant_id, office_date)
);
create index registrations_active_by_date
  on trono_private.registrations (office_date, participant_id) where status = 'registered';

create table trono_private.draws (
  office_date date primary key check (extract(isodow from office_date) between 1 and 5),
  status text not null check (status in ('winner', 'no_participants')),
  winner_participant_id uuid references trono_private.participants (id),
  exceptional boolean not null default false,
  eligible_count integer not null check (eligible_count >= 0),
  drawn_at timestamptz not null,
  check (
    (status = 'winner' and winner_participant_id is not null and exceptional = (eligible_count = 0))
    or (status = 'no_participants' and winner_participant_id is null and not exceptional and eligible_count = 0)
  )
);
create index draws_by_winner_week on trono_private.draws (winner_participant_id, office_date)
  where winner_participant_id is not null;

create table trono_private.blocked_days (
  date date primary key check (extract(isodow from date) between 1 and 5),
  reason text,
  created_at timestamptz not null default pg_catalog.clock_timestamp()
);

alter table trono_private.game_settings enable row level security;
alter table trono_private.participants enable row level security;
alter table trono_private.registrations enable row level security;
alter table trono_private.draws enable row level security;
alter table trono_private.blocked_days enable row level security;

revoke all on all tables in schema trono_private from public, anon, authenticated, service_role;

grant usage on schema trono_private to trono_rpc_owner;
grant select on trono_private.game_settings, trono_private.participants,
  trono_private.registrations, trono_private.draws to trono_rpc_owner;
grant select (date) on trono_private.blocked_days to trono_rpc_owner;
grant insert (display_name, normalized_name) on trono_private.participants to trono_rpc_owner;
grant insert (participant_id, office_date, status, updated_at), update (status, updated_at)
  on trono_private.registrations to trono_rpc_owner;
grant insert (office_date, status, winner_participant_id, exceptional, eligible_count, drawn_at)
  on trono_private.draws to trono_rpc_owner;

create policy rpc_read_settings on trono_private.game_settings for select to trono_rpc_owner using (true);
create policy rpc_read_participants on trono_private.participants for select to trono_rpc_owner using (true);
create policy rpc_insert_participants on trono_private.participants for insert to trono_rpc_owner with check (true);
create policy rpc_read_registrations on trono_private.registrations for select to trono_rpc_owner using (true);
create policy rpc_insert_registrations on trono_private.registrations for insert to trono_rpc_owner
  with check (status = 'registered');
create policy rpc_update_registrations on trono_private.registrations for update to trono_rpc_owner
  using (true) with check (status in ('registered', 'cancelled'));
create policy rpc_read_draws on trono_private.draws for select to trono_rpc_owner using (true);
create policy rpc_insert_draws on trono_private.draws for insert to trono_rpc_owner with check (true);
create policy rpc_read_blocked_days on trono_private.blocked_days for select to trono_rpc_owner using (true);

create function trono_private.closes_at(p_date date)
returns timestamptz
language sql immutable strict
set search_path = ''
as $$
  select (p_date - 1 + time '22:00') at time zone 'Europe/Madrid';
$$;

create function trono_private.next_office_date(p_now timestamptz)
returns date
language plpgsql stable strict
set search_path = ''
as $$
declare
  v_date date := (p_now at time zone 'Europe/Madrid')::date + 1;
begin
  while extract(isodow from v_date) > 5
      or trono_private.closes_at(v_date) <= p_now
      or exists (select 1 from trono_private.blocked_days as b where b.date = v_date)
  loop
    v_date := v_date + 1;
  end loop;
  return v_date;
end;
$$;

-- The caller holds the game lock and supplies a server timestamp.
create function trono_private.resolve_pending(p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_start date;
  v_last date := (p_now at time zone 'Europe/Madrid')::date + 1;
  v_date date;
  v_monday date;
  v_registered uuid[];
  v_eligible uuid[];
  v_pool uuid[];
  v_count integer;
  v_pick bigint;
  v_eligible_count integer;
begin
  if trono_private.closes_at(v_last) > p_now then
    v_last := v_last - 1;
  end if;
  select s.start_date into strict v_start from trono_private.game_settings as s;

  for v_date in
    select v_start + day_offset
    from pg_catalog.generate_series(0, v_last - v_start) as days(day_offset)
    where extract(isodow from v_start + day_offset) between 1 and 5
      and not exists (select 1 from trono_private.blocked_days as b where b.date = v_start + day_offset)
      and not exists (select 1 from trono_private.draws as d where d.office_date = v_start + day_offset)
    order by day_offset
  loop
    v_monday := v_date - (extract(isodow from v_date)::integer - 1);
    select
      array_agg(c.participant_id order by c.participant_id),
      array_agg(c.participant_id order by c.participant_id) filter (where c.eligible)
    into v_registered, v_eligible
    from (
      select r.participant_id,
        count(d.office_date) filter (where d.office_date >= v_monday)
          < case when count(d.office_date) filter (where d.office_date < v_monday) >= 2
              then 1 else 2 end as eligible
      from trono_private.registrations as r
      join trono_private.participants as p on p.id = r.participant_id and p.active
      left join trono_private.draws as d on d.winner_participant_id = r.participant_id
        and d.office_date >= v_monday - 7 and d.office_date < v_date
      where r.office_date = v_date and r.status = 'registered'
      group by r.participant_id
    ) as c;

    if v_registered is null then
      insert into trono_private.draws (office_date, status, eligible_count, drawn_at)
      values (v_date, 'no_participants', 0, p_now);
      continue;
    end if;

    v_eligible_count := coalesce(cardinality(v_eligible), 0);
    v_pool := coalesce(v_eligible, v_registered);
    v_count := cardinality(v_pool);
    v_pick := 0;
    if v_count > 1 then
      -- The first 32 bits of a random UUID are uniform. Reject any partial bucket.
      loop
        v_pick := ('x' || left(pg_catalog.gen_random_uuid()::text, 8))::bit(32)::bigint;
        exit when v_pick < 4294967296 - (4294967296 % v_count);
      end loop;
    end if;

    insert into trono_private.draws
      (office_date, status, winner_participant_id, exceptional, eligible_count, drawn_at)
    values (v_date, 'winner', v_pool[1 + (v_pick % v_count)::integer], v_eligible_count = 0, v_eligible_count, p_now);
  end loop;
end;
$$;

create function trono_private.snapshot(p_now timestamptz)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'serverNow', to_char(p_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'startDate', s.start_date,
    'nextDate', next_day.date,
    'closesAt', trono_private.closes_at(next_day.date),
    'blockedDays', coalesce((
      select jsonb_agg(b.date order by b.date) from trono_private.blocked_days as b
    ), '[]'::jsonb),
    'attendees', coalesce((
      select jsonb_agg(
        jsonb_build_object('name', p.display_name, 'normalizedName', p.normalized_name)
        order by p.normalized_name
      )
      from trono_private.registrations as r
      join trono_private.participants as p on p.id = r.participant_id and p.active
      where r.office_date = next_day.date and r.status = 'registered'
    ), '[]'::jsonb),
    'draws', coalesce((
      select jsonb_agg(
        jsonb_build_object('officeDate', d.office_date, 'status', d.status,
          'winnerName', p.display_name, 'exceptional', d.exceptional)
        order by d.office_date desc
      )
      from trono_private.draws as d
      left join trono_private.participants as p on p.id = d.winner_participant_id
    ), '[]'::jsonb)
  )
  from trono_private.game_settings as s
  cross join lateral (select trono_private.next_office_date(p_now) as date) as next_day;
$$;

create function trono_private.set_attendance(p_name text, p_expected_date date, p_attending boolean)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_now timestamptz;
  v_date date;
  v_name text;
  v_normalized text;
  v_participant trono_private.participants%rowtype;
begin
  if p_name is null or octet_length(p_name) > 4096 then
    raise exception using errcode = '22023', message = 'Escribe un nombre de entre 1 y 60 caracteres.';
  end if;
  v_name := normalize(btrim(regexp_replace(p_name,
    U&'[\0009-\000D\0020\00A0\1680\2000-\200A\2028\2029\202F\205F\3000\FEFF]+', ' ', 'g')), NFC);
  if char_length(v_name) not between 1 and 60 or v_name ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'Escribe un nombre válido de entre 1 y 60 caracteres.';
  end if;
  v_normalized := normalize(lower(v_name collate trono_private.names_es), NFC);

  perform pg_catalog.pg_advisory_xact_lock(1613490020, 1);
  v_now := pg_catalog.clock_timestamp();
  v_date := trono_private.next_office_date(v_now);
  if p_expected_date is distinct from v_date then
    raise exception using errcode = '22023', message = 'La inscripción para ese día ya no está abierta.';
  end if;

  select * into v_participant from trono_private.participants as p where p.normalized_name = v_normalized;
  if p_attending then
    if not found then
      insert into trono_private.participants (display_name, normalized_name)
      values (v_name, v_normalized) returning * into v_participant;
    end if;
    if not v_participant.active then
      raise exception using errcode = '22023', message = 'Ese nombre no está disponible.';
    end if;
    insert into trono_private.registrations as r (participant_id, office_date, status, updated_at)
    values (v_participant.id, v_date, 'registered', v_now)
    on conflict (participant_id, office_date) do update
    set status = 'registered', updated_at = excluded.updated_at
    where r.status <> 'registered';
  elsif found then
    update trono_private.registrations as r
    set status = 'cancelled', updated_at = v_now
    where r.participant_id = v_participant.id and r.office_date = v_date and r.status = 'registered';
  end if;

  perform trono_private.resolve_pending(v_now);
  return trono_private.snapshot(v_now) || jsonb_build_object('savedName', v_participant.display_name);
end;
$$;

create function public.office_snapshot()
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_now timestamptz;
begin
  perform pg_catalog.pg_advisory_xact_lock(1613490020, 1);
  v_now := pg_catalog.clock_timestamp();
  perform trono_private.resolve_pending(v_now);
  return trono_private.snapshot(v_now);
end;
$$;

create function public.register_attendance(p_name text, p_expected_date date)
returns jsonb
language sql security definer
set search_path = ''
as $$
  select trono_private.set_attendance(p_name, p_expected_date, true);
$$;

create function public.cancel_attendance(p_name text, p_expected_date date)
returns jsonb
language sql security definer
set search_path = ''
as $$
  select trono_private.set_attendance(p_name, p_expected_date, false);
$$;

create function trono_private.admin_block_day(p_date date, p_reason text default null)
returns void
language plpgsql security invoker
set search_path = ''
as $$
declare
  v_now timestamptz;
begin
  if p_date is null or not pg_catalog.isfinite(p_date) or extract(isodow from p_date) not between 1 and 5 then
    raise exception using errcode = '22023', message = 'Indica una fecha válida de lunes a viernes.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(1613490020, 1);
  v_now := pg_catalog.clock_timestamp();
  if exists (select 1 from trono_private.draws as d where d.office_date = p_date) then
    raise exception using errcode = '22023', message = 'Ese día ya tiene un resultado definitivo.';
  end if;
  if trono_private.closes_at(p_date) <= v_now then
    raise exception using errcode = '22023', message = 'El plazo de inscripción de ese día ya ha cerrado.';
  end if;
  insert into trono_private.blocked_days (date, reason)
  values (p_date, nullif(btrim(p_reason), ''))
  on conflict (date) do update set reason = excluded.reason;
  update trono_private.registrations as r
  set status = 'invalidated', updated_at = v_now
  where r.office_date = p_date and r.status = 'registered';
end;
$$;

create function trono_private.admin_unblock_day(p_date date)
returns void
language plpgsql security invoker
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(1613490020, 1);
  delete from trono_private.blocked_days as b where b.date = p_date;
end;
$$;

revoke all on all functions in schema trono_private from public, anon, authenticated, service_role;
grant execute on function trono_private.closes_at(date), trono_private.next_office_date(timestamptz),
  trono_private.resolve_pending(timestamptz), trono_private.snapshot(timestamptz),
  trono_private.set_attendance(text, date, boolean) to trono_rpc_owner;

revoke all on function public.office_snapshot(),
  public.register_attendance(text, date), public.cancel_attendance(text, date)
from public, anon, authenticated, service_role;
grant execute on function public.office_snapshot(),
  public.register_attendance(text, date), public.cancel_attendance(text, date)
to anon;

-- Ownership transfer needs CREATE in the target schema. Keep it scoped to this transaction.
grant create on schema public to trono_rpc_owner;
alter function public.office_snapshot() owner to trono_rpc_owner;
alter function public.register_attendance(text, date) owner to trono_rpc_owner;
alter function public.cancel_attendance(text, date) owner to trono_rpc_owner;
revoke create on schema public from trono_rpc_owner;

notify pgrst, 'reload schema';

commit;
