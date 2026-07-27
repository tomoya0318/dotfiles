import { useMemo, useState } from 'react';
import type { SessionMeta } from '../../api/client';
import { usePlan } from '../../hooks/usePlan';
import { useStickyHeight } from '../../hooks/useStickyHeight';
import { countsAsPlanOpen } from '../../lib/comment';
import type {
  PlanComment,
  PlanNode as PlanNodeData,
  SessionView,
} from '../../types/plan';
import type { Label } from '../../types/thread';
import { PlanComments } from './PlanComments';
import { PlanHeader, type PlanRemainingItem } from './PlanHeader';
import { PlanLostComments } from './PlanLostComments';
import { PlanNode, type PlanTreeNode } from './PlanNode';

function planTree(nodes: PlanNodeData[]): PlanTreeNode[] {
  const trees = new Map<string, PlanTreeNode>();
  for (const node of nodes) {
    if (node.id !== '@doc') trees.set(node.id, { ...node, children: [] });
  }
  const roots: PlanTreeNode[] = [];
  for (const tree of trees.values()) {
    const parent = tree.parent ? trees.get(tree.parent) : undefined;
    if (parent) parent.children.push(tree);
    else roots.push(tree);
  }
  const sort = (items: PlanTreeNode[]) => {
    items.sort((left, right) => left.index - right.index);
    for (const item of items) sort(item.children);
  };
  sort(roots);
  return roots;
}

function groupComments(comments: PlanComment[]): Map<string, PlanComment[]> {
  const grouped = new Map<string, PlanComment[]>();
  for (const comment of comments) {
    const current = grouped.get(comment.anchor.nodeId) ?? [];
    current.push(comment);
    grouped.set(comment.anchor.nodeId, current);
  }
  return grouped;
}

