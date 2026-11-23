import { CalendarDays, Crown } from 'lucide-react'
import { formatOfficeDate, isWeekday } from '../domain/calendar'
import type { OfficeSnapshot } from '../domain/office'

export function Throne({ today, state }: { today: string; state: OfficeSnapshot }) {
  const draw = state.draws.find((item) => item.officeDate === today)
  const won = draw?.status === 'winner'
  const closed = !isWeekday(today) || state.blockedDays.includes(today)
  const winner = draw?.winnerName
  const title = closed ? 'Sin sorteo' : winner ?? (draw ? 'Trono desierto' : 'Sorteo pendiente')
  const description = closed ? 'Hoy descansa hasta la silla.' : won
    ? (draw.exceptional ? 'Victoria excepcional. ¡Que rule!' : 'Hoy tiene asiento reservado.')
    : draw ? 'Nadie se apuntó al sorteo de hoy.' : 'El resultado aparecerá al consultar tras el cierre.'

  return (
    <section aria-labelledby="today-title" className="throne-card card">
      <div className="throne-image">
        <img src={`${import.meta.env.BASE_URL}trono.jpg`} alt="Silla de oficina de cuero oscuro con ruedas y adornos de trono dorado" />
        <span className="photo-label"><Crown size={17} /> Er Trono</span>
      </div>
      <div className="throne-caption">
        <span className="medallion"><Crown size={24} strokeWidth={1.65} /></span>
        <div className="throne-result">
          <div className="eyebrow">El trono de hoy</div>
          <h2 id="today-title">{title}</h2>
          <p>{description}</p>
        </div>
        <time dateTime={today} className="date-pill"><CalendarDays size={15} /> {formatOfficeDate(today, { day: 'numeric', month: 'short' })}</time>
      </div>
    </section>
  )
}
