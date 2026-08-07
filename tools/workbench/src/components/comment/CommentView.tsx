import { useState } from 'react';
import { Avatar } from '../../Avatar';
import { ReplyBox } from './ReplyBox';
import { AUTHOR_NAME, isFinding, isHuman, LABEL_TEXT } from '../../lib/comment';
import type { Comment } from '../../types/thread';

export function CommentView({ c, onRemove, onReply, onResolve, allowResolve = false }: {
  c: Comment;
  onRemove: () => void;
  onReply?: (body: string) => void;
  onResolve: () => void;
  allowResolve?: boolean;
}) {
  const [replying, setReplying] = useState(false);
  const [text, setText] = useState('');
  const canReply = c.state !== 'resolved' && onReply !== undefined;
  const finding = isFinding(c);

  const send = () => {
    if (!text.trim()) return;
    onReply?.(text);
    setText('');
    setReplying(false);
  };

  return (
    <div className={`comment ${c.state} ${finding ? 'finding' : `l-${c.label}`}`} id={`c-${c.id}`}>
      <div className="speaker">
        <span className="tag">{finding ? '指摘' : LABEL_TEXT[c.label ?? 'question']}</span>
        {c.classification && <span className="classification">分類 {c.classification}</span>}
        {c.confidence && <span className={`conf c-${c.confidence}`}>確信度 {c.confidence}</span>}
        <span className="state">
          {c.state === 'resolved' ? '解決'
            : c.state === 'answered' ? '回答あり'
            : finding ? 'トリアージ待ち' : '未解決'}
        </span>
        {(finding || allowResolve) && c.state !== 'resolved' && (
          <button className="link" onClick={onResolve}>{finding ? '却下' : '解決'}</button>
        )}
        {!finding && c.turns.length === 1 && (
          <button className="link" onClick={onRemove}>削除</button>
        )}
      </div>

      {c.turns.map((t, i) => (
        <div key={i} className={`turn ${isHuman(t.by) ? 'human' : 'ai'} by-${t.by}`}>
          <div className="who"><Avatar by={t.by} />{AUTHOR_NAME[t.by]}</div>
          <p>{t.body}</p>
        </div>
      ))}

      {canReply && !replying && (
        <button className="reply-open" onClick={() => setReplying(true)}>返信</button>
      )}
      {replying && (
        <ReplyBox text={text} onChange={setText} onSend={send} onCancel={() => setReplying(false)} />
      )}
    </div>
  );
}
