import { readFileSync, existsSync } from 'node:fs';
import { writeJsonFile } from './fileStore.js';

export type Turn = { by: string; body: string };
export type Comment = {
  id: string; hunk: string; side: string; offset: number; lineText: string;
  label?: string; turns: Turn[]; state: string; key?: string; confidence?: string;
};
export type Thread = { comments: Comment[]; checks: string[] };

const EMPTY: Thread = { comments: [], checks: [] };

export function load(path: string): Thread {
  if (!existsSync(path)) return { ...EMPTY };
  try {
    const raw = JSON.parse(readFileSync(path, 'utf8'));
    return { comments: raw.comments ?? [], checks: raw.checks ?? [] };
  } catch {
    return { ...EMPTY };
  }
}

export function save(path: string, t: Thread) {
  writeJsonFile(path, t);
}

function nextId(cs: Comment[]) {
  const n = cs.reduce((m, c) => Math.max(m, Number(String(c.id).slice(1)) || 0), 0);
  return `c${n + 1}`;
}

export function apply(t: Thread, op: string, body: Record<string, unknown>): Thread {
  switch (op) {
    case 'add': {
      const c = body.comment as Comment;
      return { ...t, comments: [...t.comments, { ...c, id: nextId(t.comments) }] };
    }
    case 'reply': {
      const { id, turn } = body as { id: string; turn: Turn };
      return {
        ...t,
        comments: t.comments.map(c =>
          c.id === id ? { ...c, turns: [...c.turns, turn], state: 'open' } : c),
      };
    }
    case 'remove': {
      const { id } = body as { id: string };
      // AI が触れたスレッドは消させない。相手の領域を削ることになる
      const target = t.comments.find(c => c.id === id);
      if (!target || target.turns.some(x => x.by !== 'you')) return t;
      return { ...t, comments: t.comments.filter(c => c.id !== id) };
    }
    case 'resolve': {
      const { id } = body as { id: string };
      return {
        ...t,
        comments: t.comments.map(c => (c.id === id ? { ...c, state: 'resolved' } : c)),
      };
    }
    case 'checks':
      return { ...t, checks: (body.checks as string[]) ?? [] };
    default:
      return t;
  }
}
