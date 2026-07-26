import { useState } from 'react';
import { Elements } from './ElementList';
import { countsAsOpen } from '../../lib/comment';
import type { Ctx } from '../../contexts/Ctx';
import type { Group } from '../../types/report';

export function GroupCard({ group, ctx, checked, onCheck, open, onToggle }: {
  group: Group; ctx: Ctx; checked: boolean; onCheck: (v: boolean) => void;
  open: boolean; onToggle: () => void;
}) {
  const [showRipple, setShowRipple] = useState(false);
  const unknown = group.tags.includes('意図不明');
  const ids = new Set([...group.core, ...group.ripple]);
  const n = ctx.comments.filter(c => ids.has(c.hunk) && countsAsOpen(c)).length;
  const body = open && !checked;

  return (
    <article id={`g-${group.id}`} className={`card${unknown ? ' unknown' : ''}${checked ? ' checked' : ''}`}>
      <div className="card-head">
        <input
          type="checkbox"
          checked={checked}
          aria-label={`${group.title} の判断を済ませる`}
          onChange={e => onCheck(e.target.checked)}
        />
        <button className="head-main" onClick={() => !checked && onToggle()} aria-expanded={body}>
          <span className={`chev${body ? ' open' : ''}`} aria-hidden>›</span>
          <span className="title">{group.title}</span>
          {n > 0 && <span className="badge">{n}</span>}
          <span className="counts">
            判断 {group.core.length}
            {group.ripple.length > 0 && <span className="muted"> / 波及 {group.ripple.length}</span>}
          </span>
        </button>
      </div>

      {!checked && (unknown
        ? <p className="reason none">意図を1文で書けなかった</p>
        : <p className="reason">{group.reason}</p>)}

      {body && (
        <div className="body">
          <Elements ids={group.core} ctx={ctx} />
          {group.ripple.length > 0 && (
            <>
              <button className="fold" onClick={() => setShowRipple(s => !s)}>
                {showRipple ? '▾' : '▸'} 波及 {group.ripple.length} 件
              </button>
              {showRipple && <div className="ripple"><Elements ids={group.ripple} ctx={ctx} /></div>}
            </>
          )}
        </div>
      )}
    </article>
  );
}
