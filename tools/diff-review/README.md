# diff-review

大きな差分を「1つの決定とその波及」でグループ化し、読むべき理由の順に並べて読むためのローカルツール。
skill 側の手順は `~/.claude/skills/diff-review/SKILL.md`。

## 使い方

```bash
# 1. hunk とファイル操作を出す
python3 tools/gen.py <repo> <ref> -o <work>/review/report.json

# 2. AI にグルーピングと理由文を書かせて groups.json を得る（skill の手順3）

# 3. groups と thread を畳み込む
python3 tools/gen.py <repo> <ref> \
  --groups <work>/review/groups.json \
  --thread <work>/review/thread.json \
  -o <work>/review/report.json

# 4. サーバを起動
DIFF_REVIEW_REPORT=<work>/review/report.json \
DIFF_REVIEW_THREAD=<work>/review/thread.json \
DIFF_REVIEW_CACHE=node_modules/.vite-<n> \
  pnpm dev --port <port>
```

**アプリのディレクトリには何も書かない。** 見るファイルは全て環境変数で渡すので、
同じ checkout のまま何本でも並行できる。ポートと `DIFF_REVIEW_CACHE` だけ分ける。

`thread.json` が唯一の永続物。ブラウザは `/api/thread` 経由で人間のターンを書き、
エージェントは同じファイルに自分のターンを足す。互いに相手の領域を触らない。
外から書かれた変更は監視で検知され、リロードなしで画面に反映される。
