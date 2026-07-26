import type { FileOp } from '../../types/report';

export function OpView({ op }: { op: FileOp }) {
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
