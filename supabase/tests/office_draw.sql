\set ON_ERROR_STOP on

begin;
set local plpgsql.check_asserts = on;
set local time zone 'Pacific/Honolulu';

do $$
declare
  v_role text;
  v_rpc regprocedure;
begin
  assert current_database() = 'queruleertrono_test', 'Usa la base desechable queruleertrono_test';
  assert not exists (select from trono_private.draws)
     and not exists (select from trono_private.participants), 'La base de pruebas debe estar vacía';

  assert trono_private.closes_at(date '2026-03-27') = timestamptz '2026-03-26 21:00Z', 'Hora de invierno';
  assert trono_private.closes_at(date '2026-03-30') = timestamptz '2026-03-29 20:00Z', 'Cambio a horario de verano';
  assert trono_private.closes_at(date '2026-10-26') = timestamptz '2026-10-25 21:00Z', 'Cambio a horario de invierno';
  assert trono_private.next_office_date(timestamptz '2026-11-26 20:59:59.999Z') = date '2026-11-27';
  assert trono_private.next_office_date(timestamptz '2026-11-26 21:00Z') = date '2026-11-30';
  assert trono_private.next_office_date(timestamptz '2026-11-27 12:00Z') = date '2026-11-30';
  assert trono_private.next_office_date(timestamptz '2026-11-29 20:59:59.999Z') = date '2026-11-30';
  assert trono_private.next_office_date(timestamptz '2026-11-29 21:00Z') = date '2026-12-01';

  foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
    assert not pg_has_role(v_role, 'trono_rpc_owner', 'MEMBER'), 'El rol de API no puede asumir el propietario';
    assert not has_schema_privilege(v_role, 'trono_private', 'USAGE'), 'Acceso al esquema privado';
    assert not has_table_privilege(v_role, 'trono_private.registrations', 'SELECT, INSERT, UPDATE, DELETE');
    assert not has_table_privilege(v_role, 'trono_private.participants', 'SELECT, INSERT, UPDATE, DELETE');
    assert not has_table_privilege(v_role, 'trono_private.draws', 'SELECT, INSERT, UPDATE, DELETE');
    assert not has_table_privilege(v_role, 'trono_private.blocked_days', 'SELECT, INSERT, UPDATE, DELETE');
    assert not has_function_privilege(v_role, 'trono_private.admin_block_day(date,text)', 'EXECUTE');
    assert not has_function_privilege(v_role, 'trono_private.admin_unblock_day(date)', 'EXECUTE');
    assert not has_function_privilege(v_role, 'trono_private.resolve_pending(timestamptz)', 'EXECUTE');
    assert not exists (
      select from pg_proc as p
      where p.pronamespace = 'trono_private'::regnamespace and has_function_privilege(v_role, p.oid, 'EXECUTE')
    ), 'Las funciones internas quedan fuera del alcance de los roles de API';
  end loop;
  assert not exists (
    select from pg_class where relnamespace = 'trono_private'::regnamespace and relkind = 'r' and not relrowsecurity
  ), 'RLS debe estar activa en todas las tablas internas';

  assert (
    select not (rolcanlogin or rolsuper or rolcreatedb or rolcreaterole or rolreplication or rolbypassrls)
    from pg_roles where rolname = 'trono_rpc_owner'
  ), 'El propietario de las RPC debe tener privilegios limitados';
  assert not has_schema_privilege('trono_rpc_owner', 'public', 'CREATE');
  assert not has_schema_privilege('trono_rpc_owner', 'trono_private', 'CREATE');
  assert not has_column_privilege('trono_rpc_owner', 'trono_private.blocked_days', 'reason', 'SELECT');
  assert not has_table_privilege('trono_rpc_owner', 'trono_private.blocked_days', 'INSERT, UPDATE, DELETE');
  assert not has_table_privilege('trono_rpc_owner', 'trono_private.draws', 'UPDATE, DELETE');
  assert not has_function_privilege('trono_rpc_owner', 'trono_private.admin_block_day(date,text)', 'EXECUTE');
  assert not has_function_privilege('trono_rpc_owner', 'trono_private.admin_unblock_day(date)', 'EXECUTE');
  assert not exists (
    select from pg_proc as p where p.pronamespace = 'trono_private'::regnamespace
      and (p.prosecdef or p.proowner <> 'postgres'::regrole
        or not coalesce(p.proconfig @> array['search_path=""'], false))
  ), 'Las funciones privadas son SECURITY INVOKER de postgres con search_path fijo';

  foreach v_rpc in array array[
    'public.office_snapshot()'::regprocedure,
    'public.register_attendance(text,date)'::regprocedure,
    'public.cancel_attendance(text,date)'::regprocedure
  ] loop
    assert (
      select p.prosecdef and p.proowner = 'trono_rpc_owner'::regrole
        and p.proconfig @> array['search_path=""']
      from pg_proc as p where p.oid = v_rpc
    ), 'Cada RPC pública tiene propietario restringido y search_path fijo';
    assert has_function_privilege('anon', v_rpc, 'EXECUTE');
    assert not has_function_privilege('anon', v_rpc, 'EXECUTE WITH GRANT OPTION');
    assert not has_function_privilege('authenticated', v_rpc, 'EXECUTE');
    assert not has_function_privilege('service_role', v_rpc, 'EXECUTE');
    assert not exists (
      select from pg_proc as p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as a
      where p.oid = v_rpc and a.grantee not in (p.proowner, 'anon'::regrole)
    ), 'Solo el propietario y anon figuran en la ACL de la RPC';
  end loop;
