import type { LABELS } from '../lib/comment';

export type Label = (typeof LABELS)[number];

/** 'ai' は旧形式。誰が答えたかを残さないと Claude と Codex を区別できない。 */
export type Author = 'you' | 'claude' | 'codex' | 'ai';
export type Turn = { by: Author; body: string };
export type Classification = '欠陥' | '要件外';

export type Comment = {
  id: string;
  hunk: string;
  side: 'old' | 'new' | 'normal';
  offset: number;
  lineText: string;
  /** 人間発のコメントだけが持つ。AI 発の指摘には無い */
  label?: Label;
  /** AI 発の指摘だけが持つ */
  classification?: Classification;
  /** AI 発の指摘だけが持つ */
  confidence?: '高' | '中' | '低';
  turns: Turn[];
  state: 'open' | 'answered' | 'resolved';
};

/** thread.json は AI が書くので、旧形式 {human, ai} も読めるようにしておく。 */
export type RawComment = Omit<Comment, 'label' | 'turns'> & {
  label?: Label; turns?: Turn[]; human?: string; ai?: string | null;
};

export type Thread = { comments: Comment[]; checks: string[] };

export type Progress = {
  groups: { done: number; total: number; pending: { id: string; title: string }[] };
  openComments: Comment[];
  findings: Comment[];
  notes: number;
  remaining: number;
};
