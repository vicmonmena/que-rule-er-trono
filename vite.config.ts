import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ command, isPreview, mode }) => {
  const { VITE_SUPABASE_PUBLISHABLE_KEY: key } = loadEnv(mode, '.', 'VITE_SUPABASE_')
  if (key?.trim() && !/^sb_publishable_[\w-]+$/.test(key.trim())) {
    throw new Error('VITE_SUPABASE_PUBLISHABLE_KEY debe ser una clave publicable sb_publishable_.')
  }
  return {
    base: command === 'build' || isPreview ? '/que-rule-er-trono/' : '/',
    plugins: [react()],
  }
})
