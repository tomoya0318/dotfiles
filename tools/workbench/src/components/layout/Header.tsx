import { report } from '../../report';
import type { Group } from '../../types/report';

export function Header({ review, foldCount }: { review: Group[]; foldCount: number }) {
  const s = report.stats;
  return (
    <header>
      <h1>{report.subject}</h1>
      <div className="stats">
        <span>{s.files} files</span>
        <span>{s.hunks} hunks</span>
        <span className="plus">+{s.additions}</span>
        <span className="minus">−{s.deletions}</span>
        <code className="ref on">{report.ref}</code>
      </div>
      <p className="lede">
        <strong>読むべき {review.length} グループ</strong>
        <span className="muted"> — 波及 {foldCount} 件は畳んである</span>
      </p>
    </header>
  );
}
