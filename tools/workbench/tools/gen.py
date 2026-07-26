#!/usr/bin/env python3
"""git の差分と AI のグルーピング結果から、レビュー画面用の report.json を生成する。

AI に diff 本文を書かせない。本文は常に git から取り、AI の出力は ID 参照のみを使う。
"""
import argparse, json, os, re, subprocess
from collections import Counter, defaultdict

IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
IMPORT = re.compile(r'^\s*(import\b|from\s+\S+\s+import\b|export\s+.*\bfrom\b|const\s+\{?[^=]*\}?\s*=\s*require\()')
DEFN = re.compile(r'^\s*(async\s+)?(def|class|function|interface|type|enum|struct)\b'
                  r'|^\s*export\s+(async\s+)?(function|class|const|interface|type|enum)\b'
                  r'|^\s*(const|let|var)\s+\w+\s*[:=].*=>')
CTRL = re.compile(r'\b(if|elif|else|for|while|try|except|catch|switch|case|finally|with)\b')
CONF = re.compile(r'[（(]?\s*確信度\s*[:：]\s*(高|中|低)\s*[）)]?\s*[。.]?\s*$')


def git(repo, *args):
    return subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True, check=True).stdout


def split_files(patch):
    """patch を `diff --git` 単位に割る。パスは +++/--- ヘッダから取り、両方 /dev/null でない方を使う。"""
    out, cur = [], None
    for line in patch.splitlines():
        if line.startswith('diff --git '):
            cur = {'raw': [line], 'old': None, 'new': None}
            out.append(cur)
        elif cur is None:
            continue
        else:
            cur['raw'].append(line)
            if line.startswith('--- '):
                cur['old'] = None if line == '--- /dev/null' else line[6:]
            elif line.startswith('+++ '):
                cur['new'] = None if line == '+++ /dev/null' else line[6:]
    for f in out:
        f['raw'] = '\n'.join(f['raw']) + '\n'
        f['path'] = f['new'] or f['old']
    return out


def split_hunks(raw):
    out, cur = [], None
    for line in raw.splitlines():
        if line.startswith('@@'):
            cur = {'header': line, 'add': [], 'del': []}
            out.append(cur)
        elif cur is not None:
            if line.startswith('+'):
                cur['add'].append(line[1:])
            elif line.startswith('-'):
                cur['del'].append(line[1:])
    return out


def classify(h):
    add, dele = h['add'], h['del']
    changed = [l for l in add + dele if l.strip()]
    kinds = []
    if not changed:
        return ['empty']
    if all(IMPORT.match(l) for l in changed):
        kinds.append('import_only')
    if add and dele and Counter(IDENT.sub('X', l.strip()) for l in add) == \
                        Counter(IDENT.sub('X', l.strip()) for l in dele):
        kinds.append('pure_substitution')
    if any(DEFN.match(l) for l in add):
        kinds.append('definition')
    if Counter(CTRL.findall(' '.join(add))) != Counter(CTRL.findall(' '.join(dele))):
        kinds.append('control_flow')
    if dele and not add:
        kinds.append('deletion_only')
    return kinds or ['other']


def core_candidate(kinds):
    if {'pure_substitution', 'import_only', 'empty'} & set(kinds):
        return False
    return True


def file_ops(repo, ref):
    """移動を「同じ配置換え」でまとめ、決定要素にする。新規・削除はディレクトリ単位でまとめる。"""
    raw = git(repo, 'show', ref, '-M', '--format=', '--raw')
    moves, adds, dels = [], [], []
    for line in raw.splitlines():
        if not line.startswith(':'):
            continue
        meta, _, paths = line.partition('\t')
        status, parts = meta.split()[-1], paths.split('\t')
        rec = {'status': status, 'old': parts[0], 'new': parts[-1], 'silent': status == 'R100'}
        if status.startswith('R') and parts[0] != parts[-1]:
            moves.append(rec)
        elif status == 'A':
            adds.append(rec)
        elif status == 'D':
            dels.append(rec)

    buckets = defaultdict(list)
    for o in moves:
        a, b = o['old'].split('/'), o['new'].split('/')
        while a and b and a[0] == b[0]:
            a, b = a[1:], b[1:]
        buckets[('/'.join(a[:-1]) or '.', '/'.join(b[:-1]) or '.')].append(o)

    ops, n = [], 0
    for (src, dst), items in sorted(buckets.items(), key=lambda x: -len(x[1])):
        n += 1
        ops.append({'id': f'f{n:03d}', 'kind': 'move', 'from': src, 'to': dst,
                    'files': [{'old': i['old'], 'new': i['new'], 'silent': i['silent']} for i in items],
                    'silentCount': sum(1 for i in items if i['silent'])})
    # 新規/削除はディレクトリ単位で割る。1つの巨大な袋にすると分割という決定が埋没する
    for kind, group in (('add', adds), ('delete', dels)):
        by_dir = defaultdict(list)
        for o in group:
            p = o['new'] if kind == 'add' else o['old']
            by_dir[p.rsplit('/', 1)[0] if '/' in p else '.'].append(p)
        for d, paths in sorted(by_dir.items(), key=lambda x: -len(x[1])):
            n += 1
            ops.append({'id': f'f{n:03d}', 'kind': kind, 'dir': d,
                        'files': [{'new' if kind == 'add' else 'old': p} for p in sorted(paths)],
                        'silentCount': 0})
    return ops