end;
$$;

savepoint public_api;

set local role anon;
do $$
declare
  v_date date := (public.office_snapshot()->>'nextDate')::date;
  v_data jsonb;
begin
  v_data := public.register_attendance(U&'  Ana \0009 Mari\0301a  ', v_date);
  assert v_data->>'savedName' = 'Ana María', 'Nombre en NFC';
  v_data := public.register_attendance(U&'ANA\00A0MARÍA', v_date);
  assert v_data#>>'{attendees,0,normalizedName}' = 'ana maría', 'Nombre normalizado';
  assert jsonb_array_length(v_data->'attendees') = 1, 'Alta idempotente';

  v_data := public.cancel_attendance('ANA MARÍA', v_date);
  assert jsonb_array_length(v_data->'attendees') = 0, 'Baja';
  v_data := public.cancel_attendance('Ana María', v_date);
  assert jsonb_array_length(v_data->'attendees') = 0, 'Baja idempotente';
  v_data := public.register_attendance('ana maría', v_date);
  assert jsonb_array_length(v_data->'attendees') = 1, 'Reactivar inscripción';

  begin
    perform public.register_attendance('Cris', v_date + 14);
    raise exception 'La API aceptó una fecha futura arbitraria';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.cancel_attendance('Ana María', (clock_timestamp() at time zone 'Europe/Madrid')::date);
    raise exception 'La API aceptó una baja fuera de plazo';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.register_attendance('   ', v_date);
    raise exception 'La API aceptó un nombre vacío';
  exception when invalid_parameter_value then null;
  end;
  begin
    execute 'update trono_private.registrations set status = ''registered''';
    raise exception 'anon escribió directamente en la tabla';
  exception when insufficient_privilege then null;
  end;
  begin
    execute 'select trono_private.admin_block_day($1, null)' using v_date;
    raise exception 'anon ejecutó una operación administrativa';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

do $$
begin
  assert (select count(*) from trono_private.participants) = 1;
  assert (select count(*) from trono_private.registrations) = 1;
end;
$$;

rollback to savepoint public_api;
savepoint calendar_admin;

do $$
declare
  v_week date := date_trunc('week', clock_timestamp() at time zone 'Europe/Madrid')::date;
  v_future date := v_week + 14;
  v_past date := v_week - 7;
  v_before_close timestamptz := trono_private.closes_at(v_future) - interval '1 second';
  v_participant uuid;
