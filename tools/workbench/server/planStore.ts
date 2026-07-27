import { randomUUID } from 'node:crypto';
import {
  existsSync,
  readFileSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { containedPath } from './contained.js';
import { sequentialId, writeJsonFile } from './fileStore.js';
import { readPlan } from './planDoc.js';
import type {
  ParsedPlanNode,
  PlanApproval,
  PlanComment,
  PlanCommentLabel,
  PlanCommentState,
  PlanConfirmation,
  PlanDocument,
  PlanNode,
  PlanResponse,
  PlanState,
  PlanStateResponse,
  PlanTurn,
  StoredPlanNode,
} from './planTypes.js';

export class PlanHttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

type LoadedPlanState = {
  state: PlanState;
  warnings: string[];
  dirty: boolean;
};

export type SyncedPlanState = {
  state: PlanState;
  warnings: string[];
  nodeIds: Map<string, string>;
};

const EMPTY_STATE: PlanState = {
  revision: 0,
  nodes: [],
  comments: [],
  confirmations: [],
  approval: null,
};
const LEVELS = new Set(['focus', 'decision', 'detail']);
const LABELS = new Set(['note', 'question', 'fix']);
const STATES = new Set(['open', 'answered', 'resolved']);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function copyEmptyState(): PlanState {
  return {
    ...EMPTY_STATE,
    nodes: [],
    comments: [],
    confirmations: [],
  };
}

function statePath(workDir: string, createParent = false): string {
  return containedPath(workDir, 'review/plan.json', createParent);
}

function sentinelPath(workDir: string, createParent = false): string {
  return containedPath(workDir, 'review/plan-approved', createParent);
}

function removeSentinel(workDir: string): void {
  const path = sentinelPath(workDir);
  if (existsSync(path)) unlinkSync(path);
}

function writeState(
  workDir: string,
  state: PlanState,
  onWrite?: () => void,
): void {
  const path = statePath(workDir, true);
  writeJsonFile(path, state);
  onWrite?.();
}

function validStoredNode(value: unknown): value is StoredPlanNode {
  if (!isRecord(value)) return false;
  const validId = (id: unknown): id is string =>
    typeof id === 'string' && (id === '@doc' || /^n\d+$/.test(id));
  return (
    validId(value.id)
    && (value.parent === null || validId(value.parent))
    && Number.isSafeInteger(value.index)
    && Number(value.index) >= 0
    && typeof value.hash === 'string'
    && /^[a-f0-9]{12}$/.test(value.hash)
    && (
      value.quote === undefined
      || (typeof value.quote === 'string' && value.quote.length <= 120)
    )
    && typeof value.level === 'string'
    && LEVELS.has(value.level)
    && typeof value.leaf === 'boolean'
  );
}

function validTurn(value: unknown): value is PlanTurn {
  return (
    isRecord(value)
    && typeof value.by === 'string'
    && value.by !== ''
    && typeof value.body === 'string'
    && value.body.trim() !== ''
  );
}

function loadComment(
  value: unknown,
  seenIds: Set<string>,
  warnings: string[],
): PlanComment | null {
  if (!isRecord(value) || typeof value.id !== 'string' || !/^c\d+$/.test(value.id)) {
    warnings.push('壊れたコメントを除外しました');
    return null;
  }
  if (seenIds.has(value.id)) {
    warnings.push(`重複したコメント ID を除外しました: ${value.id}`);
    return null;
  }
  if (
    !isRecord(value.anchor)
    || value.anchor.kind !== 'plan'
    || typeof value.anchor.nodeId !== 'string'
    || !/^(?:@doc|n\d+)$/.test(value.anchor.nodeId)
  ) {
    warnings.push(`壊れたコメントを除外しました: ${value.id}`);
    return null;
  }
  const rawTurns = Array.isArray(value.turns) ? value.turns : [];
  const turns: PlanTurn[] = [];
  for (const [index, turn] of rawTurns.entries()) {
    if (
      !validTurn(turn)
      || (index === 0 && turn.by !== 'you')
      || (index > 0 && turn.by === 'you')
    ) {
      warnings.push(`不正な発言を除外しました: ${value.id}`);
      continue;
    }
    turns.push(turn);
  }
  if (turns.length === 0 || turns[0].by !== 'you') {
    warnings.push(`発言のないコメントを除外しました: ${value.id}`);
    return null;
  }

  const label = typeof value.label === 'string' && LABELS.has(value.label)
    ? value.label as PlanCommentLabel
    : 'question';
  if (label !== value.label) warnings.push(`不正なコメントラベルを補正しました: ${value.id}`);
  const state = typeof value.state === 'string' && STATES.has(value.state)
    ? value.state as PlanCommentState
    : 'open';
  if (state !== value.state) warnings.push(`不正なコメント状態を補正しました: ${value.id}`);
  seenIds.add(value.id);
  return {
    id: value.id,
    anchor: {
      kind: 'plan',
      nodeId: value.anchor.nodeId,
      ...(typeof value.anchor.quote === 'string' ? { quote: value.anchor.quote } : {}),
    },
    label,
    turns,
    state,
  };
}

function validConfirmation(value: unknown): value is PlanConfirmation {
  return (
    isRecord(value)
    && typeof value.nodeId === 'string'
    && /^(?:@doc|n\d+)$/.test(value.nodeId)
    && typeof value.hash === 'string'
    && /^[a-f0-9]{12}$/.test(value.hash)
    && typeof value.at === 'string'
  );
}

function validApproval(value: unknown): value is PlanApproval {
  return (
    isRecord(value)
    && typeof value.planHash === 'string'
    && /^[a-f0-9]{64}$/.test(value.planHash)
    && Number.isSafeInteger(value.stateRevision)
    && Number(value.stateRevision) >= 0
    && typeof value.nonce === 'string'
    && value.nonce !== ''
    && typeof value.at === 'string'
    && (value.consumedAt === undefined || typeof value.consumedAt === 'string')
  );
}

function loadState(workDir: string): LoadedPlanState {
  const path = statePath(workDir);
  if (!existsSync(path)) {
    return { state: copyEmptyState(), warnings: [], dirty: false };
  }

  let raw: unknown;
  try {
    raw = JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return {
      state: copyEmptyState(),
      warnings: ['plan.json を読めなかったため空の状態を使います'],
      dirty: true,
    };
  }
  if (!isRecord(raw)) {
    return {
      state: copyEmptyState(),
      warnings: ['plan.json のルートが不正なため空の状態を使います'],
      dirty: true,
    };
  }

  const warnings: string[] = [];
  let dirty = false;
  const revision = Number.isSafeInteger(raw.revision) && Number(raw.revision) >= 0
    ? Number(raw.revision)
    : 0;
  if (revision !== raw.revision) {
    warnings.push('revision が不正なため 0 に補正しました');
    dirty = true;
  }

  const nodes: StoredPlanNode[] = [];
  const nodeIds = new Set<string>();
  for (const value of Array.isArray(raw.nodes) ? raw.nodes : []) {
    if (!validStoredNode(value)) {
      warnings.push('壊れたノードを除外しました');
      dirty = true;
      continue;
    }
    if (nodeIds.has(value.id)) {
      warnings.push(`重複したノード ID を除外しました: ${value.id}`);
      dirty = true;
      continue;
    }
    nodeIds.add(value.id);
    nodes.push(value);
  }
  if (!Array.isArray(raw.nodes)) dirty = true;

  const comments: PlanComment[] = [];
  const commentIds = new Set<string>();
  for (const value of Array.isArray(raw.comments) ? raw.comments : []) {
    const warningCount = warnings.length;
    const comment = loadComment(value, commentIds, warnings);
    if (comment) comments.push(comment);
    if (!comment || warnings.length !== warningCount) dirty = true;
  }
  if (!Array.isArray(raw.comments)) dirty = true;

  const confirmations: PlanConfirmation[] = [];
  const confirmedNodes = new Set<string>();
  for (const value of Array.isArray(raw.confirmations) ? raw.confirmations : []) {
    if (!validConfirmation(value)) {
      warnings.push('壊れた確認を除外しました');
      dirty = true;
      continue;
    }
    if (confirmedNodes.has(value.nodeId)) {
      warnings.push(`重複した確認を除外しました: ${value.nodeId}`);
      dirty = true;
      continue;
    }
    confirmedNodes.add(value.nodeId);
    confirmations.push(value);
  }
  if (!Array.isArray(raw.confirmations)) dirty = true;

  let approval: PlanApproval | null = null;
  if (raw.approval !== null && raw.approval !== undefined) {
    if (validApproval(raw.approval)) approval = raw.approval;
    else {
      warnings.push('壊れた承認を除外しました');
      dirty = true;
    }
  }

  return {
    state: { revision, nodes, comments, confirmations, approval },
    warnings,
    dirty,
  };
}

function nextNodeId(nodes: StoredPlanNode[]): () => string {
  return sequentialId(nodes.map(node => node.id), 'n');
}

function reconcileNodes(
  savedNodes: StoredPlanNode[],
  document: PlanDocument,
  comments: PlanComment[],
  confirmations: PlanConfirmation[],
): { nodes: StoredPlanNode[]; nodeIds: Map<string, string> } {
  const current = document.nodes;
  const currentByKey = new Map(current.map(node => [node.key, node]));
  const matches = new Map<string, string>();
  const usedCurrent = new Set<string>();
  if (currentByKey.has('@doc')) {
    matches.set('@doc', '@doc');
    usedCurrent.add('@doc');
  }

  const candidates = current.filter(node => node.key !== '@doc');
  const hashCounts = new Map<string, number>();
  for (const node of candidates) {
    hashCounts.set(node.hash, (hashCounts.get(node.hash) ?? 0) + 1);
  }
  for (const saved of savedNodes) {
    if (
      saved.id !== '@doc'
      && hashCounts.get(saved.hash) === 1
    ) {
      const candidate = candidates.find(node => node.hash === saved.hash);
      if (candidate && !usedCurrent.has(candidate.key)) {
        matches.set(saved.id, candidate.key);
        usedCurrent.add(candidate.key);
      }
    }
  }

  let matchedByPosition = true;
  while (matchedByPosition) {
    matchedByPosition = false;
    for (const saved of savedNodes) {
      if (matches.has(saved.id) || saved.id === '@doc') continue;
      const parentKey = saved.parent === null ? null : matches.get(saved.parent);
      if (saved.parent !== null && !parentKey) continue;
      const positional = candidates.filter(node =>
        !usedCurrent.has(node.key)
        && node.parentKey === parentKey
        && node.index === saved.index);
      if (positional.length !== 1) continue;
      matches.set(saved.id, positional[0].key);
      usedCurrent.add(positional[0].key);
      matchedByPosition = true;
    }
  }

  for (const saved of savedNodes) {
    if (matches.has(saved.id) || !saved.quote) continue;
    const quoted = candidates.filter(node =>
      !usedCurrent.has(node.key)
      && node.quote?.startsWith(saved.quote ?? '') === true);
    if (quoted.length !== 1) continue;
    matches.set(saved.id, quoted[0].key);
    usedCurrent.add(quoted[0].key);
  }

  const idByCurrent = new Map<string, string>();
  for (const [id, key] of matches) idByCurrent.set(key, id);
  idByCurrent.set('@doc', '@doc');
  const allocate = nextNodeId(savedNodes);
  for (const node of current) {
    if (!idByCurrent.has(node.key)) idByCurrent.set(node.key, allocate());
  }

  const nodes = current.map(node => ({
    id: idByCurrent.get(node.key) ?? allocate(),
    parent: node.parentKey === null ? null : idByCurrent.get(node.parentKey) ?? null,
    index: node.index,
    hash: node.hash,
    ...(node.quote ? { quote: node.quote } : {}),
    level: node.level,
    leaf: node.leaf,
  }));
  const referenced = new Set([
    ...comments.map(comment => comment.anchor.nodeId),
    ...confirmations.map(confirmation => confirmation.nodeId),
  ]);
  const matchedIds = new Set(matches.keys());
  for (const saved of savedNodes) {
    if (
      saved.id !== '@doc'
      && !matchedIds.has(saved.id)
      && referenced.has(saved.id)
    ) {
      nodes.push(saved);
    }
  }

  return { nodes, nodeIds: idByCurrent };
}

function sameNodes(left: StoredPlanNode[], right: StoredPlanNode[]): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}