def attach_ripple(groups, hunks, ops):
    """波及 hunk をグループへ機械的に帰属させる。件数は FE が数えるので持たせない。"""
    by_id = {h['id']: h for h in hunks}
    owner_by_file, owner_by_prefix = {}, {}
    for g in groups:
        for hid in g.get('core', []):
            if hid in by_id:
                owner_by_file.setdefault(by_id[hid]['file'], g['id'])
        for fid in g.get('core', []) + g.get('ripple', []):
            for op in ops:
                if op['id'] != fid:
                    continue
                for f in op['files']:
                    owner_by_prefix.setdefault(f.get('new') or f.get('old'), g['id'])

    assigned = {hid for g in groups for hid in g.get('core', []) + g.get('ripple', [])}
    orphans = []
    for h in hunks:
        if h['id'] in assigned:
            continue
        gid = owner_by_file.get(h['file']) or owner_by_prefix.get(h['file'])
        if gid:
            next(g for g in groups if g['id'] == gid).setdefault('ripple', []).append(h['id'])
        else:
            orphans.append(h['id'])
    orphans += [op['id'] for op in ops if op['id'] not in assigned]

    # 受け皿を2つに分ける。機械的と判定済みのものを「意図不明」に混ぜると、
    # 本当に読むべき未分類が 443 件の中に埋もれる
    mechanical = [i for i in orphans if i in by_id and not by_id[i]['coreCandidate']]
    unclear = [i for i in orphans if i not in mechanical]
    if mechanical:
        groups.append({'id': 'g_mechanical', 'title': '機械的な置換として畳まれた変更',
                       'tags': ['機械的'], 'reason': '', 'core': [], 'ripple': mechanical})
    if unclear:
        groups.append({'id': 'g_unclear', 'title': 'どのグループにも帰属しなかった変更',
                       'tags': ['意図不明'], 'reason': '', 'core': [], 'ripple': unclear})
    return groups


def find_anchor(files, hunks, hunk_id, needle):
    """指摘を hunk 内の実在する行に着地させる。lineText が無いと再生成でアンカーを引き直せない。"""
    h = next((x for x in hunks if x['id'] == hunk_id), None)
    if not h:
        return None
    f = next(x for x in files if x['id'] == h['fileId'])
    blocks, cur = [], None
    for line in f['diff'].splitlines():
        if line.startswith('@@'):
            cur = []
            blocks.append(cur)
        elif cur is not None and not line.startswith('\\'):
            cur.append(line)
    body = blocks[h['index']] if h['index'] < len(blocks) else []

    changed = [(i, l) for i, l in enumerate(body) if l[:1] in '+-']
    if not changed:
        return None

    def at(i, l, exact):
        return {'offset': i, 'lineText': l[1:], 'side': 'new' if l[0] == '+' else 'old',
                'exact': exact}

    if needle and needle.strip():
        for i, l in changed:
            if needle.strip() in l:
                return at(i, l, True)
        # 完全一致しないことは多い（`session.commit()` と `self.db.commit()` など）。
        # 識別子単位で最も一致する行を選ぶ。先頭行へ落とすと指摘が無関係な行に着く
        toks = [t for t in IDENT.findall(needle) if len(t) > 2]
        if toks:
            scored = [(sum(t in l for t in toks), max((len(t) for t in toks if t in l), default=0), i, l)
                      for i, l in changed]
            best = max(scored)
            if best[0]:
                return at(best[2], best[3], False)

    i, l = changed[0]
    return at(i, l, False)


