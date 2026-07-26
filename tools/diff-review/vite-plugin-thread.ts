import { readFileSync, writeFileSync, mkdirSync, existsSync, watch } from 'node:fs';
import { dirname, resolve } from 'node:path';
import type { Plugin, ViteDevServer } from 'vite';

/**
 * `.review/thread.json` を読み書きする開発サーバ側の口。
 *
 * 書き手は2人いる（ブラウザ = 人間のターン、エージェント = AI のターン）。
 * どちらも「読む → 自分の領域だけ差し替える → 書く」を守る。
 * 丸ごと置き換えにすると、片方が書いている間にもう片方の内容が消える。
 */

type Turn = { by: string; body: string };
type Comment = {
  id: string; hunk: string; side: string; offset: number; lineText: string;
  label?: string; turns: Turn[]; state: string; key?: string; confidence?: string;
};
type Thread = { comments: Comment[]; checks: string[] };

const EMPTY: Thread = { comments: [], checks: [] };

function threadPath(root: string) {
  return resolve(root, process.env.DIFF_REVIEW_THREAD ?? '.review/thread.json');
}

function reportPath(root: string) {
  return resolve(root, process.env.DIFF_REVIEW_REPORT ?? '.review/report.json');
}

function load(path: string): Thread {
  if (!existsSync(path)) return { ...EMPTY };
  try {
    const raw = JSON.parse(readFileSync(path, 'utf8'));
    return { comments: raw.comments ?? [], checks: raw.checks ?? [] };
  } catch {
    return { ...EMPTY };
  }
}

function save(path: string, t: Thread) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(t, null, 1) + '\n');
}

function nextId(cs: Comment[]) {
  const n = cs.reduce((m, c) => Math.max(m, Number(String(c.id).slice(1)) || 0), 0);
  return `c${n + 1}`;
}

function apply(t: Thread, op: string, body: Record<string, unknown>): Thread {
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

function readJson(req: import('node:http').IncomingMessage): Promise<Record<string, unknown>> {
  return new Promise(res => {
    let buf = '';
    req.on('data', c => (buf += c));
    req.on('end', () => {
      try { res(JSON.parse(buf || '{}')); } catch { res({}); }
    });
  });
}

export function threadApi(): Plugin {
  return {
    name: 'diff-review-thread',
    configureServer(server: ViteDevServer) {
      const path = threadPath(server.config.root);
      const report = reportPath(server.config.root);
      let selfWrite = 0;

      // report もサーバから配る。アプリのディレクトリに何も書かないので、
      // 環境変数を変えれば同じ checkout で何本でも並行できる
      server.middlewares.use('/api/report', (_req, res) => {
        res.setHeader('content-type', 'application/json');
        if (!existsSync(report)) {
          res.statusCode = 404;
          res.end(JSON.stringify({ error: `report not found: ${report}` }));
          return;
        }
        res.end(readFileSync(report, 'utf8'));
      });

      // 「人間はもう書かない」の宣言。skill 側はこのファイルを待つ
      server.middlewares.use('/api/handoff', (req, res) => {
        if (req.method === 'POST') {
          writeFileSync(resolve(dirname(path), 'handoff'), new Date().toISOString() + '\n');
        }
        res.setHeader('content-type', 'application/json');
        res.end('{"ok":true}');
      });

      server.middlewares.use('/api/thread', async (req, res) => {
        res.setHeader('content-type', 'application/json');
        if (req.method === 'GET') {
          res.end(JSON.stringify(load(path)));
          return;
        }
        if (req.method === 'POST') {
          const body = await readJson(req);
          const next = apply(load(path), String(body.op), body);
          selfWrite = Date.now();
          save(path, next);
          res.end(JSON.stringify(next));
          return;
        }
        res.statusCode = 405;
        res.end('{}');
      });

      // エージェントが外から書いたときだけ通知する。自分の書き込みで往復させない
      mkdirSync(dirname(path), { recursive: true });
      if (existsSync(dirname(path))) {
        watch(dirname(path), (_e, name) => {
          if (name && !path.endsWith(name)) return;
          if (Date.now() - selfWrite < 500) return;
          server.ws.send({ type: 'custom', event: 'thread:changed' });
        });
      }

      server.config.logger.info(`  ➜  report:  ${report}`);
      server.config.logger.info(`  ➜  thread:  ${path}`);
    },
  };
}
