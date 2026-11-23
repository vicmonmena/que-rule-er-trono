import { describe, expect, it } from 'vitest'
import { addDays, isWeekday, madridDate, mondayOf, workweek } from './calendar'

describe('calendario de Madrid', () => {
  it('calcula la fecha local aunque en UTC sea el día anterior', () => {
    expect(madridDate(new Date('2026-07-19T22:05:00Z'))).toBe('2026-07-20')
    expect(madridDate(new Date('2026-11-22T23:05:00Z'))).toBe('2026-11-23')
  })

  it('muestra de lunes a viernes, incluso al cambiar de año', () => {
    expect(mondayOf('2027-01-03')).toBe('2026-12-28')
    expect(workweek('2027-01-03')).toEqual(['2026-12-28', '2026-12-29', '2026-12-30', '2026-12-31', '2027-01-01'])
    expect(addDays('2028-02-28', 1)).toBe('2028-02-29')
    expect(isWeekday('2027-01-03')).toBe(false)
    expect(isWeekday('2027-01-04')).toBe(true)
  })
})
