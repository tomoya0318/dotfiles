import { useEffect } from 'react';

type WorkbenchChange = {
  sessionId?: unknown;
  kind?: unknown;
};

export function EmptySession({ sessionId }: { sessionId: string }) {
  useEffect(() => {
    const changed = (data: WorkbenchChange) => {
      if (data.sessionId !== sessionId) return;
      if (data.kind === 'report') location.reload();
    };
    import.meta.hot?.on('workbench:changed', changed);
    return () => {
      import.meta.hot?.off('workbench:changed', changed);
    };
  }, [sessionId]);

  return (
    <main className="empty-session">
      <p className="eyebrow">workbench</p>
      <h1>まだ diff がありません</h1>
      <p className="reason">report.json はまだ生成されていません。生成されるとレビューを開けます。</p>
      <a className="home-link" href="/">作業一覧へ戻る</a>
    </main>
  );
}
