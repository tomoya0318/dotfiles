#!/usr/bin/env python3
"""
Claude Code 月次家事按分レポート生成スクリプト

使用方法:
  python3 generate-report.py           # 当月レポート
  python3 generate-report.py 2026-03   # 指定月レポート

設定:
  ~/.claude/skills/monthly-report/.env を編集してください
"""

import csv
import json
import sys
import os
import calendar
from pathlib import Path
from datetime import datetime
from collections import defaultdict

SKILL_DIR = Path(__file__).parent.parent


def load_env() -> dict[str, str]:
    """SKILL_DIR/.env を読み込んで辞書で返す"""
    env = {}
    env_path = SKILL_DIR / '.env'
    if not env_path.exists():
        return env
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' in line:
            key, _, value = line.partition('=')
            env[key.strip()] = value.strip()
    return env


def resolve_path(raw: str) -> Path | None:
    """~ を展開してパスを返す。空文字なら None"""
    if not raw:
        return None
    return Path(os.path.expanduser(raw))


def load_business_folders(conf_path: Path) -> list[str]:
    """事業用フォルダ設定を読み込む"""
    if not conf_path.exists():
        print(f"警告: 設定ファイルが見つかりません: {conf_path}", file=sys.stderr)
        return []
    folders = []
    for line in conf_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            folders.append(line)
    return folders


def is_business(cwd: str, business_folders: list[str]) -> bool:
    """cwd が事業用フォルダに前方一致するか判定"""
    for folder in business_folders:
        if cwd == folder or cwd.startswith(folder + '/'):
            return True
    return False


def build_project_cwd_map(projects_dir: Path) -> dict[str, str]:
    """
    subagent JSONL から「エンコード済みプロジェクトディレクトリ名 → 実際の cwd」のマッピングを構築する。
    主セッションファイル（cwd フィールドなし）の cwd 復元に使用。
    """
    mapping = {}
    for jsonl_file in projects_dir.rglob('subagents/*.jsonl'):
        encoded_dir = jsonl_file.parent.parent.parent.name
        if encoded_dir in mapping:
            continue
        try:
            with open(jsonl_file, 'r', encoding='utf-8') as f:
                entry = json.loads(f.readline())
                cwd = entry.get('cwd', '')
                if cwd:
                    mapping[encoded_dir] = cwd
        except Exception:
            pass
    return mapping


