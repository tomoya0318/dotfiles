import type { SessionView } from '../../types/plan';

export function ViewToggle({
  view,
  hasPlan,
  onChange,
}: {
  view: SessionView;
  hasPlan: boolean;
  onChange: (view: SessionView) => void;
}) {
  return (
    <div className="view-toggle" aria-label="表示する文書">
      {hasPlan && (
        <button
          className={view === 'plan' ? 'on' : ''}
          aria-pressed={view === 'plan'}
          onClick={() => onChange('plan')}
        >
          Plan
        </button>
      )}
      <button
        className={view === 'review' ? 'on' : ''}
        aria-pressed={view === 'review'}
        onClick={() => onChange('review')}
      >
        Review
      </button>
    </div>
  );
}
