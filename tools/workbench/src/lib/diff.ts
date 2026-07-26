import type { ChangeData } from 'react-diff-view';
import type { Comment } from '../types/thread';

export const sideOf = (c: ChangeData): Comment['side'] =>
  c.type === 'insert' ? 'new' : c.type === 'delete' ? 'old' : 'normal';
