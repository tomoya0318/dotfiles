import type { Label } from './thread';

export type SessionView = 'plan' | 'review';
export type PlanLevel = 'focus' | 'decision' | 'detail';
export type PlanNodeKind = 'document' | 'section' | 'preamble';
export type PlanCommentState = 'open' | 'answered' | 'resolved';

export type PlanTurn = {
  by: string;
  body: string;
};

export type PlanComment = {
  id: string;
  anchor: {
    kind: 'plan';
    nodeId: string;
    quote?: string;
  };
  label: Label;
  turns: PlanTurn[];
  state: PlanCommentState;
};

export type PlanConfirmation = {
  nodeId: string;
  hash: string;
  at: string;
};

export type PlanApproval = {
  planHash: string;
  stateRevision: number;
  nonce: string;
  at: string;
  consumedAt?: string;
};

export type StoredPlanNode = {
  id: string;
  parent: string | null;
  index: number;
  hash: string;
  quote?: string;
  level: PlanLevel;
  leaf: boolean;
};

export type PlanNode = StoredPlanNode & {
  title: string;
  depth: number;
  kind: PlanNodeKind;
  markdown: string;
};

export type PlanStateResponse = {
  revision: number;
  nodes: StoredPlanNode[];
  comments: PlanComment[];
  confirmations: PlanConfirmation[];
  approval: PlanApproval | null;
  warnings: string[];
};

export type PlanResponse = Omit<PlanStateResponse, 'nodes'> & {
  hash: string;
  nodes: PlanNode[];
};
