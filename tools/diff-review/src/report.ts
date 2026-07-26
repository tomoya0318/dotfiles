import { normalizeThread, type Thread } from './thread';

export type Hunk = {
  id: string; file: string; fileId: string; index: number;
  kinds: string[]; coreCandidate: boolean; add: number; del: number;
};
export type FileOp = {
  id: string; kind: 'move' | 'add' | 'delete'; from?: string; to?: string; dir?: string;
  files: { old?: string; new?: string; silent?: boolean }[]; silentCount: number;
};
export type Group = {
  id: string; title: string; tags: string[]; reason: string; core: string[]; ripple: string[];
};
export type FileEntry = {
  id: string; old: string | null; new: string | null; path: string; diff: string; hunks: string[];
};
export type Report = {
  ref: string; subject: string; repo: string; threadPath: string;
  stats: { files: number; hunks: number; additions: number; deletions: number; coreCandidates: number };
  files: FileEntry[]; hunks: Hunk[]; fileOps: FileOp[]; groups: Group[];
  thread?: { comments?: unknown[]; checks?: string[] };
};

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

export const fetchReport = async (): Promise<Report> => {
  const res = await fetch('/api/report');
  if (!res.ok) throw new Error((await res.json()).error ?? 'report not found');
  return res.json();
};
