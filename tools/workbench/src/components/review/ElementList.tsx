import { DiffOfHunk } from './HunkDiff';
import { OpView } from './FileOpView';
import { isOp } from '../../lib/element';
import { hunkById, opById } from '../../report';
import type { Ctx } from '../../contexts/Ctx';

export function Elements({ ids, ctx }: { ids: string[]; ctx: Ctx }) {
  return (
    <>
      {ids.map(id => {
        const el = opById.get(id) ?? hunkById.get(id);
        if (!el) return null;
        return isOp(el) ? <OpView key={id} op={el} /> : <DiffOfHunk key={id} hunk={el} ctx={ctx} />;
      })}
    </>
  );
}