def scan_sessions(projects_dir: Path, target_year: int, target_month: int) -> dict:
    """
    JSONL ファイルをスキャンしてセッション別データを集計する。
    返り値: {session_id: {cwd, git_branch, timestamp, model, tokens: {...}}}
    """
    project_cwd_map = build_project_cwd_map(projects_dir)
    sessions = {}

    for jsonl_file in projects_dir.rglob('*.jsonl'):
        parts = jsonl_file.parts
        projects_idx = next((i for i, p in enumerate(parts) if p == 'projects'), -1)
        if projects_idx < 0 or projects_idx + 1 >= len(parts):
            continue
        encoded_project_dir = parts[projects_idx + 1]

        try:
            with open(jsonl_file, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    session_id = entry.get('sessionId')
                    if not session_id:
                        continue

                    timestamp_str = entry.get('timestamp', '')
                    if not timestamp_str:
                        continue

                    try:
                        ts = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                    except ValueError:
                        continue

                    if ts.year != target_year or ts.month != target_month:
                        continue

                    entry_cwd = entry.get('cwd', '') or project_cwd_map.get(encoded_project_dir, '')
                    entry_branch = entry.get('gitBranch', '')

                    if session_id not in sessions:
                        sessions[session_id] = {
                            'cwd': entry_cwd,
                            'git_branch': entry_branch,
                            'timestamp': ts,
                            'model': '',
                            'tokens': {
                                'input': 0,
                                'output': 0,
                                'cache_creation': 0,
                                'cache_read': 0,
                            }
                        }
                    else:
                        if not sessions[session_id]['cwd'] and entry_cwd:
                            sessions[session_id]['cwd'] = entry_cwd
                        if not sessions[session_id]['git_branch'] and entry_branch:
                            sessions[session_id]['git_branch'] = entry_branch
                        if ts < sessions[session_id]['timestamp']:
                            sessions[session_id]['timestamp'] = ts

                    if entry.get('type') == 'assistant':
                        msg = entry.get('message', {})
                        if not sessions[session_id]['model'] and msg.get('model'):
                            sessions[session_id]['model'] = msg['model']
                        usage = msg.get('usage', {})
                        sessions[session_id]['tokens']['input'] += usage.get('input_tokens', 0)
                        sessions[session_id]['tokens']['output'] += usage.get('output_tokens', 0)
                        sessions[session_id]['tokens']['cache_creation'] += usage.get('cache_creation_input_tokens', 0)
                        sessions[session_id]['tokens']['cache_read'] += usage.get('cache_read_input_tokens', 0)

        except (OSError, PermissionError):
            continue

    return sessions


def total_tokens(token_dict: dict) -> int:
    return sum(token_dict.values())


def format_number(n: int) -> str:
    return f"{n:,}"


def project_name(cwd: str) -> str:
    if not cwd:
        return '(不明)'
    parts = cwd.rstrip('/').split('/')
    if len(parts) >= 2:
        return '/'.join(parts[-2:])
    return parts[-1] if parts else '(不明)'


def build_report_text(year: int, month: int, sessions: dict, business_folders: list[str]) -> str:
    lines = []
    sorted_sessions = sorted(sessions.items(), key=lambda x: x[1]['timestamp'])

    project_stats = defaultdict(lambda: {
        'cwd': '',
        'category': '',
        'session_count': 0,
        'total_tokens': 0
    })

    for sid, s in sorted_sessions:
        cwd = s['cwd']
        category = '業務' if is_business(cwd, business_folders) else '非業務'
        pname = project_name(cwd)
        project_stats[pname]['cwd'] = cwd
        project_stats[pname]['category'] = category
        project_stats[pname]['session_count'] += 1
        project_stats[pname]['total_tokens'] += total_tokens(s['tokens'])

    total_business = sum(v['total_tokens'] for v in project_stats.values() if v['category'] == '業務')
    total_non_business = sum(v['total_tokens'] for v in project_stats.values() if v['category'] == '非業務')
    grand_total = total_business + total_non_business
    ratio = (total_business / grand_total * 100) if grand_total > 0 else 0.0

    sep = '=' * 56
    lines.append(f"\n{sep}")
    lines.append(f"  Claude Code 利用実績レポート: {year}年{month:02d}月")
    lines.append(sep)

    lines.append("\n【セッション別明細】")
    header = f"{'日時':<20}  {'プロジェクト':<28}  {'分類':<6}  {'合計トークン':>12}"
    lines.append(header)
    lines.append('-' * len(header))
    for sid, s in sorted_sessions:
        cwd = s['cwd']
        category = '業務' if is_business(cwd, business_folders) else '非業務'
        pname = project_name(cwd)
        branch = f" ({s['git_branch']})" if s['git_branch'] else ''
        label = f"{pname}{branch}"
        ts_str = s['timestamp'].astimezone().strftime('%Y-%m-%d %H:%M')
        tok = total_tokens(s['tokens'])
        lines.append(f"{ts_str:<20}  {label:<28}  {category:<6}  {format_number(tok):>12}")

    lines.append("\n【プロジェクト別集計】")
    header2 = f"{'プロジェクト':<30}  {'分類':<6}  {'セッション数':>6}  {'合計トークン':>12}"
    lines.append(header2)
    lines.append('-' * len(header2))
    for pname, stats in sorted(project_stats.items(), key=lambda x: -x[1]['total_tokens']):
        lines.append(
            f"{pname:<30}  {stats['category']:<6}  {stats['session_count']:>6}  "
            f"{format_number(stats['total_tokens']):>12}"
        )

    lines.append("\n【按分比率サマリー】")
    if grand_total > 0:
        lines.append(f"  事業用トークン合計:   {format_number(total_business):>12}  ({total_business/grand_total*100:.1f}%)")
        lines.append(f"  非業務トークン合計:   {format_number(total_non_business):>12}  ({total_non_business/grand_total*100:.1f}%)")
        lines.append(f"  全体トークン合計:     {format_number(grand_total):>12}")
        lines.append(f"\n  ★ 当月の家事按分比率（事業割合）: {ratio:.1f}%")
    else:
        lines.append("  トークンデータなし")

    now_str = datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')
    first_day = f"{year}年{month:02d}月01日"
    last_day = f"{year}年{month:02d}月{calendar.monthrange(year, month)[1]:02d}日"
    lines.append("\n【税務証憑用メモ】")
    lines.append(f"  集計期間:   {first_day}〜{last_day}")
    lines.append(f"  集計日時:   {now_str}")
    lines.append(f"  データソース: ~/.claude/projects/ 以下の JSONL ログ")
    lines.append(f"  判定基準:   business-folders.conf に記載のフォルダを業務用として分類")
    lines.append(f"  按分比率:   {ratio:.1f}%（事業用 {format_number(total_business)} / 全体 {format_number(grand_total)}）")
    lines.append("")

    return '\n'.join(lines)


def compute_summary(sessions: dict, business_folders: list[str]) -> tuple[float, int]:
    """ratio（%）と grand_total トークン数を返す"""
    total_biz = sum(
        total_tokens(s['tokens']) for s in sessions.values()
        if is_business(s['cwd'], business_folders)
    )
    grand = sum(total_tokens(s['tokens']) for s in sessions.values())
    ratio = (total_biz / grand * 100) if grand > 0 else 0.0
    return ratio, grand


CSV_FILENAME = 'summary.csv'
CSV_FIELDS = ['月', '家事按分比率', '合計トークン']


def update_summary_csv(output_dir: Path, year: int, month: int, ratio: float, grand_total: int) -> list[dict]:
    """summary.csv に当月行を upsert して全行を返す"""
    csv_path = output_dir / CSV_FILENAME
    month_key = f"{year}年{month:02d}月"

    rows: list[dict] = []
    if csv_path.exists():
        with open(csv_path, 'r', encoding='utf-8-sig', newline='') as f:
            rows = list(csv.DictReader(f))

    new_row = {'月': month_key, '家事按分比率': f"{ratio:.1f}%", '合計トークン': str(grand_total)}
    updated = False
    for row in rows:
        if row['月'] == month_key:
            row.update(new_row)
            updated = True
            break
    if not updated:
        rows.append(new_row)

    rows.sort(key=lambda r: r['月'])

    with open(csv_path, 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    return rows


def vlen(s: str) -> int:
    """全角文字（CJK など）を幅2、それ以外を幅1として文字列の表示幅を返す"""
    w = 0
    for c in s:
        cp = ord(c)
        if (0x1100 <= cp <= 0x115F or 0x2E80 <= cp <= 0x9FFF or
                0xAC00 <= cp <= 0xD7A3 or 0xF900 <= cp <= 0xFAFF or
                0xFE10 <= cp <= 0xFE19 or 0xFE30 <= cp <= 0xFE6F or
                0xFF01 <= cp <= 0xFF60 or 0xFFE0 <= cp <= 0xFFE6):
            w += 2
        else:
            w += 1
    return w


def vcenter(s: str, width: int) -> str:
    """表示幅 width に収まるよう s をセンタリングしてスペースパディングする"""
    pad = max(0, width - vlen(s))
    left = pad // 2
    return ' ' * left + s + ' ' * (pad - left)


def print_summary_table(rows: list[dict]) -> None:
    """summary.csv の内容をボックス罫線テーブルで表示する"""
    headers = ['月', '家事按分比率', '合計トークン']
    data = [[r['月'], r['家事按分比率'], f"{int(r['合計トークン']):,}"] for r in rows]

    col_widths = [
        max(vlen(h), max(vlen(row[i]) for row in data)) + 2
        for i, h in enumerate(headers)
    ]
    w0, w1, w2 = col_widths

    def bar(l, m, r):
        return l + '─' * w0 + m + '─' * w1 + m + '─' * w2 + r

    def row_line(v0, v1, v2):
        return f"│{vcenter(v0, w0)}│{vcenter(v1, w1)}│{vcenter(v2, w2)}│"

    print()
    print(bar('┌', '┬', '┐'))
    print(row_line(*headers))
    print(bar('├', '┼', '┤'))
    for i, row in enumerate(data):
        print(row_line(*row))
        if i < len(data) - 1:
            print(bar('├', '┼', '┤'))
    print(bar('└', '┴', '┘'))


def generate_report(year: int, month: int) -> None:
    env = load_env()

    conf_raw = env.get('BUSINESS_FOLDERS_CONF', '')
    conf_path = resolve_path(conf_raw) or (SKILL_DIR / 'config' / 'business-folders.conf')

    output_dir = resolve_path(env.get('REPORT_OUTPUT_DIR', ''))

    projects_dir = Path.home() / '.claude' / 'projects'

    business_folders = load_business_folders(conf_path)
    sessions = scan_sessions(projects_dir, year, month)

    if not sessions:
        print(f"\n対象期間（{year}年{month:02d}月）のセッションデータが見つかりませんでした。")
        return

    ratio, grand_total = compute_summary(sessions, business_folders)
    report = build_report_text(year, month, sessions, business_folders)

    # 標準出力に表示
    print(report)

    # REPORT_OUTPUT_DIR が設定されていればファイルにも保存
    if output_dir:
        output_dir.mkdir(parents=True, exist_ok=True)

        # TXT レポート保存
        output_file = output_dir / f"{year}-{month:02d}.txt"
        output_file.write_text(report, encoding='utf-8')
        print(f"📄 保存しました: {output_file}")

        # summary.csv 更新（upsert）してテーブル表示
        rows = update_summary_csv(output_dir, year, month, ratio, grand_total)
        print_summary_table(rows)
        print(f"📊 更新しました: {output_dir / CSV_FILENAME}")


def main():
    if len(sys.argv) >= 2:
        arg = sys.argv[1]
        try:
            dt = datetime.strptime(arg, '%Y-%m')
            year, month = dt.year, dt.month
        except ValueError:
            print(f"エラー: 年月の形式が正しくありません（例: 2026-03）: {arg}", file=sys.stderr)
            sys.exit(1)
    else:
        now = datetime.now()
        year, month = now.year, now.month

    generate_report(year, month)


if __name__ == '__main__':
    main()
