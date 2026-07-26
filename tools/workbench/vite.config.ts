import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { threadApi } from './vite-plugin-thread.js'

// 同じ checkout で複数の dev サーバを走らせるため、依存の最適化キャッシュを分ける
export default defineConfig({
  cacheDir: process.env.DIFF_REVIEW_CACHE ?? 'node_modules/.vite',
  plugins: [react(), threadApi()],
})
