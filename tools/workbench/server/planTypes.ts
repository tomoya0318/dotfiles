export type PlanLevel = 'focus' | 'decision' | 'detail';
export type PlanNodeKind = 'document' | 'section' | 'preamble';
export type PlanCommentLabel = 'note' | 'question' | 'fix';
export type PlanCommentState = 'open' | 'answered' | 'resolved';

export type PlanTurn = {
  by: string;
  body: string;
};

export type PlanAnchor = {
  kind: 'plan';
  nodeId: string;
  quote?: string;
};

export type PlanComment = {
  id: string;
  anchor: PlanAnchor;
  label: PlanCommentLabel;
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

export type PlanState = {
  revision: number;
  nodes: StoredPlanNode[];
  comments: PlanComment[];
  confirmations: PlanConfirmation[];
  approval: PlanApproval | null;
};

export type ParsedPlanNode = {
  key: string;
  parentKey: string | null;
  index: number;
  title: string;
  depth: number;
  kind: PlanNodeKind;
  hash: string;
  quote?: string;
  level: PlanLevel;
  leaf: boolean;
  markdown: string;
};

export type PlanDocument = {
  hash: string;
  nodes: ParsedPlanNode[];
  warnings: string[];
};

export type PlanNode = StoredPlanNode & {
  title: string;
  depth: number;
  kind: PlanNodeKind;
  markdown: string;
};

export type PlanResponse = {
  hash: string;
  revision: number;
  nodes: PlanNode[];
  comments: PlanComment[];
  confirmations: PlanConfirmation[];
  approval: PlanApproval | null;
  warnings: string[];
};

export type PlanStateResponse = PlanState & {
  warnings: string[];
};
