export function ReplyBox({ text, onChange, onSend, onCancel }: {
  text: string; onChange: (v: string) => void; onSend: () => void; onCancel: () => void;
}) {
  return (
    <div className="reply">
      <textarea
        autoFocus rows={2} value={text}
        placeholder="この行への返信"
        onChange={e => onChange(e.target.value)}
        onKeyDown={e => {
          if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) onSend();
          if (e.key === 'Escape') onCancel();
        }}
      />
      <div className="composer-actions">
        <button onClick={onSend}>返信 <kbd>⌘↵</kbd></button>
        <button className="ghost" onClick={onCancel}>取消</button>
      </div>
    </div>
  );
}