export function syncPlanState(
  workDir: string,
  document: PlanDocument,
  onWrite?: () => void,
): SyncedPlanState {
  const loaded = loadState(workDir);
  const reconciled = reconcileNodes(
    loaded.state.nodes,
    document,
    loaded.state.comments,
    loaded.state.confirmations,
  );
  let approval = loaded.state.approval;
  let approvalInvalidated = false;
  if (!approval) {
    removeSentinel(workDir);
  } else if (
    approval
    && (
      approval.planHash !== document.hash
      || approval.stateRevision !== loaded.state.revision
    )
  ) {
    removeSentinel(workDir);
    approval = null;
    approvalInvalidated = true;
  }
  const state = {
    ...loaded.state,
    nodes: reconciled.nodes,
    approval,
  };
  if (
    loaded.dirty
    || approvalInvalidated
    || !sameNodes(loaded.state.nodes, reconciled.nodes)
  ) {
    writeState(workDir, state, onWrite);
  }
  return {
    state,
    warnings: loaded.warnings,
    nodeIds: reconciled.nodeIds,
  };
}

function stateResponse(
  synced: SyncedPlanState,
  documentWarnings: string[] = [],
): PlanStateResponse {
  return {
    ...synced.state,
    warnings: [...documentWarnings, ...synced.warnings],
  };
}

