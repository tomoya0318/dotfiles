import { normalizeThread } from './lib/comment';
import type { FileEntry, FileOp, Hunk, Report } from './types/report';
import type { Thread } from './types/thread';

// init() で埋まる。live binding なので、読む側は普通の const のように書ける
export let report: Report;
export let hunkById: Map<string, Hunk>;
export let opById: Map<string, FileOp>;
export let fileById: Map<string, FileEntry>;
export let groupOfElement: Map<string, string>;
/** サーバが無いとき用の初期値。通常は /api/thread が正。 */
export let embedded: Thread;

export function init(raw: Report) {
  report = raw;
  hunkById = new Map(raw.hunks.map(h => [h.id, h]));
  opById = new Map(raw.fileOps.map(o => [o.id, o]));
  fileById = new Map(raw.files.map(f => [f.id, f]));
  groupOfElement = new Map();
  for (const g of raw.groups) {
    for (const id of [...g.core, ...g.ripple]) groupOfElement.set(id, g.id);
  }
  embedded = normalizeThread(raw.thread ?? {});
}
