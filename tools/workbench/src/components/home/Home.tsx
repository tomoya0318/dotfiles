import { useEffect, useMemo, useState } from 'react';
import {
  fetchSessions,
  type WorkbenchRepository,
  type WorkbenchSession,
} from '../../api/client';

const DOCUMENT_LABELS = {
  review: 'review',
  report: 'report',
  thread: 'thread',
} as const;

function UpdatedAt({ value }: { value: string }) {
  const formatter = useMemo(() => new Intl.DateTimeFormat('ja-JP', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }), []);
  return <time dateTime={value}>{formatter.format(new Date(value))}</time>;
}

function SessionCard({ session }: { session: WorkbenchSession }) {
  return (
    <li className="session-card">
      <a className="session-link" href={`/s/${encodeURIComponent(session.id)}`}>
        <span className="session-name">{session.name}</span>
        <span className="session-updated">更新 <UpdatedAt value={session.updatedAt} /></span>
      </a>
      <div className="document-list" aria-label="文書の状態">
        {Object.entries(DOCUMENT_LABELS).map(([key, label]) => {
          const present = session.documents[key as keyof typeof session.documents];
          return (
            <span className={`document ${present ? 'present' : 'absent'}`} key={key}>
              {label}
            </span>
          );
        })}
      </div>
      <code className="work-dir">{session.workDir}</code>
    </li>
  );
}

export default function Home() {
  const [repositories, setRepositories] = useState<WorkbenchRepository[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let alive = true;
    fetchSessions()
      .then(value => {
        if (alive) setRepositories(value);
      })
      .catch(reason => {
        if (alive) setError(reason instanceof Error ? reason.message : String(reason));
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, []);

  const visibleRepositories = repositories
    .map(repository => ({
      ...repository,
      branches: repository.branches.filter(branch => branch.sessions.length > 0),
    }))
    .filter(repository => repository.branches.length > 0);

  return (
    <main className="home">
      <header className="home-header">
        <p className="eyebrow">workbench</p>
        <h1>作業コンソール</h1>
        <p>登録したリポジトリの作業セッションを、ブランチごとに表示します。</p>
      </header>

      {loading && <p className="home-state">セッションを走査しています。</p>}
      {error && <p className="missing">セッションを読めなかった: {error}</p>}
      {!loading && !error && visibleRepositories.length === 0 && (
        <p className="home-state">表示できる作業セッションがありません。</p>
      )}

      <div className="repository-list">
        {visibleRepositories.map(repository => (
          <section className="repository" key={repository.root}>
            <div className="repository-head">
              <h2>{repository.name}</h2>
              <code>{repository.root}</code>
            </div>
            {repository.branches.map(branch => (
              <section className="branch" key={branch.worktree}>
                <div className="branch-head">
                  <h3>{branch.name}</h3>
                  <code>{branch.worktree}</code>
                </div>
                <ol className="session-list">
                  {branch.sessions.map(session => (
                    <SessionCard key={session.id} session={session} />
                  ))}
                </ol>
              </section>
            ))}
          </section>
        ))}
      </div>
    </main>
  );
}
