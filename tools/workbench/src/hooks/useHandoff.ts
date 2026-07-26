import { useState } from 'react';
import { handoff } from '../api/client';
import { copyBlock } from '../lib/handoff';
import { repoPath, threadPath } from '../lib/paths';
import { report } from '../report';
import type { Progress } from '../types/thread';

export function useHandoff(progress: Progress) {
  const [copied, setCopied] = useState(false);

  // ボタンはロックの受け渡し。sentinel と合図の両方を出す。
  // 待っているセッションがあれば自動で動き、無ければ貼れば動く
  const onDone = async () => {
    handoff();
    await navigator.clipboard.writeText(
      copyBlock(report.ref, repoPath, threadPath, progress));
    setCopied(true);
    setTimeout(() => setCopied(false), 2200);
  };

  return { copied, onDone };
}
