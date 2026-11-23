import { createClient, type SupabaseClient } from '@supabase/supabase-js'

let client: SupabaseClient | undefined

export function getSupabase() {
  if (client) return client

  const url = import.meta.env.VITE_SUPABASE_URL?.trim()
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()
  if (!url || !key?.startsWith('sb_publishable_') || key === 'sb_publishable_your_key') {
    throw new Error('Configura la URL y la clave publicable de Supabase en .env.local y reinicia Vite.')
  }

  try {
    client = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    })
    return client
  } catch {
    throw new Error('Revisa la URL de Supabase en .env.local y reinicia Vite.')
  }
}
