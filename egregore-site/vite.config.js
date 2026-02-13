import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': {
        target: 'https://egregore-production-55f2.up.railway.app',
        changeOrigin: true,
      },
    },
  },
})
