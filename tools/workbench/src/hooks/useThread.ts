import { useCallback, useEffect, useMemo, useState } from 'react';
import { addComment, fetchThread, removeComment, replyTo, resolveComment, setChecks } from '../api/client';
import { embedded } from '../report';
import type { Ctx } from '../contexts/Ctx';
import type { Thread } from '../types/thread';

type WorkbenchChange = {
  sessionId?: unknown;
  kind?: unknown;
};

export function useThread(sessionId: string) {
  const [thread, setThread] = useState<Thread>(embedded);

  const comments = thread.comments;
  const checks = thread.checks;

  // 起動時にサーバの thread を取る。エージェントが外から書いたら取り直す
  useEffect(() => {
    let alive = true;
    const pull = () => fetchThread(sessionId).then(t => alive && setThread(t)).catch(() => {});
    const changed = (data: WorkbenchChange) => {
      if (data.sessionId !== sessionId) return;
      if (data.kind === 'report') {
        location.reload();
        return;
      }
      if (data.kind === 'thread') pull();
    };
    pull();
    import.meta.hot?.on('workbench:changed', changed);
    return () => {
      alive = false;
      import.meta.hot?.off('workbench:changed', changed);
    };
  }, [sessionId]);

  const toggleCheck = useCallback((id: string, on: boolean) => {
    setThread(prev => {
      const next = on
        ? [...new Set([...prev.checks, id])]
        : prev.checks.filter(x => x !== id);
      setChecks(sessionId, next).then(setThread).catch(() => {});
      return { ...prev, checks: next };
    });
  }, [sessionId]);

  const ctx: Ctx = useMemo(() => ({
    comments,
    add: c => { addComment(sessionId, c).then(setThread).catch(() => {}); },
    remove: id => { removeComment(sessionId, id).then(setThread).catch(() => {}); },
    reply: (id, body) => { replyTo(sessionId, id, body).then(setThread).catch(() => {}); },
    resolve: id => { resolveComment(sessionId, id).then(setThread).catch(() => {}); },
  }), [comments, sessionId]);

  return { comments, checks, ctx, toggleCheck };
}
