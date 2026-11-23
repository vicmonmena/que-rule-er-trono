export const OFFICE_TIME_ZONE = 'Europe/Madrid'

const madridClock = new Intl.DateTimeFormat('en-GB', {
  timeZone: OFFICE_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})

export function madridDate(instant: Date) {
  const parts = madridClock.formatToParts(instant)
  const value = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)!.value
  return `${value('year')}-${value('month')}-${value('day')}`
}

// A calendar date is represented independently of the device's time zone.
function utcDate(date: string) {
  return new Date(`${date}T00:00:00Z`)
}

export function addDays(date: string, days: number) {
  const parsed = utcDate(date)
  parsed.setUTCDate(parsed.getUTCDate() + days)
  return parsed.toISOString().slice(0, 10)
}

export function mondayOf(date: string) {
  return addDays(date, -((utcDate(date).getUTCDay() + 6) % 7))
}

export function workweek(date: string) {
  const monday = mondayOf(date)
  return Array.from({ length: 5 }, (_, offset) => addDays(monday, offset))
}

export function isWeekday(date: string) {
  const day = utcDate(date).getUTCDay()
  return day >= 1 && day <= 5
}

export function formatOfficeDate(date: string, options: Intl.DateTimeFormatOptions) {
  return new Intl.DateTimeFormat('es-ES', { ...options, timeZone: 'UTC' }).format(utcDate(date))
}

export function formatOfficeRange(start: string, end: string) {
  return new Intl.DateTimeFormat('es-ES', {
    day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC',
  }).formatRange(utcDate(start), utcDate(end))
}
