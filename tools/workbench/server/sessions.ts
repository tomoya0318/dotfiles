import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  existsSync,
  lstatSync,
  readdirSync,
  statSync,
} from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { readRoots } from './roots.js';

const WORKTREE_TTL_MS = 5_000;
const SESSION_NAME = /^[0-9]{4}_.+$/;

type Worktree = {
  path: string;
  head: string;
  branch: string;
  bare: boolean;
  prunable: boolean;
};

export type SessionDocuments = {
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

export type SessionCatalog = {
  repositories: WorkbenchRepository[];
  byId: Map<string, WorkbenchSession>;
};

const worktreeCache = new Map<string, { expiresAt: number; worktrees: Worktree[] }>();

function parseWorktrees(output: string): Worktree[] {
  return output
    .trim()
    .split(/\n\n+/)
    .filter(Boolean)
    .map(record => {
      const lines = record.split('\n');
      const worktree = lines.find(line => line.startsWith('worktree '))?.slice(9) ?? '';
      const head = lines.find(line => line.startsWith('HEAD '))?.slice(5) ?? '';
      const branchRef = lines.find(line => line.startsWith('branch '))?.slice(7);
      return {
        path: worktree,
        head,
        branch: branchRef?.replace(/^refs\/heads\//, '') ?? head.slice(0, 12),
        bare: lines.includes('bare'),
        prunable: lines.some(line => line === 'prunable' || line.startsWith('prunable ')),
      };
    });
}

function listWorktrees(root: string): Worktree[] {
  const cached = worktreeCache.get(root);
  if (cached && cached.expiresAt > Date.now()) return cached.worktrees;

  const output = execFileSync(
    'git',
    ['-C', root, 'worktree', 'list', '--porcelain'],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
  );
  const worktrees = parseWorktrees(output);
  worktreeCache.set(root, { expiresAt: Date.now() + WORKTREE_TTL_MS, worktrees });
  return worktrees;
}

function urlPart(value: string, fallback: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, '') || fallback;
}

function sessionId(repositoryName: string, workDir: string, directoryName: string): string {
  const hash = createHash('sha256').update(workDir).digest('hex').slice(0, 12);
  return [
    urlPart(repositoryName, 'repo'),
    hash,
    urlPart(directoryName, 'session'),
  ].join('-');
}

function documentState(workDir: string): {
  documents: SessionDocuments;
  updatedAt: string;
} {
  const paths = {
    review: join(workDir, 'review.md'),
    report: join(workDir, 'review', 'report.json'),
    thread: join(workDir, 'review', 'thread.json'),
  };
  const metadata = {} as Record<keyof SessionDocuments, number | null>;
  for (const [name, path] of Object.entries(paths)) {
    try {
      metadata[name as keyof SessionDocuments] = lstatSync(path).mtimeMs;
    } catch {
      metadata[name as keyof SessionDocuments] = null;
    }
  }
  const documents = {
    review: metadata.review !== null,
    report: metadata.report !== null,
    thread: metadata.thread !== null,
  };
  const mtimes = [statSync(workDir).mtimeMs];
  for (const value of Object.values(metadata)) {
    if (value !== null) mtimes.push(value);
  }
  return {
    documents,
    updatedAt: new Date(Math.max(...mtimes)).toISOString(),
  };
}

function sessionsForWorktree(
  repositoryName: string,
  worktree: Worktree,
): WorkbenchSession[] {
  const tmp = join(worktree.path, 'tmp');
  if (!existsSync(tmp)) return [];

  const sessions: WorkbenchSession[] = [];
  for (const entry of readdirSync(tmp, { withFileTypes: true })) {
    if (!entry.isDirectory() || !SESSION_NAME.test(entry.name)) continue;
    const workDir = resolve(tmp, entry.name);
    try {
      const { documents, updatedAt } = documentState(workDir);
      sessions.push({
        id: sessionId(repositoryName, workDir, entry.name),
        name: entry.name,
        workDir,
        updatedAt,
        documents,
      });
    } catch {
      // A session can disappear while the directory is being scanned.
    }
  }
  return sessions.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export function scanSessions(): SessionCatalog {
  const repositories: WorkbenchRepository[] = [];
  const byId = new Map<string, WorkbenchSession>();

  for (const registeredRoot of readRoots()) {
    try {
      const root = resolve(registeredRoot);
      const repositoryName = basename(root);
      const branches: WorkbenchBranch[] = [];
      for (const worktree of listWorktrees(root)) {
        if (
          worktree.bare
          || worktree.prunable
          || !worktree.path
          || !existsSync(worktree.path)
        ) {
          continue;
        }
        try {
          const sessions = sessionsForWorktree(repositoryName, worktree);
          for (const session of sessions) byId.set(session.id, session);
          branches.push({
            name: worktree.branch || worktree.head.slice(0, 12),
            worktree: resolve(worktree.path),
            sessions,
          });
        } catch {
          // One missing checkout must not hide the repository's other worktrees.
        }
      }
      repositories.push({ name: repositoryName, root, branches });
    } catch {
      // Stale roots are expected because the registry is append-only.
    }
  }

  repositories.sort((a, b) => a.name.localeCompare(b.name));
  return { repositories, byId };
}
