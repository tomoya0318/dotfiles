import { useCallback, useState } from 'react';

export function useOpenGroups() {
  const [openGroups, setOpenGroups] = useState<string[]>([]);

  const toggleGroup = useCallback((id: string) => {
    setOpenGroups(p => (p.includes(id) ? p.filter(x => x !== id) : [...p, id]));
  }, []);

  /** 畳まれたグループの中のコメントへは飛べないので、開いてから飛ぶ。 */
  const jumpTo = useCallback((sel: string, groupId?: string) => {
    if (groupId) setOpenGroups(p => (p.includes(groupId) ? p : [...p, groupId]));
    requestAnimationFrame(() => requestAnimationFrame(() => {
      document.querySelector(sel)?.scrollIntoView({ block: 'start', behavior: 'smooth' });
    }));
  }, []);

  return { openGroups, toggleGroup, jumpTo };
}
