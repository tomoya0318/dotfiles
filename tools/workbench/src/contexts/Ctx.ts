import type { Comment } from '../types/thread';

export type Ctx = {
  comments: Comment[];
  add: (c: Omit<Comment, 'id'>) => void;
  remove: (id: string) => void;
  reply: (id: string, body: string) => void;
  resolve: (id: string) => void;
};
