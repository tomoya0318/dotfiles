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