export function makePlanResponse(
  document: PlanDocument,
  synced: SyncedPlanState,
): PlanResponse {
  const storedById = new Map(synced.state.nodes.map(node => [node.id, node]));
  const nodes: PlanNode[] = [];
  for (const parsed of document.nodes) {
    const id = synced.nodeIds.get(parsed.key);
    const stored = id ? storedById.get(id) : undefined;
    if (!stored) continue;
    nodes.push({
      ...stored,
      title: parsed.title,
      depth: parsed.depth,
      kind: parsed.kind,
      markdown: parsed.markdown,
    });
  }
  return {
    hash: document.hash,
    revision: synced.state.revision,
    nodes,
    comments: synced.state.comments,
    confirmations: synced.state.confirmations,
    approval: synced.state.approval,
    warnings: [...document.warnings, ...synced.warnings],
  };
}

export function getPlanStateResponse(
  document: PlanDocument,
  synced: SyncedPlanState,
): PlanStateResponse {
  return stateResponse(synced, document.warnings);
}

function currentNode(
  document: PlanDocument,
  synced: SyncedPlanState,
  nodeId: string,
): { parsed: ParsedPlanNode; stored: StoredPlanNode } {
  const parsed = document.nodes.find(node => synced.nodeIds.get(node.key) === nodeId);
  const stored = synced.state.nodes.find(node => node.id === nodeId);
  if (!parsed || !stored) throw new PlanHttpError(400, 'nodeId is not in the current plan');
  return { parsed, stored };
}

