import type { Group } from '../types/report';

export const reviewOf = (groups: Group[]) => groups.filter(g => g.core.length > 0);
export const restOf = (groups: Group[]) => groups.filter(g => g.core.length === 0);
export const foldCountOf = (groups: Group[]) => groups.reduce((n, g) => n + g.ripple.length, 0);
