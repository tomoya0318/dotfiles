import { normalizeThread } from '../lib/comment';
import type { Report } from '../types/report';
import type { Comment, Thread } from '../types/thread';

export const fetchReport = async (): Promise<Report> => {
  const res = await fetch('/api/report');
  if (!res.ok) throw new Error((await res.json()).error ?? 'report not found');
  return res.json();
};

async function post(op: string, body: Record<string, unknown> = {}): Promise<Thread> {
  const res = await fetch('/api/thread', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ op, ...body }),
  });
  return normalizeThread(await res.json());
}

export const fetchThread = async (): Promise<Thread> =>
  normalizeThread(await (await fetch('/api/thread')).json());

export const addComment = (comment: Omit<Comment, 'id'>) => post('add', { comment });
export const replyTo = (id: string, body: string) => post('reply', { id, turn: { by: 'you', body } });
export const removeComment = (id: string) => post('remove', { id });
export const resolveComment = (id: string) => post('resolve', { id });
export const setChecks = (checks: string[]) => post('checks', { checks });

export const handoff = () => fetch('/api/handoff', { method: 'POST' }).catch(() => {});