function nextCommentId(comments: PlanComment[]): string {
  return sequentialId(comments.map(comment => comment.id), 'c')();
}

function requestRevision(body: Record<string, unknown>): number {
  if (!Number.isSafeInteger(body.revision) || Number(body.revision) < 0) {
    throw new PlanHttpError(400, 'revision is required');
  }
  return Number(body.revision);
}

function requestedNodeId(
  body: Record<string, unknown>,
  comment?: Record<string, unknown>,
): string {
  if (
    comment
    && isRecord(comment.anchor)
    && typeof comment.anchor.nodeId === 'string'
  ) {
    return comment.anchor.nodeId;
  }
  if (typeof body.nodeId === 'string') return body.nodeId;
  throw new PlanHttpError(400, 'nodeId is required');
}

function addComment(
  state: PlanState,
  document: PlanDocument,
  synced: SyncedPlanState,
  body: Record<string, unknown>,
): PlanState {
  const input = isRecord(body.comment) ? body.comment : {};
  const nodeId = requestedNodeId(body, input);
  const { parsed } = currentNode(document, synced, nodeId);
  const labelValue = input.label ?? body.label ?? 'question';
  if (typeof labelValue !== 'string' || !LABELS.has(labelValue)) {
    throw new PlanHttpError(400, 'invalid comment label');
  }

  const rawTurns = Array.isArray(input.turns)
    ? input.turns
    : [{
        by: 'you',
        body: typeof body.body === 'string' ? body.body : '',
      }];
  if (
    rawTurns.length !== 1
    || !validTurn(rawTurns[0])
    || rawTurns[0].by !== 'you'
  ) {
    throw new PlanHttpError(400, 'add requires one human turn');
  }
  const comment: PlanComment = {
    id: nextCommentId(state.comments),
    anchor: {
      kind: 'plan',
      nodeId,
      ...(parsed.quote ? { quote: parsed.quote } : {}),
    },
    label: labelValue as PlanCommentLabel,
    turns: [rawTurns[0]],
    state: 'open',
  };
  return {
    ...state,
    comments: [...state.comments, comment],
    confirmations: state.confirmations.filter(item => item.nodeId !== nodeId),
  };
}

