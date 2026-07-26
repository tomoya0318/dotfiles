import { useCallback, useEffect, useMemo, useState } from 'react';
import { addComment, fetchThread, removeComment, replyTo, resolveComment, setChecks } from '../api/client';
import { embedded } from '../report';
import type { Ctx } from '../contexts/Ctx';
import type { Thread } from '../types/thread';

export function useThread() {
  const [thread, setThread] = useState<Thread>(embedded);

  const comments = thread.comments;
  const checks = thread.checks;

  // 起動時にサーバの thread を取る。エージェントが外から書いたら取り直す
  useEffect(() => {
    let alive = true;
    const pull = () => fetchThread().then(t => alive && setThread(t)).catch(() => {});
    pull();
    import.meta.hot?.on('thread:changed', pull);
    return () => { alive = false; };
  }, []);

  const toggleCheck = useCallback((id: string, on: boolean) => {
    setThread(prev => {
      const next = on
        ? [...new Set([...prev.checks, id])]
        : prev.checks.filter(x => x !== id);
      setChecks(next).then(setThread).catch(() => {});
      return { ...prev, checks: next };
    });
  }, []);

  const ctx: Ctx = useMemo(() => ({
    comments,
    add: c => { addComment(c).then(setThread).catch(() => {}); },
    remove: id => { removeComment(id).then(setThread).catch(() => {}); },
    reply: (id, body) => { replyTo(id, body).then(setThread).catch(() => {}); },
    resolve: id => { resolveComment(id).then(setThread).catch(() => {}); },
  }), [comments]);

  return { comments, checks, ctx, toggleCheck };
}
