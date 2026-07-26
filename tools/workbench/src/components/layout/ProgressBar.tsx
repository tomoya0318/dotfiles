import { useState } from 'react';
import type { RefObject } from 'react';
import { RemainingList } from './RemainingList';
import type { Progress } from '../../types/thread';

export function ProgressBar({ bar, progress, copied, onDone, jumpTo }: {
  bar: RefObject<HTMLDivElement | null>;
  progress: Progress;
  copied: boolean;
  onDone: () => void;
  jumpTo: (sel: string, groupId?: string) => void;
}) {
  const [showRemaining, setShowRemaining] = useState(false);

  return (
    <div className="progress" ref={bar}>
      <div className="progress-row">
        <button className="progress-main" onClick={() => setShowRemaining(v => !v)}
          aria-expanded={showRemaining} disabled={progress.remaining === 0}>
          <span className={`chev${showRemaining ? ' open' : ''}`} aria-hidden>›</span>
          <strong className={progress.remaining === 0 ? 'done' : ''}>
            {progress.remaining === 0 ? 'すべて判断済み' : `残り ${progress.remaining}`}
          </strong>
          <span>グループ判断 {progress.groups.done} / {progress.groups.total}</span>
          <span>未解決コメント {progress.openComments.length}</span>
          {progress.findings.length > 0 && (
            <span className="danger">未トリアージの指摘 {progress.findings.length}</span>
          )}
          <span className="muted">所感 {progress.notes}</span>
        </button>
        <button className="copy" onClick={onDone}>
          {copied ? '合図をコピーした' : 'レビュー完了'}
        </button>
      </div>

      {showRemaining && progress.remaining > 0 && (
        <RemainingList progress={progress} jumpTo={jumpTo} />
      )}
    </div>
  );
}