export function PlanApp({
  sessionId,
  session,
  view,
  onViewChange,
}: {
  sessionId: string;
  session: SessionMeta;
  view: SessionView;
  onViewChange: (view: SessionView) => void;
}) {
  const {
    plan,
    error,
    busy,
    approvalInvalidated,
    addComment,
    removeComment,
    resolveComment,
    confirm,
    unconfirm,
    approve,
  } = usePlan(sessionId);
  const bar = useStickyHeight();
  const [openDetailIds, setOpenDetailIds] = useState<Set<string>>(() => new Set());

  const derived = useMemo(() => {
    if (!plan) return null;
    const nodeIds = new Set(plan.nodes.map(node => node.id));
    const documentNode = plan.nodes.find(node => node.id === '@doc');
    const commentsByNode = groupComments(plan.comments);
    const confirmationsByNode = new Map(
      plan.confirmations.map(item => [item.nodeId, item]),
    );
    const valid = (node: PlanNodeData): boolean =>
      confirmationsByNode.get(node.id)?.hash === node.hash;
    const focus = plan.nodes.filter(node => node.leaf && node.level === 'focus');
    const decisions = plan.nodes.filter(node => node.leaf && node.level === 'decision');
    const confirmationNodes = documentNode ? [documentNode, ...focus] : focus;
    const missingConfirmations = confirmationNodes.filter(node => !valid(node));
    const missingDecisions = decisions.filter(node => !valid(node));
    const blockingComments = plan.comments.filter(countsAsPlanOpen);
    const lostComments = plan.comments.filter(comment => !nodeIds.has(comment.anchor.nodeId));
    const details = plan.nodes.filter(node => node.level === 'detail').map(node => node.id);
    const remaining: PlanRemainingItem[] = [
      ...missingConfirmations.map(node => ({
        id: `confirm-${node.id}`,
        target: node.id === '@doc' ? 'plan-document-thread' : `plan-${node.id}`,
        kind: '未確認' as const,
        title: node.id === '@doc' ? '文書全体' : node.title,
      })),
      ...missingDecisions.map(node => ({
        id: `decision-${node.id}`,
        target: `plan-${node.id}`,
        kind: '未決' as const,
        title: node.title,
      })),
      ...blockingComments.map(comment => ({
        id: `comment-${comment.id}`,
        target: `c-${comment.id}`,
        kind: 'コメント' as const,
        title: comment.turns[0]?.body.trim().split('\n')[0] || comment.id,
      })),
    ];
    const approvalProblems = [
      ...(missingConfirmations.length > 0
        ? [`未確認の項目が ${missingConfirmations.length} 件あります`]
        : []),
      ...(missingDecisions.length > 0
        ? [`accept していない判断が ${missingDecisions.length} 件あります`]
        : []),
      ...(blockingComments.length > 0
        ? [`未解決コメントが ${blockingComments.length} 件あります`]
        : []),
    ];
    return {
      tree: planTree(plan.nodes),
      documentNode,
      documentComments: commentsByNode.get('@doc') ?? [],
      commentsByNode,
      confirmationsByNode,
      lostComments,
      details,
      confirmationTotal: confirmationNodes.length,
      confirmed: confirmationNodes.length - missingConfirmations.length,
      undecided: missingDecisions.length,
      openComments: blockingComments.length,
      remaining,
      approvalProblems,
    };
  }, [plan]);

  if (error && !plan) {
    return (
      <main className="empty-session">
        <p className="missing">plan を読めなかった: {error}</p>
        <a className="home-link" href="/">作業一覧へ戻る</a>
      </main>
    );
  }
  if (!plan || !derived) {
    return <main className="empty-session"><p>Plan を読み込んでいます。</p></main>;
  }

  const documentConfirmed = (
    derived.documentNode
    && derived.confirmationsByNode.get('@doc')?.hash === derived.documentNode.hash
  );
  const allDetailsExpanded = (
    derived.details.length > 0
    && derived.details.every(id => openDetailIds.has(id))
  );
  const add = (nodeId: string, body: string, label: Label) => {
    void addComment(nodeId, body, label);
  };
  const remove = (id: string) => {
    void removeComment(id);
  };
  const resolve = (id: string) => {
    void resolveComment(id);
  };
  const setConfirmed = (nodeId: string, on: boolean) => {
    void (on ? confirm(nodeId) : unconfirm(nodeId));
  };

  return (
    <main className="plan-app">
      <PlanHeader
        bar={bar}
        session={session}
        view={view}
        onViewChange={onViewChange}
        confirmed={derived.confirmed}
        confirmationTotal={derived.confirmationTotal}
        undecided={derived.undecided}
        openComments={derived.openComments}
        remaining={derived.remaining}
        warnings={plan.warnings}
        approval={plan.approval}
        approvalInvalidated={approvalInvalidated}
        approvalProblems={derived.approvalProblems}
        busy={busy}
        allDetailsExpanded={allDetailsExpanded}
        onToggleDetails={() => {
          setOpenDetailIds(
            allDetailsExpanded ? new Set() : new Set(derived.details),
          );
        }}
        onApprove={() => void approve()}
      />

      {error && <p className="missing">Plan の更新に失敗した: {error}</p>}

      <section className="plan-document-thread" id="plan-document-thread">
        <div className="plan-document-head">
          <div>
            <p className="eyebrow">document</p>
            <h1>{derived.documentNode?.title ?? session.name}</h1>
          </div>
          <label>
            <input
              type="checkbox"
              checked={Boolean(documentConfirmed)}
              disabled={busy || !derived.documentNode}
              onChange={() => setConfirmed('@doc', !documentConfirmed)}
            />
            文書全体を確認
          </label>
        </div>
        <PlanComments
          nodeId="@doc"
          comments={derived.documentComments}
          busy={busy}
          onAdd={add}
          onRemove={remove}
          onResolve={resolve}
          alwaysVisible
        />
      </section>

      <div className="plan-tree">
        {derived.tree.map(node => (
          <PlanNode
            key={node.id}
            node={node}
            commentsByNode={derived.commentsByNode}
            confirmationsByNode={derived.confirmationsByNode}
            openDetailIds={openDetailIds}
            busy={busy}
            onToggleDetail={nodeId => {
              setOpenDetailIds(current => {
                const next = new Set(current);
                if (next.has(nodeId)) next.delete(nodeId);
                else next.add(nodeId);
                return next;
              });
            }}
            onAddComment={add}
            onRemoveComment={remove}
            onResolveComment={resolve}
            onConfirm={nodeId => setConfirmed(nodeId, true)}
            onUnconfirm={nodeId => setConfirmed(nodeId, false)}
          />
        ))}
      </div>

      <PlanLostComments
        comments={derived.lostComments}
        onRemove={remove}
        onResolve={resolve}
      />
    </main>
  );
}
