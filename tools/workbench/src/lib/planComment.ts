import { AUTHOR_NAME } from './comment';
import type { PlanComment } from '../types/plan';
import type { Author, Comment } from '../types/thread';

function author(value: string): Author {
  return Object.hasOwn(AUTHOR_NAME, value) ? value as Author : 'ai';
}

export function threadComment(comment: PlanComment): Comment {
  return {
    id: comment.id,
    hunk: comment.anchor.nodeId,
    side: 'normal',
    offset: 0,
    lineText: comment.anchor.quote ?? '',
    label: comment.label,
    turns: comment.turns.map(turn => ({
      by: author(turn.by),
      body: turn.body,
    })),
    state: comment.state,
  };
}
