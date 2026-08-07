import { firstLine, isFinding, LABEL_TEXT } from '../../lib/comment';
import { groupOfElement } from '../../report';
import type { Progress } from '../../types/thread';

export function RemainingList({ progress, jumpTo }: {
  progress: Progress; jumpTo: (sel: string, groupId?: string) => void;
}) {
  return (
    <ul className="remaining">
      {progress.groups.pending.map(g => (
        <li key={g.id}>
          <button onClick={() => jumpTo(`#g-${g.id}`)}>
            <span className="chip id">{g.id}</span>
            <span className="chip kind">未判断</span>
            <span className="txt">{g.title}</span>
          </button>
        </li>
      ))}
      {progress.openComments.map(c => (
        <li key={c.id}>
          <button onClick={() => jumpTo(`#c-${c.id}`, groupOfElement.get(c.hunk))}>
            <span className="chip id">{c.hunk}</span>
            <span className={`chip ${isFinding(c) ? 'finding' : `l-${c.label}`}`}>
              {isFinding(c) ? '指摘' : LABEL_TEXT[c.label ?? 'question']}
            </span>
            {c.classification && <span className="chip classification">{c.classification}</span>}
            {c.confidence && <span className={`chip conf c-${c.confidence}`}>{c.confidence}</span>}
            <span className="txt">{firstLine(c)}</span>
          </button>
        </li>
      ))}
    </ul>
  );
}
