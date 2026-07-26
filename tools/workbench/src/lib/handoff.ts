import type { Progress } from '../types/thread';

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
    '<!-- workbench -->',
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
