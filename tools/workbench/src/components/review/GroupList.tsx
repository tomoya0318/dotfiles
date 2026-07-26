import { GroupCard } from './GroupCard';
import type { Ctx } from '../../contexts/Ctx';
import type { Group } from '../../types/report';

export function GroupList({ review, rest, ctx, checks, toggleCheck, openGroups, toggleGroup }: {
  review: Group[]; rest: Group[]; ctx: Ctx; checks: string[];
  toggleCheck: (id: string, on: boolean) => void;
  openGroups: string[]; toggleGroup: (id: string) => void;
}) {
  return (
    <>
      <section>
        {review.map(g => (
          <GroupCard key={g.id} group={g} ctx={ctx}
            checked={checks.includes(g.id)} onCheck={v => toggleCheck(g.id, v)}
            open={openGroups.includes(g.id)} onToggle={() => toggleGroup(g.id)} />
        ))}
      </section>

      {rest.length > 0 && (
        <section className="rest">
          <h2>未分類</h2>
          {rest.map(g => (
            <GroupCard key={g.id} group={g} ctx={ctx}
              checked={checks.includes(g.id)} onCheck={v => toggleCheck(g.id, v)}
              open={openGroups.includes(g.id)} onToggle={() => toggleGroup(g.id)} />
          ))}
        </section>
      )}
    </>
  );
}
