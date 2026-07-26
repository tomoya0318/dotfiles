import { useState } from 'react';
import { type Author, AUTHOR_NAME } from './thread';

/**
 * `public/avatar-{you,claude,codex}.png` があればそれを使い、無ければ組み込みの図形を出す。
 * 画像を差し替えたいだけのときにコードを触らずに済む。
 */
const SRC: Record<Author, string | null> = {
  you: '/avatar-you.png',
  claude: '/avatar-claude.png',
  codex: '/avatar-codex.png',
  ai: null,
};

function Fallback({ by }: { by: Author }) {
  if (by === 'claude') {
    // 中心から放射する短いストローク
    return (
      <svg viewBox="0 0 24 24" className="av-svg claude" aria-hidden>
        <g stroke="currentColor" strokeWidth="2.1" strokeLinecap="round">
          {Array.from({ length: 8 }, (_, i) => {
            const a = (i * Math.PI) / 4;
            return (
              <line key={i}
                x1={12 + Math.cos(a) * 3.2} y1={12 + Math.sin(a) * 3.2}
                x2={12 + Math.cos(a) * 8.4} y2={12 + Math.sin(a) * 8.4} />
            );
          })}
        </g>
      </svg>
    );
  }
  if (by === 'codex') {
    return (
      <svg viewBox="0 0 24 24" className="av-svg codex" aria-hidden>
        <path d="M12 3.2 19.4 7.4v9.2L12 20.8 4.6 16.6V7.4Z"
          fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinejoin="round" />
        <circle cx="12" cy="12" r="2.6" fill="currentColor" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" className="av-svg you" aria-hidden>
      <circle cx="12" cy="9" r="3.6" fill="currentColor" />
      <path d="M4.8 20.4c.7-4 3.6-6 7.2-6s6.5 2 7.2 6Z" fill="currentColor" />
    </svg>
  );
}

export function Avatar({ by, size = 20 }: { by: Author; size?: number }) {
  const [broken, setBroken] = useState(false);
  const src = SRC[by];
  return (
    <span className={`av av-${by}`} style={{ width: size, height: size }}
      title={AUTHOR_NAME[by]}>
      {src && !broken
        ? <img src={src} alt="" onError={() => setBroken(true)} />
        : <Fallback by={by} />}
    </span>
  );
}
