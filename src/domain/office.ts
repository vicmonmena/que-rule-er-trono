export interface Attendee {
  name: string
  normalizedName: string
}

export type Draw = { officeDate: string } & (
  | { status: 'winner'; winnerName: string; exceptional: boolean }
  | { status: 'no_participants'; winnerName: null; exceptional: false }
)

export interface OfficeSnapshot {
  serverNow: string
  startDate: string
  nextDate: string
  closesAt: string
  blockedDays: string[]
  attendees: Attendee[]
  draws: Draw[]
}

export function cleanName(name: string) {
  return name.normalize('NFC').trim().replace(/\s+/gu, ' ')
}

export function normalizeName(name: string) {
  return cleanName(name).toLocaleLowerCase('es-ES').normalize('NFC')
}
