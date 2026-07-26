import type { ChangeData } from 'react-diff-view';

/** 左ほど要求が弱い。スライダーの並び順そのもの。 */
export const LABELS = ['note', 'question', 'fix'] as const;
export type Label = (typeof LABELS)[number];

export const LABEL_TEXT: Record<Label, string> = { note: '所感', question: '質問', fix: '要修正' };

/** 'ai' は旧形式。誰が答えたかを残さないと Claude と Codex を区別できない。 */
export type Author = 'you' | 'claude' | 'codex' | 'ai';
export type Turn = { by: Author; body: string };

export const AUTHOR_NAME: Record<Author, string> = {
  you: 'あなた', claude: 'Claude', codex: 'Codex', ai: 'AI',
};
export const isHuman = (by: Author) => by === 'you';

export type Comment = {
  id: string;
  hunk: string;
  side: 'old' | 'new' | 'normal';
  offset: number;
  lineText: string;
  /** 人間発のコメントだけが持つ。AI 発の指摘には無い */
  label?: Label;
  /** AI 発の指摘だけが持つ */
  confidence?: '高' | '中' | '低';
  turns: Turn[];
  state: 'open' | 'answered' | 'resolved';
};

/** thread.json は AI が書くので、旧形式 {human, ai} も読めるようにしておく。 */
type RawComment = Omit<Comment, 'label' | 'turns'> & {
  label?: Label; turns?: Turn[]; human?: string; ai?: string | null;
};

export function normalize(c: RawComment): Comment {
  const { human, ai, ...rest } = c;
  const turns: Turn[] = (c.turns ?? [
    ...(human ? [{ by: 'you' as const, body: human }] : []),
    ...(ai ? [{ by: 'ai' as const, body: ai }] : []),
  ]).map(t => ({ ...t, by: (t.by as string) === 'human' ? 'you' : t.by }));
  // AI 発には label を付けない。label は人間の要求の強さを表すもの
  const label = turns[0]?.by === 'you' ? (c.label ?? 'question') : c.label;
  return { ...rest, label, turns };
}

export const lastTurn = (c: Comment) => c.turns[c.turns.length - 1];
/** 検証者が起票したもの。人間がトリアージするまで閉じない */
export const isFinding = (c: Comment) => c.turns[0] !== undefined && c.turns[0].by !== 'you';
export const firstLine = (c: Comment) => (c.turns[0]?.body ?? '').trim().split('\n')[0];

/** 所感は解決すべきものではないので、残数に数えない。 */
export const countsAsOpen = (c: Comment) => c.state === 'open' && c.label !== 'note';

/** 再生成で行番号はずれるので、lineText で探し直す。見つからなければ迷子。 */
export function resolveOffset(changes: ChangeData[], c: Comment): number | null {
  if (changes[c.offset]?.content === c.lineText) return c.offset;
  const found = changes.findIndex(ch => ch.content === c.lineText);
  return found === -1 ? null : found;
}

export type Thread = { comments: Comment[]; checks: string[] };

async function post(op: string, body: Record<string, unknown> = {}): Promise<Thread> {
  const res = await fetch('/api/thread', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ op, ...body }),
  });
  return normalizeThread(await res.json());
}

export function normalizeThread(t: { comments?: unknown[]; checks?: string[] }): Thread {
  return {
    comments: (t.comments ?? []).map(c => normalize(c as RawComment)),
    checks: t.checks ?? [],
  };
}

export const fetchThread = async (): Promise<Thread> =>
  normalizeThread(await (await fetch('/api/thread')).json());

export const addComment = (comment: Omit<Comment, 'id'>) => post('add', { comment });
export const replyTo = (id: string, body: string) => post('reply', { id, turn: { by: 'you', body } });
export const removeComment = (id: string) => post('remove', { id });
export const resolveComment = (id: string) => post('resolve', { id });
export const setChecks = (checks: string[]) => post('checks', { checks });

export type Progress = {
  groups: { done: number; total: number; pending: { id: string; title: string }[] };
  openComments: Comment[];
  findings: Comment[];
  notes: number;
  remaining: number;
};

/**
 * ③→④ の合図。中身は thread.json にあるので、ここに載せるのは
 * ロックの受け渡しと、別セッションに貼っても通じるだけの前提。
 */
export function copyBlock(
  ref: string, repo: string, threadPath: string, progress: Progress,
): string {
  const p = progress;
  const pending = p.groups.pending.map(g => g.id).join(', ');
  return [
    '<!-- diff-review -->',
    'レビューを終えた。以降 `thread.json` は触らないので、あなたが書いてよい。',
    '',
    `- 対象: \`${repo}\` の \`${ref}\``,
    `- スレッド: \`${threadPath}\``,
    '',
    '`state: "open"` のコメントに対応する。',
    '',
    '`turns[0].by` が `you` でないものは検証者の指摘で、人間のトリアージ待ち。**触らない。**',
    '',
    '- `label: "fix"` … コードを直す',
    '- `label: "question"` … **コードを変えない。** 現物を確認して答えるだけ',
    '- `label: "note"` … 対応不要。`state` を `resolved` にする',
    '',
    '対応したら `turns` の末尾に自分の発言を足し、`state` を `answered` にする。',
    '`by` は Claude なら `claude`、Codex なら `codex`。',
    '人間の `turns` と `label` は書き換えない。',
    'ファイルを読んでから自分のターンだけ足す。丸ごと置き換えると人間のコメントが消える。',
    '',
    'コメントに書かれていないことはしない。気づいた点は直さず、返答の中で述べる。',
    '',
    `未解決 ${p.openComments.length}（うち未トリアージの指摘 ${p.findings.length}） / ` +
      `グループ判断 ${p.groups.done}/${p.groups.total}` +
      (pending ? `（未判断: ${pending}）` : ''),
    '',
  ].join('\n');
}

export const handoff = () => fetch('/api/handoff', { method: 'POST' }).catch(() => {});
