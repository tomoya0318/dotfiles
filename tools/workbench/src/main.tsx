import { createRoot } from 'react-dom/client'
import { fetchReport } from './api/client'
import { init } from './report'
import './App.css'

const root = createRoot(document.getElementById('root')!)

// App は report を同期的に読むので、init のあとで読み込む
fetchReport().then(async raw => {
  init(raw)
  const { default: App } = await import('./App.tsx')
  root.render(<App />)
}).catch(err => {
  root.render(
    <main>
      <p className="missing">report を読めなかった: {String(err?.message ?? err)}</p>
      <p className="reason">gen.py で生成し、DIFF_REVIEW_REPORT にそのパスを渡して起動する。</p>
    </main>,
  )
})
