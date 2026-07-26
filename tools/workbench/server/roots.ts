import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join } from 'node:path';

function stateDir(): string {
  return process.env.WORKBENCH_STATE_DIR
    ?? join(homedir(), '.local', 'state', 'workbench');
}

export function rootsPath(): string {
  return join(stateDir(), 'roots.json');
}

export function readRoots(): string[] {
  try {
    const value: unknown = JSON.parse(readFileSync(rootsPath(), 'utf8'));
    if (!Array.isArray(value)) return [];
    return [...new Set(value.filter((root): root is string =>
      typeof root === 'string' && isAbsolute(root)))];
  } catch {
    return [];
  }
}
