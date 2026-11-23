import { CalendarDays, ChevronLeft, ChevronRight, Clock3, Crown, Minus, ShieldOff } from 'lucide-react'
import { useState } from 'react'
import { addDays, formatOfficeDate, formatOfficeRange, mondayOf, workweek } from '../domain/calendar'
import type { OfficeSnapshot } from '../domain/office'

interface WeekProps {
  state: OfficeSnapshot
  today: string
  compact?: boolean
}

export function OfficeWeek({ state, today, compact = false }: WeekProps) {
  const [offset, setOffset] = useState(0)
  const monday = addDays(mondayOf(today), offset * 7)
  const days = workweek(monday)

  return (
    <section className={compact ? 'week section-space' : 'week'}>
      <div className="section-heading">
        <div>
          <div className="eyebrow"><CalendarDays size={15} /> Calendario de oficina</div>
          <h2>{compact ? 'Esta semana' : 'La semana del trono'}</h2>
          <p>{formatOfficeRange(monday, days[4])}</p>
        </div>
        {compact ? (
          <a href="#calendario" className="outline-button">Ver calendario</a>
        ) : (
          <div className="week-controls" aria-label="Cambiar semana">
            <button className="icon-button" aria-label="Semana anterior" onClick={() => setOffset(offset - 1)}><ChevronLeft size={19} /></button>
            <button className="outline-button" onClick={() => setOffset(0)}>Hoy</button>
            <button className="icon-button" aria-label="Semana siguiente" onClick={() => setOffset(offset + 1)}><ChevronRight size={19} /></button>
          </div>
        )}
      </div>
      <ol className="week-grid">
        {days.map((date) => {
          const draw = state.draws.find((item) => item.officeDate === date)
          const blocked = state.blockedDays.includes(date)
          let status = 'Pendiente'
          let Icon = Clock3
          if (blocked || date < state.startDate) {
            status = blocked ? 'Sin sorteo' : 'Sin registro'
            Icon = ShieldOff
          } else if (draw?.status === 'winner') {
            status = draw.winnerName
            Icon = Crown
          } else if (draw?.status === 'no_participants') {
            status = 'Sin inscritos'
            Icon = Minus
          } else if (date === state.nextDate) {
            status = 'Inscripción abierta'
            Icon = CalendarDays
          }

          return (
            <li key={date} className={date === today ? 'week-day current' : 'week-day'}>
              <div className="week-day-heading">
                <time dateTime={date}>
                  <span>{formatOfficeDate(date, { weekday: 'long' })}</span>
                  <strong>{formatOfficeDate(date, { day: 'numeric' })}</strong>
                </time>
                {date === today && <span className="today-label" aria-current="date">Hoy</span>}
              </div>
              <div className={draw?.status === 'winner' ? 'day-status winner-status' : 'day-status'}><Icon size={15} /> {status}</div>
              {draw?.status === 'winner' && draw.exceptional && <small>Victoria excepcional</small>}
            </li>
          )
        })}
      </ol>
    </section>
  )
}
