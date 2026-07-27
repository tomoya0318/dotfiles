import { useState } from 'react';
import type { RefObject } from 'react';
import type { SessionMeta } from '../../api/client';
import type { PlanApproval, SessionView } from '../../types/plan';
import { ViewToggle } from '../session/ViewToggle';

export type PlanRemainingItem = {
  id: string;
  target: string;
  kind: '未確認' | '未決' | 'コメント';
  title: string;
};

function formatTime(value: string): string {
  return new Intl.DateTimeFormat('ja-JP', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
}

export function PlanHeader({
  bar,
  session,
  view,
  onViewChange,
  confirmed,
  confirmationTotal,
  undecided,
  openComments,
  remaining,
  warnings,
  approval,
  approvalInvalidated,
  approvalProblems,
  busy,
  allDetailsExpanded,
  onToggleDetails,
  onApprove,
}: {
  bar: RefObject<HTMLDivElement | null>;
  session: SessionMeta;
  view: SessionView;
  onViewChange: (view: SessionView) => void;
  confirmed: number;
  confirmationTotal: number;
  undecided: number;
  openComments: number;
  remaining: PlanRemainingItem[];
  warnings: string[];
  approval: PlanApproval | null;
  approvalInvalidated: boolean;
  approvalProblems: string[];
  busy: boolean;
  allDetailsExpanded: boolean;
  onToggleDetails: () => void;
  onApprove: () => void;
}) {
  const [showRemaining, setShowRemaining] = useState(false);
  const approvalCurrent = approval && !approval.consumedAt;
  const disabled = busy || approvalProblems.length > 0 || Boolean(approvalCurrent);
  const disabledReason = approvalCurrent
    ? 'この plan は承認済みです'
    : approvalProblems.join('、');

  const jump = (target: string) => {
    document.getElementById(target)?.scrollIntoView({ behavior: 'smooth' });
    setShowRemaining(false);
  };

  return (
    <div className="progress plan-progress" ref={bar}>
      <div className="progress-row plan-progress-row">
        <div className="plan-progress-left">
          <a className="home-link" href="/">workbench</a>
          <strong>{session.name}</strong>
          <ViewToggle view={view} hasPlan={session.documents.plan} onChange={onViewChange} />
          <button className="plan-detail-toggle" onClick={onToggleDetails}>
            {allDetailsExpanded ? '詳細をすべて畳む' : '詳細をすべて展開'}
          </button>
        </div>
        <button
          className="progress-main plan-progress-main"
          onClick={() => setShowRemaining(value => !value)}
          aria-expanded={showRemaining}
          disabled={remaining.length === 0}
        >
          <span className={`chev${showRemaining ? ' open' : ''}`} aria-hidden>›</span>
          <span>確認 {confirmed} / {confirmationTotal}</span>
          <span className={undecided > 0 ? 'danger' : ''}>未決 {undecided}</span>
          <span className={openComments > 0 ? 'danger' : ''}>コメント {openComments}</span>
        </button>
        <button
          className="copy plan-approve"
          onClick={onApprove}
          disabled={disabled}
          title={disabled ? disabledReason : '現在の plan を実装開始可能として承認する'}
        >
          {approvalCurrent ? '承認済み' : busy ? '更新中' : '実装を承認'}
        </button>
      </div>

      {showRemaining && remaining.length > 0 && (
        <ul className="remaining plan-remaining">
          {remaining.map(item => (
            <li key={item.id}>
              <button onClick={() => jump(item.target)}>
                <span className="chip kind">{item.kind}</span>
                <span className="txt">{item.title}</span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {warnings.length > 0 && (
        <ul className="plan-warnings">
          {warnings.map((warning, index) => <li key={`${warning}-${index}`}>{warning}</li>)}
        </ul>
      )}

      {approval && (
        <p className="plan-approval-state">
          <strong>{approval.consumedAt ? '承認は消費済み' : '承認済み'}</strong>
          <span> {formatTime(approval.at)}</span>
          <code>{approval.planHash}</code>
        </p>
      )}
      {!approval && approvalInvalidated && (
        <p className="plan-approval-state invalid">Plan または状態の変更により承認が失効しました。</p>
      )}
    </div>
  );
}
