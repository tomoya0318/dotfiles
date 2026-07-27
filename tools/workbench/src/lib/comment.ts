import type { ChangeData } from 'react-diff-view';
import type { Author, Comment, Label, RawComment, Thread, Turn } from '../types/thread';

/** 左ほど要求が弱い。スライダーの並び順そのもの。 */
export const LABELS = ['note', 'question', 'fix'] as const;

export const LABEL_TEXT: Record<Label, string> = { note: '所感', question: '質問', fix: '要修正' };

export const AUTHOR_NAME: Record<Author, string> = {
  you: 'あなた', claude: 'Claude', codex: 'Codex', ai: 'AI',
};
export const isHuman = (by: Author) => by === 'you';

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

export const countsAsPlanOpen = (
  c: Pick<Comment, 'state' | 'label'>,
) => c.state !== 'resolved' && c.label !== 'note';

/** 再生成で行番号はずれるので、lineText で探し直す。見つからなければ迷子。 */
export function resolveOffset(changes: ChangeData[], c: Comment): number | null {
  if (changes[c.offset]?.content === c.lineText) return c.offset;
  const found = changes.findIndex(ch => ch.content === c.lineText);
  return found === -1 ? null : found;
}

export function normalizeThread(t: { comments?: unknown[]; checks?: string[] }): Thread {
  return {
    comments: (t.comments ?? []).map(c => normalize(c as RawComment)),
    checks: t.checks ?? [],
  };
}
