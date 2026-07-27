import { CommentView } from '../comment/CommentView';
import { threadComment } from '../../lib/planComment';
import type { PlanComment } from '../../types/plan';

export function PlanLostComments({
  comments,
  onRemove,
  onResolve,
}: {
  comments: PlanComment[];
  onRemove: (id: string) => void;
  onResolve: (id: string) => void;
}) {
  if (comments.length === 0) return null;
  return (
    <section className="lost plan-lost" id="plan-lost-comments">
      <h2>迷子コメント {comments.length} 件 — 元の節が見つからない</h2>
      {comments.map(comment => (
        <div key={comment.id} className="plan-lost-comment">
          {comment.anchor.quote && <code>{comment.anchor.quote}</code>}
          <CommentView
            c={threadComment(comment)}
            onRemove={() => onRemove(comment.id)}
            onResolve={() => onResolve(comment.id)}
            allowResolve
          />
        </div>
      ))}
    </section>
  );
}
