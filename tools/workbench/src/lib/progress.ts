import { countsAsOpen, isFinding } from './comment';
import type { Group } from '../types/report';
import type { Comment, Progress } from '../types/thread';

export function computeProgress(review: Group[], checks: string[], comments: Comment[]): Progress {
  const pending = review.filter(g => !checks.includes(g.id)).map(g => ({ id: g.id, title: g.title }));
  const openComments = comments.filter(countsAsOpen);
  const notes = comments.filter(c => c.label === 'note' && c.state !== 'resolved').length;
  return {
    groups: { done: review.length - pending.length, total: review.length, pending },
    openComments,
    findings: openComments.filter(isFinding),
    notes,
    remaining: pending.length + openComments.length,
  };
}
