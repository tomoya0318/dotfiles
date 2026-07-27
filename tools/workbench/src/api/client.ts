import { normalizeThread } from '../lib/comment';
import type { Report } from '../types/report';
import type { PlanResponse, PlanStateResponse } from '../types/plan';
import type { Comment, Thread } from '../types/thread';

export type SessionDocuments = {
  plan: boolean;
  review: boolean;
  report: boolean;
  thread: boolean;
};

export type WorkbenchSession = {
  id: string;
  name: string;
  workDir: string;
  updatedAt: string;
  documents: SessionDocuments;
};

export type SessionMeta = Pick<WorkbenchSession, 'name' | 'documents'>;

export type WorkbenchBranch = {
  name: string;
  worktree: string;
  sessions: WorkbenchSession[];
};

export type WorkbenchRepository = {
  name: string;
  root: string;
  branches: WorkbenchBranch[];
};

export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const sessionEndpoint = (sessionId: string, resource: string): string =>
  `/api/sessions/${encodeURIComponent(sessionId)}/${resource}`;

const sessionRoot = (sessionId: string): string =>
  `/api/sessions/${encodeURIComponent(sessionId)}`;

async function errorFrom(res: Response): Promise<ApiError> {
  try {
    const body: unknown = await res.json();
    const message = typeof body === 'object' && body !== null && 'error' in body
      ? String(body.error)
      : res.statusText;
    return new ApiError(res.status, message);
  } catch {
    return new ApiError(res.status, res.statusText || 'request failed');
  }
}

export const fetchSessions = async (): Promise<WorkbenchRepository[]> => {
  const res = await fetch('/api/sessions');
  if (!res.ok) throw await errorFrom(res);
  const body = await res.json() as { repositories?: WorkbenchRepository[] };
  return body.repositories ?? [];
};

export const fetchSession = async (sessionId: string): Promise<SessionMeta> => {
  const res = await fetch(sessionRoot(sessionId));
  if (!res.ok) throw await errorFrom(res);
  return res.json();
};

export const fetchReport = async (sessionId: string): Promise<Report> => {
  const res = await fetch(sessionEndpoint(sessionId, 'report'));
  if (!res.ok) throw await errorFrom(res);
  return res.json();
};

async function post(
  sessionId: string,
  op: string,
  body: Record<string, unknown> = {},
): Promise<Thread> {
  const res = await fetch(sessionEndpoint(sessionId, 'thread'), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ op, ...body }),
  });
  if (!res.ok) throw await errorFrom(res);
  return normalizeThread(await res.json());
}

export const fetchThread = async (sessionId: string): Promise<Thread> => {
  const res = await fetch(sessionEndpoint(sessionId, 'thread'));
  if (!res.ok) throw await errorFrom(res);
  return normalizeThread(await res.json());
};

export const addComment = (sessionId: string, comment: Omit<Comment, 'id'>) =>
  post(sessionId, 'add', { comment });
export const replyTo = (sessionId: string, id: string, body: string) =>
  post(sessionId, 'reply', { id, turn: { by: 'you', body } });
export const removeComment = (sessionId: string, id: string) =>
  post(sessionId, 'remove', { id });
export const resolveComment = (sessionId: string, id: string) =>
  post(sessionId, 'resolve', { id });
export const setChecks = (sessionId: string, checks: string[]) =>
  post(sessionId, 'checks', { checks });

export const handoff = (sessionId: string) =>
  fetch(sessionEndpoint(sessionId, 'handoff'), { method: 'POST' }).catch(() => {});

export const fetchPlan = async (sessionId: string): Promise<PlanResponse> => {
  const res = await fetch(sessionEndpoint(sessionId, 'plan'));
  if (!res.ok) throw await errorFrom(res);
  return res.json();
};

export async function updatePlanState(
  sessionId: string,
  revision: number,
  op: string,
  body: Record<string, unknown> = {},
): Promise<PlanStateResponse> {
  const res = await fetch(sessionEndpoint(sessionId, 'plan/state'), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ revision, op, ...body }),
  });
  if (!res.ok) throw await errorFrom(res);
  return res.json();
}

export async function approvePlan(
  sessionId: string,
  hash: string,
): Promise<PlanResponse> {
  const res = await fetch(sessionEndpoint(sessionId, 'plan/approve'), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ hash }),
  });
  if (!res.ok) throw await errorFrom(res);
  return res.json();
}
