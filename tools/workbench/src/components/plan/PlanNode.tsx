import { useState } from 'react';
import { countsAsPlanOpen } from '../../lib/comment';
import type {
  PlanComment,
  PlanConfirmation,
  PlanNode as PlanNodeData,
} from '../../types/plan';
import type { Label } from '../../types/thread';
import { Markdown } from './Markdown';
import { PlanComments } from './PlanComments';

export type PlanTreeNode = PlanNodeData & {
  children: PlanTreeNode[];
};

export function PlanNode({
  node,
  commentsByNode,
  confirmationsByNode,
  openDetailIds,
  busy,
  onToggleDetail,
  onAddComment,
  onRemoveComment,
  onResolveComment,
  onConfirm,
  onUnconfirm,
}: {
  node: PlanTreeNode;
  commentsByNode: Map<string, PlanComment[]>;
  confirmationsByNode: Map<string, PlanConfirmation>;
  openDetailIds: Set<string>;
  busy: boolean;
  onToggleDetail: (nodeId: string) => void;
  onAddComment: (nodeId: string, body: string, label: Label) => void;
  onRemoveComment: (id: string) => void;
  onResolveComment: (id: string) => void;
  onConfirm: (nodeId: string) => void;
  onUnconfirm: (nodeId: string) => void;
}) {
  const [showRaw, setShowRaw] = useState(false);
  const comments = commentsByNode.get(node.id) ?? [];
  const confirmation = confirmationsByNode.get(node.id);
  const detailOpen = openDetailIds.has(node.id);
  const confirmed = confirmation?.hash === node.hash;
  const open = node.level !== 'detail' || detailOpen;
  const returned = (
    node.level === 'decision'
    && node.leaf
    && !confirmed
    && comments.some(comment =>
      (comment.label === 'fix' || comment.label === 'question')
      && countsAsPlanOpen(comment))
  );
  const title = node.kind === 'preamble' ? `${node.title}の導入` : node.title;

  return (
    <section
      className={`plan-node level-${node.level}${confirmed ? ' confirmed' : ''}`}
      id={`plan-${node.id}`}
    >
      <div className="plan-node-head">
        {node.level === 'detail' && (
          <button
            className="plan-fold"
            onClick={() => onToggleDetail(node.id)}
            aria-expanded={open}
            title={open ? '詳細を畳む' : '詳細を展開'}
          >
            <span className={`chev${open ? ' open' : ''}`} aria-hidden>›</span>
          </button>
        )}
        {node.level === 'focus' && node.leaf && (
          <input
            type="checkbox"
            checked={confirmed}
            disabled={busy}
            aria-label={`${title}を確認`}
            onChange={() => confirmed ? onUnconfirm(node.id) : onConfirm(node.id)}
          />
        )}
        <h2>{title}</h2>
        <span className={`plan-level ${node.level}`}>{node.level}</span>
        {comments.length > 0 && <span className="plan-comment-count">コメント {comments.length}</span>}
        {node.level === 'decision' && node.leaf && (
          <>
            {returned && <span className="plan-returned">差し戻し中</span>}
            <button
              className={`plan-accept${confirmed ? ' on' : ''}`}
              disabled={busy}
              onClick={() => confirmed ? onUnconfirm(node.id) : onConfirm(node.id)}
            >
              {confirmed ? 'accept 済み' : 'accept'}
            </button>
          </>
        )}
        <button
          className="plan-raw-toggle"
          onClick={() => setShowRaw(value => !value)}
          aria-expanded={showRaw}
        >
          {showRaw ? '原文を隠す' : '原文'}
        </button>
      </div>

      {showRaw && <pre className="plan-raw"><code>{node.markdown}</code></pre>}

      {open && (
        <>
          {node.leaf && (
            <Markdown
              markdown={node.markdown}
              skipFirstHeading={node.kind === 'section'}
            />
          )}
          <PlanComments
            nodeId={node.id}
            comments={comments}
            busy={busy}
            onAdd={onAddComment}
            onRemove={onRemoveComment}
            onResolve={onResolveComment}
          />
          {node.children.length > 0 && (
            <div className="plan-children">
              {node.children.map(child => (
                <PlanNode
                  key={child.id}
                  node={child}
                  commentsByNode={commentsByNode}
                  confirmationsByNode={confirmationsByNode}
                  openDetailIds={openDetailIds}
                  busy={busy}
                  onToggleDetail={onToggleDetail}
                  onAddComment={onAddComment}
                  onRemoveComment={onRemoveComment}
                  onResolveComment={onResolveComment}
                  onConfirm={onConfirm}
                  onUnconfirm={onUnconfirm}
                />
              ))}
            </div>
          )}
        </>
      )}
    </section>
  );
}
