import { createRoot } from 'react-dom/client'
import { SessionShell } from './components/session/SessionShell'
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

async function renderHome() {
  const { default: Home } = await import('./components/home/Home.tsx')
  root.render(<Home />)
}

const sessionId = sessionIdFromPath(location.pathname)
if (sessionId) {
  root.render(<SessionShell sessionId={sessionId} />)
} else {
  void renderHome()
}
