import { createRoot } from 'react-dom/client'
import { ApiError, fetchReport } from './api/client'
import { EmptySession } from './components/session/EmptySession'
import { init } from './report'
import './App.css'

const root = createRoot(document.getElementById('root')!)

function sessionIdFromPath(pathname: string): string | null {
  const match = pathname.match(/^\/s\/([^/]+)\/?$/)
  if (!match) return null
  try {
    return decodeURIComponent(match[1])
  } catch {
    return null
  }
}

async function renderSession(sessionId: string) {
  try {
    const raw = await fetchReport(sessionId)
    init(raw)
    // App は report を同期的に読むので、init のあとで読み込む
    const { default: App } = await import('./App.tsx')
    root.render(<App sessionId={sessionId} />)
  } catch (error) {
    if (error instanceof ApiError && error.status === 404 && error.message === 'report not found') {
      root.render(<EmptySession sessionId={sessionId} />)
      return
    }
    root.render(
      <main className="empty-session">
        <p className="missing">report を読めなかった: {String(error instanceof Error ? error.message : error)}</p>
        <a className="home-link" href="/">作業一覧へ戻る</a>
      </main>,
    )
  }
}

async function renderHome() {
  const { default: Home } = await import('./components/home/Home.tsx')
  root.render(<Home />)
}

const sessionId = sessionIdFromPath(location.pathname)
if (sessionId) {
  void renderSession(sessionId)
} else {
  void renderHome()
}
