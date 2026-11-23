import { CalendarDays, Crown, History as HistoryIcon, Ticket } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { History } from './components/History'
import { OfficeWeek } from './components/OfficeWeek'
import { Registration } from './components/Registration'
import { Throne } from './components/Throne'
import { formatOfficeDate, madridDate } from './domain/calendar'
import type { OfficeSnapshot } from './domain/office'
import { fetchOffice, saveOfficeAttendance } from './lib/office-service'

const NAME_KEY = 'queruleertrono.name'

const navigation = [
  { id: 'inicio', label: 'El trono', Icon: Crown },
  { id: 'inscripcion', label: 'Inscripción', Icon: Ticket },
  { id: 'calendario', label: 'Calendario', Icon: CalendarDays },
  { id: 'historial', label: 'Historial', Icon: HistoryIcon },
]

function currentPage() {
  const id = window.location.hash.slice(1)
  return navigation.find((item) => item.id === id)?.id ?? 'inicio'
}

function readRememberedName() {
  try {
    return localStorage.getItem(NAME_KEY) ?? ''
  } catch {
    return ''
  }
}

export default function App() {
  const [tick, setTick] = useState(() => performance.now())
  const [page, setPage] = useState(currentPage)
  const [snapshot, setSnapshot] = useState<{ data: OfficeSnapshot; clock: number; receivedAt: number }>()
  const [remembered, setRemembered] = useState(readRememberedName)
  const [error, setError] = useState('')
  const state = snapshot?.data
  const now = snapshot
    ? new Date(snapshot.clock + Math.max(0, tick - snapshot.receivedAt))
    : new Date()
  const today = madridDate(now)
  const cutoffReached = state !== undefined && now.getTime() >= Date.parse(state.closesAt)

  const applySnapshot = useCallback((data: OfficeSnapshot) => {
    const receivedAt = performance.now()
    // Keep server microseconds for ordering, and use milliseconds for the UI clock.
    const clock = Date.parse(data.serverNow.slice(0, 23) + 'Z')
    setSnapshot((current) =>
      current && current.data.serverNow >= data.serverNow ? current : { data, clock, receivedAt },
    )
    setError('')
  }, [])

  const refresh = useCallback(async () => {
    try {
      applySnapshot(await fetchOffice())
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'No se pudieron consultar los datos del sorteo.')
    }
  }, [applySnapshot])

  useEffect(() => {
    const tickClock = () => setTick(performance.now())
    const clockTimer = window.setInterval(tickClock, 1000)
    const navigate = () => {
      setPage(currentPage())
      window.scrollTo(0, 0)
    }
    const onVisible = () => {
      if (!document.hidden) {
        tickClock()
        void refresh()
      }
    }
    const refreshTimer = window.setInterval(onVisible, 60_000)
    const onStorage = (event: StorageEvent) => {
      if (!event.key || event.key === NAME_KEY) setRemembered(readRememberedName())
    }
    window.addEventListener('hashchange', navigate)
    window.addEventListener('focus', onVisible)
    window.addEventListener('storage', onStorage)
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      window.clearInterval(clockTimer)
      window.clearInterval(refreshTimer)
      window.removeEventListener('hashchange', navigate)
      window.removeEventListener('focus', onVisible)
      window.removeEventListener('storage', onStorage)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [refresh])

  useEffect(() => {
    if (!document.hidden) void refresh()
  }, [today, cutoffReached, page, refresh])

  async function saveAttendance(name: string, date: string, attending: boolean) {
    try {
      const updated = await saveOfficeAttendance(name, date, attending)
      applySnapshot(updated)
      if (updated.savedName) {
        setRemembered(updated.savedName)
        try {
          localStorage.setItem(NAME_KEY, updated.savedName)
        } catch {
          // The saved attendance is independent of browser preferences.
        }
      }
    } catch (failure) {
      void refresh()
      throw failure
    }
  }

  const registration = state && (
    <Registration key={state.nextDate} attendees={state.attendees} closesAt={state.closesAt}
      now={now} date={state.nextDate} remembered={remembered} onAttendance={saveAttendance} />
  )

  return (
    <div className="app-shell">
      <header className="site-header">
        <div className="header-inner">
          <a className="brand" href="#inicio" aria-label="QueRuleErTrono, inicio">
            <span className="brand-mark"><Crown size={23} strokeWidth={1.8} /></span>
            <span>QueRule<span className="brand-accent">ErTrono</span></span>
          </a>
          <nav aria-label="Navegación principal">
            {navigation.map(({ id, label, Icon }) => (
              <a key={id} href={`#${id}`} aria-current={page === id ? 'page' : undefined}>
                <Icon size={16} strokeWidth={1.8} /> <span>{label}</span>
              </a>
            ))}
          </nav>
          <div className="header-date"><CalendarDays size={16} /><time dateTime={today}>{formatOfficeDate(today, { weekday: 'short', day: 'numeric', month: 'short' })}</time></div>
        </div>
      </header>

      <main className="main-content">
        {error && <p className="notice" role="alert">{error}</p>}
        {page === 'inicio' && (
          <>
            <section className="intro" aria-labelledby="main-title">
              <h1 id="main-title">Que rule <em>Er Trono.</em></h1>
              <p>La mejor silla de la oficina se gana por sorteo. Apúntate y que la suerte te siente bien.</p>
            </section>
            {state && (
              <>
                <div className="home-grid">
                  <Throne state={state} today={today} />
                  {registration}
                </div>
                <OfficeWeek state={state} today={today} compact />
              </>
            )}
          </>
        )}
        {state && page === 'inscripcion' && (
          <div className="registration-page">
            {registration}
          </div>
        )}
        {state && page === 'calendario' && <OfficeWeek state={state} today={today} />}
        {state && page === 'historial' && <History state={state} />}
        {!state && !error && <p role="status">Cargando el sorteo…</p>}
      </main>
      <footer className="site-footer"><div><span><Crown size={16} /> QueRuleErTrono</span><span>La realeza también ficha.</span></div></footer>
    </div>
  )
}
