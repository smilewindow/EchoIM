import path from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const apiOrigin = process.env['ECHOIM_API_ORIGIN'] ?? 'http://localhost:3000'
const wsOrigin = apiOrigin.replace(/^http/, 'ws')

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    host: true,
    port: 5173,
    proxy: {
      '/api': {
        // 允许 e2e 把前端代理切到独立后端，避免误打开发服务。
        target: apiOrigin,
        changeOrigin: true,
      },
      '/ws': {
        target: wsOrigin,
        ws: true,
      },
      '/uploads': {
        target: apiOrigin,
        changeOrigin: true,
      },
    },
  },
})
