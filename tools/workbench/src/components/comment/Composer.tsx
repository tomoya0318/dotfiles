import { useState } from 'react';
import { LabelSlider } from './LabelSlider';
import type { Label } from '../../types/thread';

export function Composer({ onSave, onCancel }: { onSave: (text: string, label: Label) => void; onCancel: () => void }) {
  const [text, setText] = useState('');
  const [label, setLabel] = useState<Label>('question');
  return (
    <div className="composer">
      <LabelSlider value={label} onChange={setLabel} />
      <textarea
        autoFocus
        rows={3}
        value={text}
        placeholder="この行への指示や疑問"
        onChange={e => setText(e.target.value)}
        onKeyDown={e => {
          if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && text.trim()) onSave(text, label);
          if (e.key === 'Escape') onCancel();
        }}
      />
      <div className="composer-actions">
        <button onClick={() => text.trim() && onSave(text, label)}>保存 <kbd>⌘↵</kbd></button>
        <button className="ghost" onClick={onCancel}>取消 <kbd>esc</kbd></button>
      </div>
    </div>
  );
}
