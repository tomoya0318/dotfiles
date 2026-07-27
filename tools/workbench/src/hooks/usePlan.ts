import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ApiError,
  approvePlan,
  fetchPlan,
  updatePlanState,
} from '../api/client';
import type {
  PlanResponse,
  PlanStateResponse,
} from '../types/plan';
import type { Label } from '../types/thread';

type WorkbenchChange = {
  sessionId?: unknown;
  kind?: unknown;
};

function mergeState(
  current: PlanResponse,
  state: PlanStateResponse,
): PlanResponse {
  const stored = new Map(state.nodes.map(node => [node.id, node]));
  return {
    ...current,
    ...state,
    nodes: current.nodes.map(node => ({
      ...node,
      ...stored.get(node.id),
    })),
  };
}

export function usePlan(sessionId: string) {
  const [plan, setPlan] = useState<PlanResponse | null>(null);
  const [error, setError] = useState('');
  const [pending, setPending] = useState(0);
  const [approvalInvalidated, setApprovalInvalidated] = useState(false);
  const planRef = useRef<PlanResponse | null>(null);
  const queue = useRef<Promise<void>>(Promise.resolve());

  const replacePlan = useCallback((next: PlanResponse, trackInvalidation = true) => {
    const previous = planRef.current;
    if (trackInvalidation && previous?.approval && !next.approval) {
      setApprovalInvalidated(true);
    }
    planRef.current = next;
    setPlan(next);
    setError('');
  }, []);

  const pull = useCallback(async (trackInvalidation = true) => {
    try {
      replacePlan(await fetchPlan(sessionId), trackInvalidation);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason));
    }
  }, [replacePlan, sessionId]);

  useEffect(() => {
    void pull(false);
    const changed = (data: WorkbenchChange) => {
      if (data.sessionId !== sessionId) return;
      if (data.kind === 'plan' || data.kind === 'plan-state') void pull();
    };
    import.meta.hot?.on('workbench:changed', changed);
    return () => {
      import.meta.hot?.off('workbench:changed', changed);
    };
  }, [pull, sessionId]);

  const enqueue = useCallback((task: () => Promise<void>) => {
    setPending(value => value + 1);
    queue.current = queue.current
      .then(task, task)
      .catch(reason => {
        setError(reason instanceof Error ? reason.message : String(reason));
      })
      .finally(() => setPending(value => value - 1));
    return queue.current;
  }, []);

  const mutate = useCallback((
    op: string,
    body: Record<string, unknown>,
  ) => enqueue(async () => {
    const current = planRef.current;
    if (!current) return;
    try {
      const state = await updatePlanState(sessionId, current.revision, op, body);
      replacePlan(mergeState(current, state));
    } catch (reason) {
      if (reason instanceof ApiError && reason.status === 409) {
        await pull();
        return;
      }
      throw reason;
    }
  }), [enqueue, pull, replacePlan, sessionId]);

  const approve = useCallback(() => enqueue(async () => {
    const current = planRef.current;
    if (!current) return;
    try {
      replacePlan(await approvePlan(sessionId, current.hash));
      setApprovalInvalidated(false);
    } catch (reason) {
      if (reason instanceof ApiError && reason.status === 409) {
        await pull();
        return;
      }
      throw reason;
    }
  }), [enqueue, pull, replacePlan, sessionId]);

  return {
    plan,
    error,
    busy: pending > 0,
    approvalInvalidated,
    addComment: (nodeId: string, body: string, label: Label) =>
      mutate('add', { nodeId, body, label }),
    removeComment: (id: string) => mutate('remove', { id }),
    resolveComment: (id: string) => mutate('resolve', { id }),
    confirm: (nodeId: string) => mutate('confirm', { nodeId }),
    unconfirm: (nodeId: string) => mutate('unconfirm', { nodeId }),
    approve,
  };
}
