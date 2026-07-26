import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { parseDiff, Diff, Hunk as HunkRow, getChangeKey } from 'react-diff-view';
import type { ChangeData } from 'react-diff-view';
import 'react-diff-view/style/index.css';
import './App.css';
import { Avatar } from './Avatar';
import {
  LABELS, LABEL_TEXT, AUTHOR_NAME, isHuman,
  type Label, type Comment, type Progress, type Thread,
  firstLine, resolveOffset, countsAsOpen, isFinding,
  fetchThread, addComment, replyTo, removeComment, resolveComment, setChecks, copyBlock, handoff,
} from './thread';
import {
  report, hunkById, opById, fileById, groupOfElement, embedded,
  type Hunk, type FileOp, type Group,
} from './report';

const threadPath = report.threadPath;
const repoPath = report.repo;

const isOp = (el: Hunk | FileOp): el is FileOp => 'kind' in el;
const sideOf = (c: ChangeData): Comment['side'] =>
  c.type === 'insert' ? 'new' : c.type === 'delete' ? 'old' : 'normal';

type Ctx = {
  comments: Comment[];
  add: (c: Omit<Comment, 'id'>) => void;
  remove: (id: string) => void;
  reply: (id: string, body: string) => void;
  resolve: (id: string) => void;
};

/** 所感 ← 質問 → 要修正。左ほど要求が弱い。既定は中央。 */
function LabelSlider({ value, onChange }: { value: Label; onChange: (l: Label) => void }) {
  const i = LABELS.indexOf(value);
  return (
    <div className="slider" role="radiogroup" aria-label="コメントの種類">
      <span className="slider-thumb" data-pos={i} aria-hidden />
      {LABELS.map((l, n) => (
        <button
          key={l}
          role="radio"
          aria-checked={l === value}
          className={l === value ? 'on' : ''}
          onClick={() => onChange(l)}
          onKeyDown={e => {
            if (e.key === 'ArrowRight') onChange(LABELS[Math.min(n + 1, 2)]);
            if (e.key === 'ArrowLeft') onChange(LABELS[Math.max(n - 1, 0)]);
          }}
        >
          {LABEL_TEXT[l]}
        </button>
      ))}
    </div>
  );
}

function Composer({ onSave, onCancel }: { onSave: (text: string, label: Label) => void; onCancel: () => void }) {
  const [text, setText] = useState('');
  const [label, setLabel] = useState<Label>('question');
  return (
    <div className="composer">
      <LabelSlider value={label} onChange={setLabel} />
      <textarea
        autoFocus
        rows={3}
        value={text}
        placeholder="この行への指示や疑問"
        onChange={e => setText(e.target.value)}
        onKeyDown={e => {
          if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && text.trim()) onSave(text, label);
          if (e.key === 'Escape') onCancel();
        }}
      />
      <div className="composer-actions">
        <button onClick={() => text.trim() && onSave(text, label)}>保存 <kbd>⌘↵</kbd></button>
        <button className="ghost" onClick={onCancel}>取消 <kbd>esc</kbd></button>
      </div>
    </div>
  );
}

function CommentView({ c, onRemove, onReply, onResolve }: {
  c: Comment; onRemove: () => void; onReply: (body: string) => void; onResolve: () => void;
}) {
  const [replying, setReplying] = useState(false);
  const [text, setText] = useState('');
  const canReply = c.state !== 'resolved';
  const finding = isFinding(c);

  const send = () => {
    if (!text.trim()) return;
    onReply(text);
    setText('');
    setReplying(false);
  };

  return (
    <div className={`comment ${c.state} ${finding ? 'finding' : `l-${c.label}`}`} id={`c-${c.id}`}>
      <div className="speaker">
        <span className="tag">{finding ? '指摘' : LABEL_TEXT[c.label ?? 'question']}</span>
        {c.confidence && <span className={`conf c-${c.confidence}`}>確信度 {c.confidence}</span>}
        <span className="state">
          {c.state === 'resolved' ? '解決'
            : c.state === 'answered' ? '回答あり'
            : finding ? 'トリアージ待ち' : '未解決'}
        </span>
        {finding && c.state !== 'resolved' && (
          <button className="link" onClick={onResolve}>却下</button>
        )}
        {!finding && c.turns.length === 1 && (
          <button className="link" onClick={onRemove}>削除</button>
        )}
      </div>

      {c.turns.map((t, i) => (
        <div key={i} className={`turn ${isHuman(t.by) ? 'human' : 'ai'} by-${t.by}`}>
          <div className="who"><Avatar by={t.by} />{AUTHOR_NAME[t.by]}</div>
          <p>{t.body}</p>
        </div>
      ))}

      {canReply && !replying && (
        <button className="reply-open" onClick={() => setReplying(true)}>返信</button>
      )}
      {replying && (
        <div className="reply">
          <textarea
            autoFocus rows={2} value={text}
            placeholder="この行への返信"
            onChange={e => setText(e.target.value)}
            onKeyDown={e => {
              if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) send();
              if (e.key === 'Escape') setReplying(false);
            }}
          />
          <div className="composer-actions">
            <button onClick={send}>返信 <kbd>⌘↵</kbd></button>
            <button className="ghost" onClick={() => setReplying(false)}>取消</button>
          </div>
        </div>
      )}
    </div>
  );
}

