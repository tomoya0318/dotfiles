import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

export function writeJsonFile(path: string, value: unknown): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 1)}\n`);
}

export function sequentialId(
  ids: Iterable<string>,
  prefix: string,
): () => string {
  let next = 1n;
  const pattern = new RegExp(`^${prefix}(\\d+)$`);
  for (const id of ids) {
    const match = id.match(pattern);
    if (match) {
      const candidate = BigInt(match[1]) + 1n;
      if (candidate > next) next = candidate;
    }
  }
  return () => `${prefix}${next++}`;
}