function replyToComment(
  state: PlanState,
  body: Record<string, unknown>,
): PlanState {
  if (typeof body.id !== 'string') throw new PlanHttpError(400, 'comment id is required');
  const target = state.comments.find(comment => comment.id === body.id);
  if (!target) throw new PlanHttpError(400, 'comment not found');
  if (target.state === 'resolved') throw new PlanHttpError(409, 'comment is resolved');
  const turn = isRecord(body.turn)
    ? body.turn
    : { by: body.by, body: body.body };
  if (!validTurn(turn) || turn.by === 'you') {
    throw new PlanHttpError(400, 'reply must be authored by AI');
  }
  return {
    ...state,
    comments: state.comments.map(comment =>
      comment.id === body.id
        ? { ...comment, turns: [...comment.turns, turn], state: 'answered' }
        : comment),
  };
}

function removeComment(
  state: PlanState,
  body: Record<string, unknown>,
): PlanState {
  if (typeof body.id !== 'string') throw new PlanHttpError(400, 'comment id is required');
  const target = state.comments.find(comment => comment.id === body.id);
  if (!target) throw new PlanHttpError(400, 'comment not found');
  if (target.turns.some(turn => turn.by !== 'you')) {
    throw new PlanHttpError(409, 'comments with AI turns cannot be removed');
  }
  return {
    ...state,
    comments: state.comments.filter(comment => comment.id !== body.id),
  };
}

function resolveComment(
  state: PlanState,
  body: Record<string, unknown>,
): PlanState {
  if (typeof body.id !== 'string') throw new PlanHttpError(400, 'comment id is required');
  if (!state.comments.some(comment => comment.id === body.id)) {
    throw new PlanHttpError(400, 'comment not found');
  }
  return {
    ...state,
    comments: state.comments.map(comment =>
      comment.id === body.id ? { ...comment, state: 'resolved' } : comment),
  };
}

function confirmNode(
  state: PlanState,
  document: PlanDocument,
  synced: SyncedPlanState,
  body: Record<string, unknown>,
): PlanState {
  const nodeId = requestedNodeId(body);
  const { parsed, stored } = currentNode(document, synced, nodeId);
  if (nodeId !== '@doc' && (!parsed.leaf || parsed.level === 'detail')) {
    throw new PlanHttpError(400, 'only review leaves can be confirmed');
  }
  const confirmation: PlanConfirmation = {
    nodeId,
    hash: stored.hash,
    at: new Date().toISOString(),
  };
  return {
    ...state,
    confirmations: [
      ...state.confirmations.filter(item => item.nodeId !== nodeId),
      confirmation,
    ],
  };
}

function unconfirmNode(
  state: PlanState,
  document: PlanDocument,
  synced: SyncedPlanState,
  body: Record<string, unknown>,
): PlanState {
  const nodeId = requestedNodeId(body);
  currentNode(document, synced, nodeId);
  return {
    ...state,
    confirmations: state.confirmations.filter(item => item.nodeId !== nodeId),
  };
}

