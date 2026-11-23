import { CalendarDays, Clock3, Crown, UserRound, UserRoundCheck, UsersRound } from 'lucide-react'
import { useState, type FormEvent } from 'react'
import { addDays, formatOfficeDate } from '../domain/calendar'
import { cleanName, normalizeName, type Attendee } from '../domain/office'

interface RegistrationProps {
  attendees: Attendee[]
  closesAt: string
  now: Date
  date: string
  remembered: string
  onAttendance: (name: string, date: string, attending: boolean) => Promise<void>
}

function countdown(milliseconds: number) {
  const total = Math.max(0, Math.ceil(milliseconds / 1000))
  const days = Math.floor(total / 86_400)
  const hours = Math.floor(total / 3_600) % 24
  const minutes = Math.floor(total / 60) % 60
  if (days) return `${days} d ${hours} h ${minutes} min`
  if (hours) return `${hours} h ${minutes} min`
  return `${minutes} min ${total % 60} s`
}

export function Registration({ attendees, closesAt, now, date, remembered, onAttendance }: RegistrationProps) {
  const [draft, setDraft] = useState<string>()
  const [status, setStatus] = useState<{ message: string; error?: boolean }>()
  const [busy, setBusy] = useState(false)
  const name = draft ?? remembered
  const remaining = Date.parse(closesAt) - now.getTime()
  const isAttending = attendees.some((item) => item.normalizedName === normalizeName(name))

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setBusy(true)
    setStatus(undefined)
    try {
      await onAttendance(name, date, !isAttending)
      setDraft(undefined)
      setStatus({ message: isAttending ? 'Inscripción cancelada.' : 'Te has apuntado al sorteo.' })
    } catch (error) {
      setStatus({ message: error instanceof Error ? error.message : 'No se pudo guardar la inscripción.', error: true })
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="registration card" id="inscripcion" aria-labelledby="signup-title">
      <div className="eyebrow"><CalendarDays size={15} /> Próximo sorteo</div>
      <h2 id="signup-title">Reclama tu sitio</h2>
      <time dateTime={date} className="signup-date">{formatOfficeDate(date, { weekday: 'long', day: 'numeric', month: 'long' })}</time>
      <div className="countdown">
        <Clock3 size={18} />
        <div><strong>Cierra en {countdown(remaining)}</strong>
          <span>{formatOfficeDate(addDays(date, -1), { weekday: 'long', day: 'numeric', month: 'long' })} a las 22:00 · Madrid</span></div>
      </div>
      <form className="signup-form" onSubmit={submit}>
        <label htmlFor="participant">Tu nombre</label>
        <div className="input-wrap"><UserRound size={18} /><input id="participant" name="participant" autoComplete="nickname" placeholder="Escribe tu nombre" value={name} maxLength={60} required onChange={(event) => { setDraft(event.target.value); setStatus(undefined) }} /></div>
        <button type="submit" className={isAttending ? 'signup-button cancel' : 'signup-button'} disabled={busy || remaining <= 0 || !cleanName(name)}>
          {isAttending ? <UserRoundCheck size={17} /> : <Crown size={18} />}
          {busy ? 'Guardando…' : isAttending ? 'Cancelar inscripción' : 'Apuntarme al sorteo'}
        </button>
        {status && <p className={status.error ? 'form-feedback error' : 'form-feedback'} role={status.error ? 'alert' : 'status'}>{status.message}</p>}
      </form>
      <div className="attendees">
        <h3><UsersRound size={18} /> Inscritos <span>{attendees.length}</span></h3>
        {attendees.length ? (
          <ul>{attendees.map((item) => <li key={item.normalizedName}><span>{Array.from(item.name)[0].toLocaleUpperCase('es-ES')}</span>{item.name}</li>)}</ul>
        ) : <p>Todavía no hay nadie en la corte.</p>}
      </div>
    </section>
  )
}
