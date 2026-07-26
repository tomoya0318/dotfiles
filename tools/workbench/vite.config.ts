import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { workbenchApi } from './vite-plugin-api.js'

// 常駐サーバと一時テストサーバが同じ依存最適化キャッシュを触らないようにする。
// 通常起動では Vite の既定位置を使い、テストだけ環境変数で分離する。
export default defineConfig({
  cacheDir: process.env.WORKBENCH_CACHE_DIR ?? 'node_modules/.vite',
  plugins: [react(), workbenchApi()],
  server: { port: 5170, strictPort: true },
})
