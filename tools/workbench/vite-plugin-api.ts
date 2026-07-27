import {
  basename,
  dirname,
  isAbsolute,
  resolve,
} from 'node:path';
import {
  existsSync,
  lstatSync,
  readFileSync,
  realpathSync,
  watch,
  writeFileSync,
  type FSWatcher,
} from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { Plugin, ViteDevServer } from 'vite';
import { containedPath, ContainmentError } from './server/contained.js';
import { PlanNotFoundError, readPlan } from './server/planDoc.js';
import {
  applyPlanOperation,
  approvePlan,
  consumePlanApproval,
  getPlanStateResponse,
  makePlanResponse,
  PlanHttpError,
  resetPlanApproval,
  syncPlanState,
} from './server/planStore.js';
import { apply, load, save } from './server/threadStore.js';
import { scanSessions, type WorkbenchSession } from './server/sessions.js';

function sendJson(
  res: ServerResponse,
  status: number,
  body: unknown,
): void {
  res.statusCode = status;
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify(body));
}

function readJson(req: IncomingMessage): Promise<Record<string, unknown>> {
  return new Promise(resolveBody => {
    let buffer = '';
    req.on('data', chunk => (buffer += chunk));
    req.on('end', () => {
      try {
        resolveBody(JSON.parse(buffer || '{}'));
      } catch {
        resolveBody({});
      }
    });
  });
}

function realpathOrResolved(path: string): string {
  const absolute = resolve(path);
  try {
    return realpathSync(absolute);
  } catch {
    return absolute;
  }
}

function requestPath(req: IncomingMessage): string {
  return new URL(req.url ?? '/', 'http://localhost').pathname;
}

function rejectMethod(res: ServerResponse): void {
  sendJson(res, 405, { error: 'method not allowed' });
}

function handleError(res: ServerResponse, error: unknown): void {
  if (error instanceof ContainmentError) {
    sendJson(res, 403, { error: error.message });
    return;
  }
  if (error instanceof PlanNotFoundError) {
    sendJson(res, 404, { error: error.message });
    return;
  }
  if (error instanceof PlanHttpError) {
    sendJson(res, error.status, { error: error.message });
    return;
  }
  sendJson(res, 500, { error: error instanceof Error ? error.message : String(error) });
}

