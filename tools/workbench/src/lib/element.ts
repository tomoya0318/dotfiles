import type { FileOp, Hunk } from '../types/report';

export const isOp = (el: Hunk | FileOp): el is FileOp => 'kind' in el;
