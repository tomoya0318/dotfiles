import { useEffect, useRef } from 'react';

export function useStickyHeight() {
  const bar = useRef<HTMLDivElement>(null);

  // sticky の実高さを常に反映する。展開すると背が伸びるので固定値にできない
  useEffect(() => {
    const el = bar.current;
    if (!el) return;
    const ro = new ResizeObserver(() => {
      document.documentElement.style.setProperty('--sticky-h', `${el.offsetHeight + 14}px`);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return bar;
}
