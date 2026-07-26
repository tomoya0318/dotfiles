import { LABELS, LABEL_TEXT } from '../../lib/comment';
import type { Label } from '../../types/thread';

/** 所感 ← 質問 → 要修正。左ほど要求が弱い。既定は中央。 */
export function LabelSlider({ value, onChange }: { value: Label; onChange: (l: Label) => void }) {
  const i = LABELS.indexOf(value);
  return (
    <div className="slider" role="radiogroup" aria-label="コメントの種類">
      <span className="slider-thumb" data-pos={i} aria-hidden />
      {LABELS.map((l, n) => (
        <button
          key={l}
          role="radio"
          aria-checked={l === value}
          className={l === value ? 'on' : ''}
          onClick={() => onChange(l)}
          onKeyDown={e => {
            if (e.key === 'ArrowRight') onChange(LABELS[Math.min(n + 1, 2)]);
            if (e.key === 'ArrowLeft') onChange(LABELS[Math.max(n - 1, 0)]);
          }}
        >
          {LABEL_TEXT[l]}
        </button>
      ))}
    </div>
  );
}
