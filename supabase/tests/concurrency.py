"""Run against a fresh queruleertrono_test database with the migration applied."""

import subprocess
import sys
import time

psql = (sys.argv[1:] or ["psql", "-d", "queruleertrono_test"]) + [
    "-X", "-qAt", "-v", "ON_ERROR_STOP=1",
]


def query(sql):
    return subprocess.run(
        [*psql, "-c", sql], check=True, capture_output=True, text=True, timeout=15,
    ).stdout.strip()


def when_lock(granted, process):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline and process.poll() is None:
        if query(f"""
            select exists (
              select from pg_locks
              where locktype = 'advisory' and classid = 1613490020 and objid = 1
                and objsubid = 2 and granted = {granted}
                and database = (select oid from pg_database where datname = current_database())
            )
        """) == "t":
            return
        time.sleep(0.05)
    raise AssertionError(f"No se observó el bloqueo (granted = {granted})")


if query("select current_database()") != "queruleertrono_test":
    sys.exit("Usa únicamente la base desechable queruleertrono_test.")
if query("""
    select exists (select from trono_private.participants)
        or exists (select from trono_private.draws)
        or exists (select from trono_private.blocked_days)
""") != "f":
    sys.exit("La prueba de concurrencia requiere una base recién migrada y vacía.")

due_date = query("""
    update trono_private.game_settings
    set start_date = date_trunc('week', clock_timestamp() at time zone 'Europe/Madrid')::date - 7
    returning start_date
""")
query(f"""
    with inserted as (
      insert into trono_private.participants (display_name, normalized_name)
      values ('Ana', 'ana'), ('Bea', 'bea') returning id
    )
    insert into trono_private.registrations (participant_id, office_date, status)
    select id, date '{due_date}', 'registered' from inserted
""")

draw_sql = f"""
    select value->>'winnerName'
    from jsonb_array_elements(public.office_snapshot()->'draws')
    where value->>'officeDate' = '{due_date}'
"""

first = subprocess.Popen(
    [*psql, "-c", f"begin; set local role anon; {draw_sql}; select pg_sleep(5); commit"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)
second = None
try:
    when_lock("true", first)
    second = subprocess.Popen(
        [*psql, "-c", f"set role anon; {draw_sql}"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    when_lock("false", second)

    winner_first, first_error = first.communicate(timeout=12)
    winner_second, second_error = second.communicate(timeout=12)
    if first.returncode or second.returncode:
        raise AssertionError(first_error + second_error)
    assert winner_first.strip() in {"Ana", "Bea"}, "Debe haber un ganador válido"
    assert winner_first.strip() == winner_second.strip(), "Ambas sesiones deben ver el mismo ganador"
    assert query(f"select count(*) from trono_private.draws where office_date = date '{due_date}'") == "1"
    print("Dos sesiones simultáneas esperaron el mismo bloqueo y obtuvieron un único ganador persistido.")
finally:
    for process in (first, second):
        if process and process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