function DiffOfHunk({ hunk, ctx }: { hunk: Hunk; ctx: Ctx }) {
  const [composeAt, setComposeAt] = useState<number | null>(null);

  const parsed = useMemo(() => {
    const file = fileById.get(hunk.fileId);
    if (!file) return null;
    try {
      return parseDiff(file.diff)[0] ?? null;
    } catch {
      return null;
    }
  }, [hunk.fileId]);

  const target = parsed?.hunks?.[hunk.index];
  const changes = target?.changes ?? [];
  const mine = ctx.comments.filter(c => c.hunk === hunk.id);
  // アンカーが外れたものは迷子欄に出るので、この hunk のバッジには数えない
  const anchored = mine.filter(c => resolveOffset(changes, c) !== null).length;

  const widgets = useMemo(() => {
    const w: Record<string, React.ReactNode> = {};
    const at = (i: number, node: React.ReactNode) => {
      const ch = changes[i];
      if (!ch) return;
      const k = getChangeKey(ch);
      w[k] = <>{w[k]}{node}</>;
    };
    for (const c of mine) {
      const i = resolveOffset(changes, c);
      if (i === null) continue;
      at(i, <CommentView key={c.id} c={c}
        onRemove={() => ctx.remove(c.id)}
        onReply={body => ctx.reply(c.id, body)}
        onResolve={() => ctx.resolve(c.id)} />);
    }
    if (composeAt !== null) {
      at(composeAt, (
        <Composer
          key="composer"
          onCancel={() => setComposeAt(null)}
          onSave={(text, label) => {
            const ch = changes[composeAt];
            ctx.add({
              hunk: hunk.id, side: sideOf(ch), offset: composeAt, lineText: ch.content,
              label, turns: [{ by: 'you', body: text }], state: 'open',
            });
            setComposeAt(null);
          }}
        />
      ));
    }
    return w;
  }, [changes, mine, composeAt, ctx, hunk.id]);

  return (
    <div className="hunk">
      <div className="el-head">
        <span className="hid">{hunk.id}</span>
        <span className="path">{hunk.file}</span>
        {anchored > 0 && <span className="badge">{anchored}</span>}
        <span className="delta"><span className="plus">+{hunk.add}</span> <span className="minus">−{hunk.del}</span></span>
      </div>
      {parsed && target ? (
        <Diff
          viewType="unified"
          diffType={parsed.type}
          hunks={[target]}
          widgets={widgets}
          codeEvents={{
            onClick: ({ change }) => {
              const i = changes.findIndex(c => c === change);
              if (i !== -1) setComposeAt(cur => (cur === i ? null : i));
            },
          }}
        >
          {hunks => hunks.map(h => <HunkRow key={h.content} hunk={h} />)}
        </Diff>
      ) : (
        <div className="missing">差分を復元できなかった</div>
      )}
    </div>
  );
}

function OpView({ op }: { op: FileOp }) {
  return (
    <div className="op">
      <div className="el-head">
        <span className="hid">{op.id}</span>
        <span className="op-label">
          {op.kind === 'move'
            ? <><code>{op.from}</code> <span className="arrow">→</span> <code>{op.to}</code></>
            : <><span className="opkind">{op.kind === 'add' ? '新規' : '削除'}</span> <code>{op.dir}</code></>}
        </span>
        <span className="delta">
          {op.files.length} files
          {op.silentCount > 0 && <span className="silent"> / 中身無変更 {op.silentCount}</span>}
        </span>
      </div>
      <ul className="op-files">
        {op.files.map((f, i) => (
          <li key={i}>{f.old && f.new ? <>{f.old} <span className="arrow">→</span> {f.new}</> : (f.new ?? f.old)}</li>
        ))}
      </ul>
    </div>
  );
}