begin
  update trono_private.game_settings set start_date = v_future;
  insert into trono_private.participants (display_name, normalized_name) values ('Ana', 'ana')
    returning id into v_participant;
  insert into trono_private.registrations (participant_id, office_date, status)
  values (v_participant, v_future, 'registered'), (v_participant, v_past, 'registered');

  assert not exists (select from trono_private.draws where office_date = v_past);
  begin
    perform trono_private.admin_block_day(v_past);
    raise exception 'Se bloqueó un día cerrado y sin resultado';
  exception when invalid_parameter_value then
    assert sqlerrm = 'El plazo de inscripción de ese día ya ha cerrado.';
  end;
  assert not exists (select from trono_private.blocked_days where date = v_past);
  assert (select status from trono_private.registrations where office_date = v_past) = 'registered';

  perform trono_private.admin_block_day(v_future, '  Festivo  ');
  assert trono_private.next_office_date(v_before_close) = v_future + 1, 'Salta el lunes bloqueado';
  assert (select status from trono_private.registrations where office_date = v_future) = 'invalidated';
  assert (select reason from trono_private.blocked_days) = 'Festivo';
  assert trono_private.snapshot(v_before_close)->'blockedDays' = jsonb_build_array(v_future);
  perform trono_private.resolve_pending(trono_private.closes_at(v_future));
  assert not exists (select from trono_private.draws), 'Un día bloqueado no se sortea';
  perform trono_private.admin_unblock_day(v_future);
  assert (select status from trono_private.registrations where office_date = v_future) = 'invalidated', 'Desbloquear no restaura la inscripción';
  perform trono_private.resolve_pending(trono_private.closes_at(v_future));
  assert (select status from trono_private.draws) = 'no_participants';
  begin
    perform trono_private.admin_block_day(v_future);
    raise exception 'Se bloqueó un día con resultado definitivo';
  exception when invalid_parameter_value then
    assert sqlerrm = 'Ese día ya tiene un resultado definitivo.';
  end;
end;
$$;

rollback to savepoint calendar_admin;
savepoint weekly_rules;

update trono_private.game_settings set start_date = date '2026-11-16';
insert into trono_private.participants (display_name, normalized_name, active)
values ('Ana', 'ana', true), ('Bea', 'bea', true), ('Cris', 'cris', true), ('Inactivo', 'inactivo', false);
insert into trono_private.registrations (participant_id, office_date, status)
select p.id, f.office_date::date, f.status
from (values
  ('ana', '2026-11-16', 'registered'), ('ana', '2026-11-17', 'registered'),
  ('bea', '2026-11-18', 'registered'), ('bea', '2026-11-19', 'registered'),
  ('cris', '2026-11-20', 'cancelled'), ('inactivo', '2026-11-20', 'registered'),
  ('ana', '2026-11-23', 'registered'), ('ana', '2026-11-24', 'registered'),
  ('bea', '2026-11-25', 'registered'), ('cris', '2026-11-26', 'registered'),
  ('ana', '2026-11-27', 'registered'), ('bea', '2026-11-27', 'registered'), ('cris', '2026-11-27', 'registered'),
  ('ana', '2026-11-30', 'registered'),
  ('ana', '2026-12-01', 'registered'), ('bea', '2026-12-01', 'registered'), ('cris', '2026-12-01', 'registered')
) as f(name, office_date, status)
join trono_private.participants as p on p.normalized_name = f.name;

do $$
declare
  v_history jsonb;
  v_ana uuid := (select id from trono_private.participants where normalized_name = 'ana');
  v_cris uuid := (select id from trono_private.participants where normalized_name = 'cris');
begin
  perform trono_private.resolve_pending(timestamptz '2026-11-15 20:59:59.999Z');
  assert not exists (select from trono_private.draws), 'No se sortea antes del cierre';
  perform trono_private.resolve_pending(timestamptz '2026-11-30 21:00Z');
  assert (select count(*) from trono_private.draws) = 12, 'Se resuelven las fechas hábiles vencidas';
  assert (select status = 'no_participants' from trono_private.draws where office_date = '2026-11-20'), 'Inscripciones no válidas quedan fuera';
  assert (select winner_participant_id = v_ana and not exceptional from trono_private.draws where office_date = '2026-11-23');
  assert (select winner_participant_id = v_ana and exceptional and eligible_count = 0 from trono_private.draws where office_date = '2026-11-24'), 'Cuota reducida y excepción para la única inscrita';
  assert (select winner_participant_id = v_cris and not exceptional and eligible_count = 1 from trono_private.draws where office_date = '2026-11-27'), 'Solo entran los elegibles';
  assert (select winner_participant_id <> v_ana and not exceptional and eligible_count = 2 from trono_private.draws where office_date = '2026-12-01'), 'La excepción de la semana anterior también reduce la cuota';
  v_history := trono_private.snapshot(timestamptz '2026-11-30 21:00Z')->'draws';
  assert v_history#>>'{0,officeDate}' = '2026-12-01';
  assert v_history#>>'{1,winnerName}' = 'Ana';
  perform trono_private.resolve_pending(timestamptz '2026-11-30 21:05Z');
  assert (select count(*) from trono_private.draws) = 12;
  assert (select count(distinct drawn_at) from trono_private.draws) = 1, 'Los resultados existentes no se reescriben';