export function applyPlanOperation(
  workDir: string,
  document: PlanDocument,
  body: Record<string, unknown>,
  onWrite?: () => void,
): PlanStateResponse {
  const synced = syncPlanState(workDir, document, onWrite);
  const revision = requestRevision(body);
  if (revision !== synced.state.revision) {
    throw new PlanHttpError(409, 'revision conflict');
  }
  if (revision === Number.MAX_SAFE_INTEGER) {
    throw new PlanHttpError(409, 'revision is exhausted');
  }
  const op = typeof body.op === 'string' ? body.op : '';
  let state: PlanState;
  switch (op) {
    case 'add':
      state = addComment(synced.state, document, synced, body);
      break;
    case 'reply':
      state = replyToComment(synced.state, body);
      break;
    case 'remove':
      state = removeComment(synced.state, body);
      break;
    case 'resolve':
      state = resolveComment(synced.state, body);
      break;
    case 'confirm':
      state = confirmNode(synced.state, document, synced, body);
      break;
    case 'unconfirm':
      state = unconfirmNode(synced.state, document, synced, body);
      break;
    default:
      throw new PlanHttpError(400, 'unknown plan operation');
  }

  removeSentinel(workDir);
  state = {
    ...state,
    revision: state.revision + 1,
    approval: null,
  };
  writeState(workDir, state, onWrite);
  return {
    ...state,
    warnings: [...document.warnings, ...synced.warnings],
  };
}

function approvalProblems(
  document: PlanDocument,
  synced: SyncedPlanState,
): string[] {
  const storedById = new Map(synced.state.nodes.map(node => [node.id, node]));
  const confirmations = new Map(
    synced.state.confirmations.map(item => [item.nodeId, item]),
  );
  const missing: string[] = [];
  for (const parsed of document.nodes) {
    const nodeId = synced.nodeIds.get(parsed.key);
    const stored = nodeId ? storedById.get(nodeId) : undefined;
    if (!nodeId || !stored) continue;
    const required = nodeId === '@doc'
      || (parsed.leaf && (parsed.level === 'focus' || parsed.level === 'decision'));
    if (!required) continue;
    const confirmation = confirmations.get(nodeId);
    if (!confirmation || confirmation.hash !== stored.hash) missing.push(nodeId);
  }
  const blocking = synced.state.comments.filter(comment =>
    comment.state !== 'resolved' && comment.label !== 'note');
  return [
    ...(missing.length ? [`missing confirmations: ${missing.join(', ')}`] : []),
    ...(blocking.length ? [`blocking comments: ${blocking.length}`] : []),
  ];
}

export function approvePlan(
  workDir: string,
  expectedHash: unknown,
  onWrite?: () => void,
): PlanResponse {
  if (typeof expectedHash !== 'string') {
    throw new PlanHttpError(400, 'hash is required');
  }
  const document = readPlan(workDir);
  if (expectedHash !== document.hash) {
    throw new PlanHttpError(409, 'plan hash conflict');
  }
  const synced = syncPlanState(workDir, document, onWrite);
  if (synced.state.approval && !synced.state.approval.consumedAt) {
    throw new PlanHttpError(409, 'plan is already approved');
  }
  const problems = approvalProblems(document, synced);
  if (problems.length) throw new PlanHttpError(409, problems.join('; '));

  const approval: PlanApproval = {
    planHash: document.hash,
    stateRevision: synced.state.revision,
    nonce: randomUUID(),
    at: new Date().toISOString(),
  };
  const state = { ...synced.state, approval };
  const sentinel = sentinelPath(workDir, true);
  writeState(workDir, state, onWrite);
  writeFileSync(sentinel, `${JSON.stringify(approval)}\n`);
  return makePlanResponse(document, { ...synced, state });
}

export function consumePlanApproval(
  workDir: string,
  document: PlanDocument,
  nonce: unknown,
  onWrite?: () => void,
): PlanStateResponse {
  if (typeof nonce !== 'string' || nonce === '') {
    throw new PlanHttpError(400, 'nonce is required');
  }
  const synced = syncPlanState(workDir, document, onWrite);
  const approval = synced.state.approval;
  if (!approval || approval.consumedAt || approval.nonce !== nonce) {
    throw new PlanHttpError(409, 'approval nonce does not match');
  }
  removeSentinel(workDir);
  const state = {
    ...synced.state,
    approval: {
      ...approval,
      consumedAt: new Date().toISOString(),
    },
  };
  writeState(workDir, state, onWrite);
  return stateResponse({ ...synced, state }, document.warnings);
}

export function resetPlanApproval(
  workDir: string,
  document: PlanDocument,
  onWrite?: () => void,
): PlanStateResponse {
  const synced = syncPlanState(workDir, document, onWrite);
  removeSentinel(workDir);
  const state = { ...synced.state, approval: null };
  if (synced.state.approval) writeState(workDir, state, onWrite);
  return stateResponse({ ...synced, state }, document.warnings);
}
