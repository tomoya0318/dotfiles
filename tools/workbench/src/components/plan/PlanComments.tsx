import { useState } from 'react';
import { CommentView } from '../comment/CommentView';
import { Composer } from '../comment/Composer';
import { threadComment } from '../../lib/planComment';
import type { PlanComment } from '../../types/plan';
import type { Label } from '../../types/thread';

export function PlanComments({
  nodeId,
  comments,
  busy,
  onAdd,
  onRemove,
  onResolve,
  alwaysVisible = false,
}: {
  nodeId: string;
  comments: PlanComment[];
  busy: boolean;
  onAdd: (nodeId: string, body: string, label: Label) => void;
  onRemove: (id: string) => void;
  onResolve: (id: string) => void;
  alwaysVisible?: boolean;
}) {
  const [composing, setComposing] = useState(false);
  if (!alwaysVisible && comments.length === 0 && !composing) {
    return (
      <button className="plan-comment-open" disabled={busy} onClick={() => setComposing(true)}>
        コメントを追加
      </button>
    );
  }
  return (
    <div className="plan-comments">
      <div className="plan-comments-head">
        <strong>コメント {comments.length}</strong>
        {!composing && (
          <button className="link" disabled={busy} onClick={() => setComposing(true)}>
            追加
          </button>
        )}
      </div>
      {comments.map(comment => (
        <CommentView
          key={comment.id}
          c={threadComment(comment)}
          onRemove={() => onRemove(comment.id)}
          onResolve={() => onResolve(comment.id)}
          allowResolve
        />
      ))}
      {composing && (
        <Composer
          onSave={(body, label) => {
            onAdd(nodeId, body, label);
            setComposing(false);
          }}
          onCancel={() => setComposing(false)}
        />
      )}
    </div>
  );
}
