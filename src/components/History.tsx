import { Crown, History as HistoryIcon, Minus, ScrollText } from 'lucide-react'
import { formatOfficeDate } from '../domain/calendar'
import type { OfficeSnapshot } from '../domain/office'

export function History({ state }: { state: OfficeSnapshot }) {
  const { draws } = state
  return (
    <section className="history">
      <div className="section-heading">
        <div>
          <div className="eyebrow"><HistoryIcon size={15} /> Historial de sorteos</div>
          <h2>Crónicas del trono</h2>
          <p>Todos los resultados, del más reciente al más antiguo.</p>
        </div>
      </div>
      {draws.length ? (
        <ul className="history-list card">
          {draws.map((draw) => {
            const won = draw.status === 'winner'
            return (
              <li key={draw.officeDate}>
                <span className="history-icon">{won ? <Crown size={20} /> : <Minus size={20} />}</span>
                <div className="history-result">
                  <strong>{draw.winnerName ?? 'Trono desierto'}</strong>
                  <time dateTime={draw.officeDate}>{formatOfficeDate(draw.officeDate, { dateStyle: 'full' })}</time>
                </div>
                {won && draw.exceptional && <span className="exception">Victoria excepcional</span>}
              </li>
            )
          })}
        </ul>
      ) : (
        <div className="history-empty card"><ScrollText size={28} /><p>Las crónicas empiezan con el primer sorteo.</p></div>
      )}
    </section>
  )
}