export function workbenchApi(): Plugin {
  return {
    name: 'workbench-api',
    configureServer(server: ViteDevServer) {
      const watchers = new Map<string, {
        workDir?: FSWatcher;
        review?: FSWatcher;
      }>();
      const selfWrites = new Map<string, number>();
      type ChangeKind = 'thread' | 'report' | 'plan' | 'plan-state';

      const selfWriteKey = (sessionId: string, kind: ChangeKind): string =>
        `${sessionId}:${kind}`;
      const markSelfWrite = (
        session: WorkbenchSession,
        kind: ChangeKind,
      ): void => {
        selfWrites.set(selfWriteKey(session.id, kind), Date.now());
      };

      const closeWatcher = (
        sessionId: string,
        kind: 'workDir' | 'review',
      ): void => {
        const sessionWatchers = watchers.get(sessionId);
        const watcher = sessionWatchers?.[kind];
        if (!sessionWatchers || !watcher) return;
        try {
          watcher.close();
        } catch {
          // The watched directory may already have disappeared.
        }
        delete sessionWatchers[kind];
        if (!sessionWatchers.workDir && !sessionWatchers.review) {
          watchers.delete(sessionId);
        }
      };

      const closeSessionWatchers = (sessionId: string): void => {
        closeWatcher(sessionId, 'review');
        closeWatcher(sessionId, 'workDir');
      };

      const sendChange = (
        session: WorkbenchSession,
        kind: ChangeKind,
      ): void => {
        if (
          Date.now() - (selfWrites.get(selfWriteKey(session.id, kind)) ?? 0) < 500
        ) {
          return;
        }
        server.ws.send({
          type: 'custom',
          event: 'workbench:changed',
          data: { sessionId: session.id, kind },
        });
      };

      const ensureReviewWatcher = (session: WorkbenchSession): boolean => {
        const sessionWatchers = watchers.get(session.id);
        if (sessionWatchers?.review) return true;

        let reviewDir: string;
        try {
          const thread = containedPath(session.workDir, 'review/thread.json');
          reviewDir = dirname(thread);
          if (!existsSync(reviewDir) || !lstatSync(reviewDir).isDirectory()) return false;
        } catch {
          return false;
        }

        try {
          const watcher = watch(reviewDir, (_event, fileName) => {
            try {
              if (!existsSync(reviewDir)) {
                closeWatcher(session.id, 'review');
                return;
              }
              const name = fileName?.toString();
              if (
                name !== basename('thread.json')
                && name !== basename('report.json')
                && name !== basename('plan.json')
              ) {
                return;
              }
              const kind = name === 'thread.json'
                ? 'thread'
                : name === 'plan.json'
                  ? 'plan-state'
                  : 'report';
              sendChange(session, kind);
            } catch {
              closeWatcher(session.id, 'review');
            }
          });
          watcher.on('error', () => closeWatcher(session.id, 'review'));
          const current = watchers.get(session.id) ?? {};
          current.review = watcher;
          watchers.set(session.id, current);
          return true;
        } catch {
          // A review directory can disappear between existsSync and watch.
          return false;
        }
      };

      const ensureWatcher = (session: WorkbenchSession): void => {
        const current = watchers.get(session.id) ?? {};
        watchers.set(session.id, current);

        if (!current.workDir) {
          try {
            const workDir = realpathSync(session.workDir);
            const watcher = watch(workDir, (_event, fileName) => {
              try {
                if (!existsSync(workDir)) {
                  closeSessionWatchers(session.id);
                  return;
                }
                const name = fileName?.toString();
                if (name === 'plan.md') {
                  try {
                    const document = readPlan(session.workDir);
                    syncPlanState(
                      session.workDir,
                      document,
                      () => markSelfWrite(session, 'plan-state'),
                    );
                  } catch {
                    // GET will report parse and containment errors to the client.
                  }
                  sendChange(session, 'plan');
                  return;
                }
                if (name !== 'review') return;

                closeWatcher(session.id, 'review');
                if (!ensureReviewWatcher(session)) return;
                const report = containedPath(session.workDir, 'review/report.json');
                if (existsSync(report)) sendChange(session, 'report');
              } catch {
                closeWatcher(session.id, 'review');
              }
            });
            watcher.on('error', () => closeSessionWatchers(session.id));
            current.workDir = watcher;
          } catch {
            // A work directory can disappear between scanning and watch.
          }
        }

        ensureReviewWatcher(session);
      };

      server.httpServer?.once('close', () => {
        for (const sessionId of [...watchers.keys()]) closeSessionWatchers(sessionId);
      });

      server.middlewares.use('/api/health', (req, res, next) => {
        if (requestPath(req) !== '/') {
          next();
          return;
        }
        if (req.method !== 'GET') {
          rejectMethod(res);
          return;
        }
        sendJson(res, 200, { app: 'workbench' });
      });

      server.middlewares.use('/api/resolve', (req, res, next) => {
        if (requestPath(req) !== '/') {
          next();
          return;
        }
        if (req.method !== 'GET') {
          rejectMethod(res);
          return;
        }
        const workDir = new URL(req.url ?? '/', 'http://localhost').searchParams.get('workDir');
        if (!workDir || !isAbsolute(workDir)) {
          sendJson(res, 400, { error: 'absolute workDir is required' });
          return;
        }
        const requestedWorkDir = realpathOrResolved(workDir);
        const session = [...scanSessions().byId.values()]
          .find(candidate => realpathOrResolved(candidate.workDir) === requestedWorkDir);
        if (!session) {
          sendJson(res, 404, { error: 'session not found' });
          return;
        }
        sendJson(res, 200, { id: session.id, workDir: session.workDir });
      });

      server.middlewares.use('/api/sessions', async (req, res, next) => {
        const path = requestPath(req);
        if (path === '/') {
          if (req.method !== 'GET') {
            rejectMethod(res);
            return;
          }
          sendJson(res, 200, { repositories: scanSessions().repositories });
          return;
        }

        const sessionMatch = path.match(/^\/([^/]+)\/?$/);
        if (sessionMatch) {
          if (req.method !== 'GET') {
            rejectMethod(res);
            return;
          }
          const session = scanSessions().byId.get(sessionMatch[1]);
          if (!session) {
            sendJson(res, 404, { error: 'session not found' });
            return;
          }
          sendJson(res, 200, {
            name: session.name,
            documents: session.documents,
          });
          return;
        }

        const planMatch = path.match(
          /^\/([^/]+)\/plan(?:\/(state|approve|approve\/(consume|reset)))?\/?$/,
        );
        if (planMatch) {
          const [, id, action] = planMatch;
          const session = scanSessions().byId.get(id);
          if (!session) {
            sendJson(res, 404, { error: 'session not found' });
            return;
          }

          ensureWatcher(session);
          try {
            const document = readPlan(session.workDir);
            if (!action) {
              if (req.method !== 'GET') {
                rejectMethod(res);
                return;
              }
              const synced = syncPlanState(
                session.workDir,
                document,
                () => markSelfWrite(session, 'plan-state'),
              );
              sendJson(res, 200, makePlanResponse(document, synced));
              return;
            }

            if (action === 'state') {
              if (req.method === 'GET') {
                const synced = syncPlanState(
                  session.workDir,
                  document,
                  () => markSelfWrite(session, 'plan-state'),
                );
                sendJson(res, 200, getPlanStateResponse(document, synced));
                return;
              }
              if (req.method === 'POST') {
                const body = await readJson(req);
                const currentDocument = readPlan(session.workDir);
                sendJson(
                  res,
                  200,
                  applyPlanOperation(
                    session.workDir,
                    currentDocument,
                    body,
                    () => markSelfWrite(session, 'plan-state'),
                  ),
                );
                return;
              }
              rejectMethod(res);
              return;
            }

            if (req.method !== 'POST') {
              rejectMethod(res);
              return;
            }
            const body = await readJson(req);
            if (action === 'approve') {
              sendJson(
                res,
                200,
                approvePlan(
                  session.workDir,
                  body.hash,
                  () => markSelfWrite(session, 'plan-state'),
                ),
              );
              return;
            }
            if (action === 'approve/consume') {
              const currentDocument = readPlan(session.workDir);
              sendJson(
                res,
                200,
                consumePlanApproval(
                  session.workDir,
                  currentDocument,
                  body.nonce,
                  () => markSelfWrite(session, 'plan-state'),
                ),
              );
              return;
            }
            const currentDocument = readPlan(session.workDir);
            sendJson(
              res,
              200,
              resetPlanApproval(
                session.workDir,
                currentDocument,
                () => markSelfWrite(session, 'plan-state'),
              ),
            );
          } catch (error) {
            handleError(res, error);
          }
          return;
        }

        const match = path.match(/^\/([^/]+)\/(report|thread|handoff)\/?$/);
        if (!match) {
          next();
          return;
        }

        const [, id, resource] = match;
        const session = scanSessions().byId.get(id);
        if (!session) {
          sendJson(res, 404, { error: 'session not found' });
          return;
        }

        try {
          if (resource === 'report') {
            if (req.method !== 'GET') {
              rejectMethod(res);
              return;
            }
            const report = containedPath(session.workDir, 'review/report.json');
            ensureWatcher(session);
            if (!existsSync(report)) {
              sendJson(res, 404, { error: 'report not found' });
              return;
            }
            res.statusCode = 200;
            res.setHeader('content-type', 'application/json');
            res.end(readFileSync(report, 'utf8'));
            return;
          }

          if (resource === 'handoff') {
            if (req.method !== 'POST') {
              rejectMethod(res);
              return;
            }
            const handoff = containedPath(session.workDir, 'review/handoff', true);
            writeFileSync(handoff, `${new Date().toISOString()}\n`);
            sendJson(res, 200, { ok: true });
            return;
          }

          const thread = containedPath(
            session.workDir,
            'review/thread.json',
            req.method === 'POST',
          );
          ensureWatcher(session);
          if (req.method === 'GET') {
            sendJson(res, 200, load(thread));
            return;
          }
          if (req.method === 'POST') {
            const body = await readJson(req);
            const nextThread = apply(load(thread), String(body.op), body);
            markSelfWrite(session, 'thread');
            save(thread, nextThread);
            sendJson(res, 200, nextThread);
            return;
          }
          rejectMethod(res);
        } catch (error) {
          handleError(res, error);
        }
      });

      // Keep this last: otherwise Vite's SPA fallback turns unmatched API GETs into HTML 200s.
      server.middlewares.use('/api', (_req, res) => {
        sendJson(res, 404, { error: 'API endpoint not found' });
      });
    },
  };
}