function Elements({ ids, ctx }: { ids: string[]; ctx: Ctx }) {
  return (
    <>
      {ids.map(id => {
        const el = opById.get(id) ?? hunkById.get(id);
        if (!el) return null;
        return isOp(el) ? <OpView key={id} op={el} /> : <DiffOfHunk key={id} hunk={el} ctx={ctx} />;
      })}
    </>
  );
}

function GroupCard({ group, ctx, checked, onCheck, open, onToggle }: {
  group: Group; ctx: Ctx; checked: boolean; onCheck: (v: boolean) => void;
  open: boolean; onToggle: () => void;
}) {
  const [showRipple, setShowRipple] = useState(false);
  const unknown = group.tags.includes('意図不明');
  const ids = new Set([...group.core, ...group.ripple]);
  const n = ctx.comments.filter(c => ids.has(c.hunk) && countsAsOpen(c)).length;
  const body = open && !checked;

  return (
    <article id={`g-${group.id}`} className={`card${unknown ? ' unknown' : ''}${checked ? ' checked' : ''}`}>
      <div className="card-head">
        <input
          type="checkbox"
          checked={checked}
          aria-label={`${group.title} の判断を済ませる`}
          onChange={e => onCheck(e.target.checked)}
        />
        <button className="head-main" onClick={() => !checked && onToggle()} aria-expanded={body}>
          <span className={`chev${body ? ' open' : ''}`} aria-hidden>›</span>
          <span className="title">{group.title}</span>
          {n > 0 && <span className="badge">{n}</span>}
          <span className="counts">
            判断 {group.core.length}
            {group.ripple.length > 0 && <span className="muted"> / 波及 {group.ripple.length}</span>}
          </span>
        </button>
      </div>

      {!checked && (unknown
        ? <p className="reason none">意図を1文で書けなかった</p>
        : <p className="reason">{group.reason}</p>)}

      {body && (
        <div className="body">
          <Elements ids={group.core} ctx={ctx} />
          {group.ripple.length > 0 && (
            <>
              <button className="fold" onClick={() => setShowRipple(s => !s)}>
                {showRipple ? '▾' : '▸'} 波及 {group.ripple.length} 件
              </button>
              {showRipple && <div className="ripple"><Elements ids={group.ripple} ctx={ctx} /></div>}
            </>
          )}
        </div>
      )}
    </article>
  );
}

/** アンカーが外れたコメント。行が消えたか書き換わった証拠なので捨てずに出す。 */
function LostComments({ comments }: { comments: Comment[] }) {
  const lost = comments.filter(c => {
    const h = hunkById.get(c.hunk);
    const f = h && fileById.get(h.fileId);
    if (!f) return true;
    try {
      const changes = parseDiff(f.diff)[0]?.hunks?.[h.index]?.changes ?? [];
      return resolveOffset(changes, c) === null;
    } catch {
      return true;
    }
  });
  if (!lost.length) return null;
  return (
    <section className="lost">
      <h2>迷子コメント {lost.length} 件 — 元の行が見つからない</h2>
      {lost.map(c => (
        <div key={c.id} className={`comment open ${isFinding(c) ? 'finding' : `l-${c.label}`}`}>
          <div className="speaker">
            <span className="tag">{isFinding(c) ? '指摘' : LABEL_TEXT[c.label ?? 'question']}</span>
            {c.hunk} <code>{c.lineText.trim()}</code>
          </div>
          <p>{firstLine(c)}</p>
        </div>
      ))}
    </section>
  );
}

