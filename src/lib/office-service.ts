import type { OfficeSnapshot } from '../domain/office'
import { getSupabase } from './supabase'

type AttendanceSnapshot = OfficeSnapshot & { savedName: string | null }

async function request<T extends OfficeSnapshot>(
  operation: 'office_snapshot' | 'register_attendance' | 'cancel_attendance',
  args?: { p_name: string; p_expected_date: string },
) {
  const { data, error, status } = await getSupabase().rpc(operation, args)
  if (status === 401) {
    throw new Error('Supabase rechazó la clave. Comprueba que la URL y la clave publicable de .env.local pertenecen al mismo proyecto.')
  }
  if (error?.code === '22023') throw new Error(error.message)
  if (error?.code === 'PGRST202') {
    throw new Error('Aplica la migración SQL de QueRuleErTrono en el proyecto de Supabase configurado.')
  }
  if (error || !data) {
    throw new Error(operation === 'office_snapshot'
      ? 'No se pudo consultar Supabase. Revisa la conexión y la configuración del proyecto.'
      : 'No se pudo confirmar el cambio de inscripción. Vuelve a consultar antes de reintentar.')
  }
  return data as T
}

export function fetchOffice() {
  return request<OfficeSnapshot>('office_snapshot')
}

export function saveOfficeAttendance(name: string, date: string, attending: boolean) {
  return request<AttendanceSnapshot>(attending ? 'register_attendance' : 'cancel_attendance', {
    p_name: name,
    p_expected_date: date,
  })
}
