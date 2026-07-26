# workbench

大きな差分を「1つの決定とその波及」でグループ化し、読むべき理由の順に並べて読むためのローカルツール。

skill 側の手順は `skills/workbench/SKILL.md`（このリポジトリが正本）。
`~/.claude/skills/workbench/SKILL.md` と `~/dev/workbench` は chezmoi が張る symlink なので、
編集するときはリポジトリ側を直す。

## 使い方

```bash
# 1. hunk とファイル操作を出す
python3 tools/gen.py <repo> <ref> -o <work>/review/report.json

# 2. AI にグルーピングと理由文を書かせて groups.json を得る（skill の手順3）

# 3. groups と findings と thread を畳み込む
python3 tools/gen.py <repo> <ref> \
  --groups <work>/review/groups.json \
  --findings <work>/review/findings.json \
  --thread <work>/review/thread.json \
  -o <work>/review/report.json

# 4. サーバを起動
DIFF_REVIEW_REPORT=<work>/review/report.json \
DIFF_REVIEW_THREAD=<work>/review/thread.json \
DIFF_REVIEW_CACHE=node_modules/.vite-<n> \
  pnpm dev --port <port>
```

`--findings` は実装検証の指摘を取り込むときだけ渡す。省くと findings は反映されない。

見るファイルは全て環境変数で渡すので、同じ checkout のまま何本でも並行できる。
ポートと `DIFF_REVIEW_CACHE` だけ分ける。
ただし `DIFF_REVIEW_CACHE` の既定値は `node_modules/.vite` でアプリ配下を指すため、
毎回明示しないと vite の最適化キャッシュがアプリのディレクトリに書かれる。

## データ

`thread.json` が唯一の永続物。
ブラウザは `/api/thread` 経由で人間のターンを書き、エージェントは同じファイルに自分のターンを足す。
互いに相手の領域を触らない。

外から `thread.json` が書き換えられると監視が検知し、リロードなしで画面に反映される。
**`report.json` は監視の対象外で、起動時に一度読むだけである。**
差分を作り直したときはブラウザをリロードする。

## 制約

`vite build` と `vite preview` は動く成果物を作らない。
API は `configureServer` にしか実装されておらず、`configurePreviewServer` が無いためである。
このツールは dev サーバ専用として使う。