export default function App() {
  const [thread, setThread] = useState<Thread>(embedded);
  const [copied, setCopied] = useState(false);
  const [showRemaining, setShowRemaining] = useState(false);
  const [openGroups, setOpenGroups] = useState<string[]>([]);
  const bar = useRef<HTMLDivElement>(null);

  const comments = thread.comments;
  const checks = thread.checks;

  // 起動時にサーバの thread を取る。エージェントが外から書いたら取り直す
  useEffect(() => {
    let alive = true;
    const pull = () => fetchThread().then(t => alive && setThread(t)).catch(() => {});
    pull();
    import.meta.hot?.on('thread:changed', pull);
    return () => { alive = false; };
  }, []);

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

  const toggleCheck = useCallback((id: string, on: boolean) => {
    setThread(prev => {
      const next = on
        ? [...new Set([...prev.checks, id])]
        : prev.checks.filter(x => x !== id);
      setChecks(next).then(setThread).catch(() => {});
      return { ...prev, checks: next };
    });
  }, []);

  const ctx: Ctx = useMemo(() => ({
    comments,
    add: c => { addComment(c).then(setThread).catch(() => {}); },
    remove: id => { removeComment(id).then(setThread).catch(() => {}); },
    reply: (id, body) => { replyTo(id, body).then(setThread).catch(() => {}); },
    resolve: id => { resolveComment(id).then(setThread).catch(() => {}); },
  }), [comments]);

  const groups = report.groups as Group[];
  const review = groups.filter(g => g.core.length > 0);
  const rest = groups.filter(g => g.core.length === 0);
  const s = report.stats;
  const foldCount = groups.reduce((n, g) => n + g.ripple.length, 0);

  const progress: Progress = useMemo(() => {
    const pending = review.filter(g => !checks.includes(g.id)).map(g => ({ id: g.id, title: g.title }));
    const openComments = comments.filter(countsAsOpen);
    const notes = comments.filter(c => c.label === 'note' && c.state !== 'resolved').length;
    return {
      groups: { done: review.length - pending.length, total: review.length, pending },
      openComments,
      findings: openComments.filter(isFinding),
      notes,
      remaining: pending.length + openComments.length,
    };
  }, [review, checks, comments]);

  // ボタンはロックの受け渡し。sentinel と合図の両方を出す。
  // 待っているセッションがあれば自動で動き、無ければ貼れば動く
  const onDone = async () => {
    handoff();
    await navigator.clipboard.writeText(
      copyBlock(report.ref, repoPath, threadPath, progress));
    setCopied(true);
    setTimeout(() => setCopied(false), 2200);
  };

  return (
    <main>
      <header>
        <h1>{report.subject}</h1>
        <div className="stats">
          <span>{s.files} files</span>
          <span>{s.hunks} hunks</span>
          <span className="plus">+{s.additions}</span>
          <span className="minus">−{s.deletions}</span>
          <code className="ref on">{report.ref}</code>
        </div>
        <p className="lede">
          <strong>読むべき {review.length} グループ</strong>
          <span className="muted"> — 波及 {foldCount} 件は畳んである</span>
        </p>
      </header>

      <div className="progress" ref={bar}>
        <div className="progress-row">
          <button className="progress-main" onClick={() => setShowRemaining(v => !v)}
            aria-expanded={showRemaining} disabled={progress.remaining === 0}>
            <span className={`chev${showRemaining ? ' open' : ''}`} aria-hidden>›</span>
            <strong className={progress.remaining === 0 ? 'done' : ''}>
              {progress.remaining === 0 ? 'すべて判断済み' : `残り ${progress.remaining}`}
            </strong>
            <span>グループ判断 {progress.groups.done} / {progress.groups.total}</span>
            <span>未解決コメント {progress.openComments.length}</span>
            {progress.findings.length > 0 && (
              <span className="danger">未トリアージの指摘 {progress.findings.length}</span>
            )}
            <span className="muted">所感 {progress.notes}</span>
          </button>
          <button className="copy" onClick={onDone}>
            {copied ? '合図をコピーした' : 'レビュー完了'}
          </button>
        </div>

        {showRemaining && progress.remaining > 0 && (
          <ul className="remaining">
            {progress.groups.pending.map(g => (
              <li key={g.id}>
                <button onClick={() => jumpTo(`#g-${g.id}`)}>
                  <span className="chip id">{g.id}</span>
                  <span className="chip kind">未判断</span>
                  <span className="txt">{g.title}</span>
                </button>
              </li>
            ))}
            {progress.openComments.map(c => (
              <li key={c.id}>
                <button onClick={() => jumpTo(`#c-${c.id}`, groupOfElement.get(c.hunk))}>
                  <span className="chip id">{c.hunk}</span>
                  <span className={`chip ${isFinding(c) ? 'finding' : `l-${c.label}`}`}>
                    {isFinding(c) ? '指摘' : LABEL_TEXT[c.label ?? 'question']}
                  </span>
                  {c.confidence && <span className={`chip conf c-${c.confidence}`}>{c.confidence}</span>}
                  <span className="txt">{firstLine(c)}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <section>
        {review.map(g => (
          <GroupCard key={g.id} group={g} ctx={ctx}
            checked={checks.includes(g.id)} onCheck={v => toggleCheck(g.id, v)}
            open={openGroups.includes(g.id)} onToggle={() => toggleGroup(g.id)} />
        ))}
      </section>

      {rest.length > 0 && (
        <section className="rest">
          <h2>未分類</h2>
          {rest.map(g => (
            <GroupCard key={g.id} group={g} ctx={ctx}
              checked={checks.includes(g.id)} onCheck={v => toggleCheck(g.id, v)}
              open={openGroups.includes(g.id)} onToggle={() => toggleGroup(g.id)} />
          ))}
        </section>
      )}

      <LostComments comments={comments} />
    </main>
  );
}
