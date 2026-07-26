import { parseDiff } from 'react-diff-view';
import { firstLine, isFinding, LABEL_TEXT, resolveOffset } from '../../lib/comment';
import { fileById, hunkById } from '../../report';
import type { Comment } from '../../types/thread';

/** アンカーが外れたコメント。行が消えたか書き換わった証拠なので捨てずに出す。 */
export function LostComments({ comments }: { comments: Comment[] }) {
  const lost = comments.filter(c => {
    const h = hunkById.get(c.hunk);
    const f = h && fileById.get(h.fileId);
    if (!f) return true;
    try {
      const changes = parseDiff(f.diff)[0]?.hunks?.[h.index]?.changes ?? [];
      return resolveOffset(changes, c) === null;
    } catch {
      return true;
    }
  });
  if (!lost.length) return null;
  return (
    <section className="lost">
      <h2>迷子コメント {lost.length} 件 — 元の行が見つからない</h2>
      {lost.map(c => (
        <div key={c.id} className={`comment open ${isFinding(c) ? 'finding' : `l-${c.label}`}`}>
          <div className="speaker">
            <span className="tag">{isFinding(c) ? '指摘' : LABEL_TEXT[c.label ?? 'question']}</span>
            {c.hunk} <code>{c.lineText.trim()}</code>
          </div>
          <p>{firstLine(c)}</p>
        </div>
      ))}
    </section>
  );
}
