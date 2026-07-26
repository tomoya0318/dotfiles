import { useMemo } from 'react';
import 'react-diff-view/style/index.css';
import './App.css';
import { Header } from './components/layout/Header';
import { ProgressBar } from './components/layout/ProgressBar';
import { GroupList } from './components/review/GroupList';
import { LostComments } from './components/review/LostComments';
import { useHandoff } from './hooks/useHandoff';
import { useOpenGroups } from './hooks/useOpenGroups';
import { useStickyHeight } from './hooks/useStickyHeight';
import { useThread } from './hooks/useThread';
import { computeProgress } from './lib/progress';
import { foldCountOf, restOf, reviewOf } from './lib/selectors';
import { report } from './report';
import type { Group } from './types/report';
import type { Progress } from './types/thread';

export default function App({ sessionId }: { sessionId: string }) {
  const { comments, checks, ctx, toggleCheck } = useThread(sessionId);
  const bar = useStickyHeight();
  const { openGroups, toggleGroup, jumpTo } = useOpenGroups();

  const groups = report.groups as Group[];
  const review = reviewOf(groups);
  const rest = restOf(groups);
  const foldCount = foldCountOf(groups);

  const progress: Progress = useMemo(
    () => computeProgress(review, checks, comments), [review, checks, comments]);

  const { copied, onDone } = useHandoff(progress, sessionId);

  return (
    <main>
      <Header review={review} foldCount={foldCount} />

      <ProgressBar bar={bar} progress={progress} copied={copied} onDone={onDone} jumpTo={jumpTo} />

      <GroupList review={review} rest={rest} ctx={ctx} checks={checks}
        toggleCheck={toggleCheck} openGroups={openGroups} toggleGroup={toggleGroup} />

      <LostComments comments={comments} />
    </main>
  );
}
