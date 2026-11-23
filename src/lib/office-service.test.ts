import { beforeEach, describe, expect, it, vi } from 'vitest'

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }))
vi.mock('./supabase', () => ({ getSupabase: () => ({ rpc }) }))

import { fetchOffice, saveOfficeAttendance } from './office-service'

const snapshot = {
  serverNow: '2026-11-24T10:00:00.000001Z',
  startDate: '2026-11-23',
  nextDate: '2026-11-25',
  closesAt: '2026-11-24T21:00:00+00:00',
  blockedDays: [],
  attendees: [],
  draws: [],
}

beforeEach(() => rpc.mockReset())

describe('servicio de oficina', () => {
  it('consulta el estado sin enviar fecha ni reloj al sorteo', async () => {
    rpc.mockResolvedValue({ data: snapshot, error: null })
    await expect(fetchOffice()).resolves.toEqual(snapshot)
    expect(rpc).toHaveBeenCalledWith('office_snapshot', undefined)
  })

  it.each([[true, 'register_attendance'], [false, 'cancel_attendance']] as const)(
    'usa la RPC apropiada para asistencia=%s',
    async (attending, operation) => {
      const result = { ...snapshot, savedName: 'Ana' }
      rpc.mockResolvedValue({ data: result, error: null })
      await expect(saveOfficeAttendance('ana', snapshot.nextDate, attending)).resolves.toEqual(result)
      expect(rpc).toHaveBeenCalledWith(operation, { p_name: 'ana', p_expected_date: snapshot.nextDate })
    },
  )

  it('informa de un cierre rechazado por la base de datos', async () => {
    rpc.mockResolvedValue({
      data: null, error: { code: '22023', message: 'La inscripción para ese día ya no está abierta.' },
    })
    await expect(saveOfficeAttendance('Ana', snapshot.nextDate, false)).rejects.toThrow('ya no está abierta')
  })

  it('identifica una RPC ausente como migración pendiente', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202' } })
    await expect(fetchOffice()).rejects.toThrow('Aplica la migración SQL')
  })

  it('indica cómo corregir un rechazo HTTP 401 de Supabase', async () => {
    rpc.mockResolvedValue({ data: null, error: {}, status: 401 })
    await expect(fetchOffice()).rejects.toThrow('Supabase rechazó la clave')
  })
})
