import { useCallback, useEffect, useState } from 'react';
import type { ComponentType } from 'react';
import {
  ApiError,
  fetchReport,
  fetchSession,
  type SessionMeta,
} from '../../api/client';
import { EmptySession } from './EmptySession';

type WorkbenchChange = {
  sessionId?: unknown;
  kind?: unknown;
};

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

export function SessionShell({ sessionId }: { sessionId: string }) {
  const [meta, setMeta] = useState<SessionMeta | null>(null);
  const [error, setError] = useState('');

  const pullMeta = useCallback(() => {
    fetchSession(sessionId)
      .then(next => {
        setMeta(next);
        setError('');
      })
      .catch(reason => setError(reason instanceof Error ? reason.message : String(reason)));
  }, [sessionId]);

  useEffect(() => {
    pullMeta();
    const changed = (data: WorkbenchChange) => {
      if (data.sessionId !== sessionId) return;
      if (data.kind === 'report') pullMeta();
    };
    import.meta.hot?.on('workbench:changed', changed);
    return () => {
      import.meta.hot?.off('workbench:changed', changed);
    };
  }, [pullMeta, sessionId]);

  if (error) {
    return (
      <main className="empty-session">
        <p className="missing">セッションを読めなかった: {error}</p>
        <a className="home-link" href="/">作業一覧へ戻る</a>
      </main>
    );
  }
  if (!meta) return <main className="empty-session"><p>セッションを読み込んでいます。</p></main>;

  return (
    <>
      <nav className="session-shell-head">
        <a className="home-link" href="/">workbench</a>
        <strong>{meta.name}</strong>
      </nav>
      <ReviewView sessionId={sessionId} hasReport={meta.documents.report} />
    </>
  );
}