def import_findings(thread, payload, files, hunks):
    """検証者の指摘を AI 発のコメントとして取り込む。何度流しても増えないようにキーで弾く。"""
    existing = {c.get('key') for c in thread['comments'] if c.get('key')}
    n = 0
    for f in payload.get('findings', payload if isinstance(payload, list) else []):
        hunk = f.get('hunk')
        key = f.get('key') or f"{hunk}:{(f.get('body') or '')[:48]}"
        if not hunk or key in existing:
            continue
        anchor = find_anchor(files, hunks, hunk, f.get('line'))
        if not anchor:
            continue
        exact = anchor.pop('exact')
        if f.get('line') and not exact:
            print(f"  {hunk}: 指定行が完全一致しないため近い行に着地させた")

        # 検証者は本文の末尾に「確信度: 高」と書いてくることが多い。
        # バッジで出すので本文からは外す
        body_text = (f.get('body') or '').strip()
        conf = f.get('confidence')
        m = CONF.search(body_text)
        if m:
            conf = conf or m.group(1)
            body_text = CONF.sub('', body_text).rstrip()
        ids = [int(str(c['id'])[1:]) for c in thread['comments'] if str(c['id'])[1:].isdigit()]
        thread['comments'].append({
            'id': f"c{max(ids, default=0) + 1}",
            'key': key,
            'hunk': hunk,
            **anchor,
            'turns': [{'by': f.get('by', 'codex'), 'body': body_text}],
            'state': 'open',
            **({'confidence': conf} if conf else {}),
        })
        existing.add(key)
        n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('repo')
    ap.add_argument('ref')
    ap.add_argument('--groups', help='AI が返したグルーピング JSON')
    ap.add_argument('--thread', default='.review/thread.json',
                    help='行コメントの永続物。存在しなければ空として扱う')
    ap.add_argument('--findings',
                    help='実装検証の指摘 JSON。thread.json へ AI 発のコメントとして取り込む')
    ap.add_argument('-o', '--out', default='report.json')
    a = ap.parse_args()

    patch = git(a.repo, 'show', a.ref, '-M', '--format=', '--patch', '-U3')
    files, hunks, n = [], [], 0
    for i, f in enumerate(split_files(patch)):
        hs = split_hunks(f['raw'])
        ids = []
        for j, h in enumerate(hs):
            n += 1
            hid = f'h{n:03d}'
            kinds = classify(h)
            ids.append(hid)
            hunks.append({'id': hid, 'file': f['path'], 'fileId': f'F{i}', 'index': j,
                          'kinds': kinds, 'coreCandidate': core_candidate(kinds),
                          'add': len(h['add']), 'del': len(h['del'])})
        files.append({'id': f'F{i}', 'old': f['old'], 'new': f['new'],
                      'path': f['path'], 'diff': f['raw'], 'hunks': ids})

    ops = file_ops(a.repo, a.ref)
    groups = json.load(open(a.groups))['groups'] if a.groups else []
    if groups:
        groups = attach_ripple(groups, hunks, ops)

    tpath = a.thread if os.path.isabs(a.thread) else os.path.join(a.repo, a.thread)
    thread = json.load(open(tpath)) if os.path.exists(tpath) else {}
    thread.setdefault('comments', [])
    thread.setdefault('checks', [])

    if a.findings:
        added = import_findings(thread, json.load(open(a.findings)), files, hunks)
        if added:
            os.makedirs(os.path.dirname(tpath) or '.', exist_ok=True)
            json.dump(thread, open(tpath, 'w'), ensure_ascii=False, indent=1)
        print(f"  指摘を取り込み: 新規 {added} 件")

    report = {
        'ref': a.ref,
        'subject': git(a.repo, 'log', '-1', '--pretty=%s', a.ref).strip(),
        'threadPath': a.thread,
        'repo': os.path.abspath(a.repo),
        'stats': {'files': len(files), 'hunks': len(hunks),
                  'additions': sum(h['add'] for h in hunks),
                  'deletions': sum(h['del'] for h in hunks),
                  'coreCandidates': sum(1 for h in hunks if h['coreCandidate'])},
        'files': files, 'hunks': hunks, 'fileOps': ops, 'groups': groups, 'thread': thread,
    }
    json.dump(report, open(a.out, 'w'), ensure_ascii=False, indent=1)
    s = report['stats']
    print(f"{a.out}  {s['files']} files / {s['hunks']} hunks / 核候補 {s['coreCandidates']} / "
          f"決定要素 {len(ops)} / グループ {len(groups)} / コメント {len(thread['comments'])}")


main()
