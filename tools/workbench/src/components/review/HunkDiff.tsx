import { useMemo, useState } from 'react';
import { parseDiff, Diff, Hunk as HunkRow, getChangeKey } from 'react-diff-view';
import { CommentView } from '../comment/CommentView';
import { Composer } from '../comment/Composer';
import { resolveOffset } from '../../lib/comment';
import { sideOf } from '../../lib/diff';
import { fileById } from '../../report';
import type { Ctx } from '../../contexts/Ctx';
import type { Hunk } from '../../types/report';

export function DiffOfHunk({ hunk, ctx }: { hunk: Hunk; ctx: Ctx }) {
  const [composeAt, setComposeAt] = useState<number | null>(null);

  const parsed = useMemo(() => {
    const file = fileById.get(hunk.fileId);
    if (!file) return null;
    try {
      return parseDiff(file.diff)[0] ?? null;
    } catch {
      return null;
    }
  }, [hunk.fileId]);

  const target = parsed?.hunks?.[hunk.index];
  const changes = target?.changes ?? [];
  const mine = ctx.comments.filter(c => c.hunk === hunk.id);
  // アンカーが外れたものは迷子欄に出るので、この hunk のバッジには数えない
  const anchored = mine.filter(c => resolveOffset(changes, c) !== null).length;

  const widgets = useMemo(() => {
    const w: Record<string, React.ReactNode> = {};
    const at = (i: number, node: React.ReactNode) => {
      const ch = changes[i];
      if (!ch) return;
      const k = getChangeKey(ch);
      w[k] = <>{w[k]}{node}</>;
    };
    for (const c of mine) {
      const i = resolveOffset(changes, c);
      if (i === null) continue;
      at(i, <CommentView key={c.id} c={c}
        onRemove={() => ctx.remove(c.id)}
        onReply={body => ctx.reply(c.id, body)}
        onResolve={() => ctx.resolve(c.id)} />);
    }
    if (composeAt !== null) {
      at(composeAt, (
        <Composer
          key="composer"
          onCancel={() => setComposeAt(null)}
          onSave={(text, label) => {
            const ch = changes[composeAt];
            ctx.add({
              hunk: hunk.id, side: sideOf(ch), offset: composeAt, lineText: ch.content,
              label, turns: [{ by: 'you', body: text }], state: 'open',
            });
            setComposeAt(null);
          }}
        />
      ));
    }
    return w;
  }, [changes, mine, composeAt, ctx, hunk.id]);

  return (
    <div className="hunk">
      <div className="el-head">
        <span className="hid">{hunk.id}</span>
        <span className="path">{hunk.file}</span>
        {anchored > 0 && <span className="badge">{anchored}</span>}
        <span className="delta"><span className="plus">+{hunk.add}</span> <span className="minus">−{hunk.del}</span></span>
      </div>
      {parsed && target ? (
        <Diff
          viewType="unified"
          diffType={parsed.type}
          hunks={[target]}
          widgets={widgets}
          codeEvents={{
            onClick: ({ change }) => {
              const i = changes.findIndex(c => c === change);
              if (i !== -1) setComposeAt(cur => (cur === i ? null : i));
            },
          }}
        >
          {hunks => hunks.map(h => <HunkRow key={h.content} hunk={h} />)}
        </Diff>
      ) : (
        <div className="missing">差分を復元できなかった</div>
      )}
    </div>
  );
}
