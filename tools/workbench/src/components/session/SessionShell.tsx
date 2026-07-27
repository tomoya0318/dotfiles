import { useCallback, useEffect, useState } from 'react';
import type { ComponentType } from 'react';
import {
  ApiError,
  fetchReport,
  fetchSession,
  type SessionMeta,
} from '../../api/client';
import type { SessionView } from '../../types/plan';
import { PlanApp } from '../plan/PlanApp';
import { EmptySession } from './EmptySession';
import { ViewToggle } from './ViewToggle';

type WorkbenchChange = {
  sessionId?: unknown;
  kind?: unknown;
};

function requestedView(meta: SessionMeta): SessionView {
  const requested = new URLSearchParams(location.search).get('view');
  if (requested === 'plan' && meta.documents.plan) return 'plan';
  if (requested === 'review') return 'review';
  if (meta.documents.report) return 'review';
  return meta.documents.plan ? 'plan' : 'review';
}

function ReviewView({
  sessionId,
  hasReport,
}: {
  sessionId: string;
  hasReport: boolean;
}) {
  const [App, setApp] = useState<ComponentType<{ sessionId: string }> | null>(null);
  const [error, setError] = useState('');
  const [missing, setMissing] = useState(false);

  useEffect(() => {
    if (!hasReport) return;
    let alive = true;
    setApp(null);
    setError('');
    setMissing(false);
    void (async () => {
      try {
        const raw = await fetchReport(sessionId);
        const { init } = await import('../../report');
        init(raw);
        const loaded = await import('../../App.tsx');
        if (alive) setApp(() => loaded.default);
      } catch (reason) {
        if (
          reason instanceof ApiError
          && reason.status === 404
          && reason.message === 'report not found'
        ) {
          if (alive) setMissing(true);
          return;
        }
        if (alive) setError(reason instanceof Error ? reason.message : String(reason));
      }
    })();
    return () => {
      alive = false;
    };
  }, [hasReport, sessionId]);

  if (!hasReport || missing) return <EmptySession sessionId={sessionId} />;
  if (error) {
    return (
      <main className="empty-session">
        <p className="missing">report を読めなかった: {error}</p>
        <a className="home-link" href="/">作業一覧へ戻る</a>
      </main>
    );
  }
  if (!App) return <main className="empty-session"><p>Review を読み込んでいます。</p></main>;
  return <App sessionId={sessionId} />;
}

export function SessionShell({
  sessionId,
  initialView,
}: {
  sessionId: string;
  initialView: SessionView | null;
}) {
  const [meta, setMeta] = useState<SessionMeta | null>(null);
  const [view, setView] = useState<SessionView>(initialView ?? 'review');
  const [error, setError] = useState('');

  const pullMeta = useCallback(() => {
    fetchSession(sessionId)
      .then(next => {
        setMeta(next);
        setView(requestedView(next));
        setError('');
      })
      .catch(reason => setError(reason instanceof Error ? reason.message : String(reason)));
  }, [sessionId]);

  useEffect(() => {
    pullMeta();
    const navigate = () => {
      setMeta(current => {
        if (current) setView(requestedView(current));
        return current;
      });
    };
    const changed = (data: WorkbenchChange) => {
      if (data.sessionId !== sessionId) return;
      if (data.kind === 'plan' || data.kind === 'report') pullMeta();
    };
    addEventListener('popstate', navigate);
    import.meta.hot?.on('workbench:changed', changed);
    return () => {
      removeEventListener('popstate', navigate);
      import.meta.hot?.off('workbench:changed', changed);
    };
  }, [pullMeta, sessionId]);

  const changeView = useCallback((next: SessionView) => {
    const url = new URL(location.href);
    url.searchParams.set('view', next);
    history.pushState(null, '', url);
    setView(next);
  }, []);

  if (error) {
    return (
      <main className="empty-session">
        <p className="missing">セッションを読めなかった: {error}</p>
        <a className="home-link" href="/">作業一覧へ戻る</a>
      </main>
    );
  }
  if (!meta) return <main className="empty-session"><p>セッションを読み込んでいます。</p></main>;

  if (view === 'plan' && meta.documents.plan) {
    return (
      <PlanApp
        sessionId={sessionId}
        session={meta}
        view={view}
        onViewChange={changeView}
      />
    );
  }

  return (
    <>
      <nav className="session-shell-head">
        <a className="home-link" href="/">workbench</a>
        <strong>{meta.name}</strong>
        <ViewToggle view="review" hasPlan={meta.documents.plan} onChange={changeView} />
      </nav>
      <ReviewView sessionId={sessionId} hasReport={meta.documents.report} />
    </>
  );
}