end;
$$;

rollback to savepoint weekly_rules;
savepoint exhausted_candidates;

update trono_private.game_settings set start_date = date '2026-11-16';
insert into trono_private.participants (display_name, normalized_name)
values ('Ana', 'ana'), ('Bea', 'bea'), ('Cris', 'cris');
insert into trono_private.registrations (participant_id, office_date, status)
select p.id, f.office_date::date, 'registered'
from (values
  ('ana', '2026-11-16'), ('ana', '2026-11-17'), ('bea', '2026-11-18'), ('bea', '2026-11-19'),
  ('cris', '2026-11-23'), ('cris', '2026-11-24'), ('ana', '2026-11-25'), ('bea', '2026-11-26'),
  ('ana', '2026-11-27'), ('bea', '2026-11-27'), ('cris', '2026-11-27')
) as f(name, office_date)
join trono_private.participants as p on p.normalized_name = f.name;

do $$
begin
  perform trono_private.resolve_pending(timestamptz '2026-11-26 21:00Z');
  assert (
    select d.status = 'winner' and d.exceptional and d.eligible_count = 0 and p.normalized_name in ('ana', 'bea', 'cris')
    from trono_private.draws as d
    join trono_private.participants as p on p.id = d.winner_participant_id
    where d.office_date = '2026-11-27'
  ), 'Cuando todos agotan la cuota, se sortea entre todos';
end;
$$;

rollback to savepoint exhausted_candidates;

update trono_private.game_settings set start_date = date '2026-12-28';
insert into trono_private.participants (display_name, normalized_name)
values ('Ana', 'ana'), ('Bea', 'bea');
insert into trono_private.registrations (participant_id, office_date, status)
select p.id, f.office_date::date, 'registered'
from (values
  ('ana', '2026-12-28'), ('ana', '2026-12-29'), ('ana', '2027-01-01'),
  ('ana', '2027-01-04'), ('ana', '2027-01-05'),
  ('ana', '2027-01-11'), ('ana', '2027-01-12'), ('bea', '2027-01-12'),
  ('ana', '2027-01-18'), ('ana', '2027-01-19'), ('ana', '2027-01-20')
) as f(name, office_date)
join trono_private.participants as p on p.normalized_name = f.name;

do $$
declare
  v_ana uuid := (select id from trono_private.participants where normalized_name = 'ana');
  v_bea uuid := (select id from trono_private.participants where normalized_name = 'bea');
begin
  perform trono_private.resolve_pending(trono_private.closes_at(date '2027-01-20'));
  assert (
    select winner_participant_id = v_ana and exceptional and eligible_count = 0
    from trono_private.draws where office_date = '2027-01-01'
  ), 'El 1 de enero comparte cuota con el lunes y martes de diciembre';
  assert (
    select winner_participant_id = v_ana and not exceptional
    from trono_private.draws where office_date = '2027-01-04'
  ), 'El lunes empieza una cuota nueva';
  assert (
    select winner_participant_id = v_ana and exceptional and eligible_count = 0
    from trono_private.draws where office_date = '2027-01-05'
  ), 'La semana anterior que cruza de año reduce la cuota a una';
  assert (
    select winner_participant_id = v_bea and not exceptional and eligible_count = 1
    from trono_private.draws where office_date = '2027-01-12'
  ), 'Una victoria ordinaria y otra excepcional mantienen la reducción la semana siguiente';
  assert (
    select count(*) = 2
    from trono_private.draws where office_date in ('2027-01-18', '2027-01-19')
      and winner_participant_id = v_ana and not exceptional
  ), 'Una sola victoria en la semana anterior restaura la cuota de dos';
  assert (
    select winner_participant_id = v_ana and exceptional and eligible_count = 0
    from trono_private.draws where office_date = '2027-01-20'
  ), 'La tercera victoria sigue siendo excepcional con la cuota restaurada';
end;
$$;

rollback;
\echo Pruebas SQL de calendario, permisos, inscripciones, cuotas consecutivas y cambio de año superadas.
