# workbench

複数のリポジトリと作業ディレクトリを一覧し、大きな差分を「1つの決定とその波及」で読めるローカル作業コンソール。

skill 側の手順は `skills/workbench/SKILL.md`（このリポジトリが正本）。
`~/.claude/skills/workbench/SKILL.md` と `~/dev/workbench` は chezmoi が張る symlink なので、編集するときはリポジトリ側を直す。

## 起動

サーバはマシンで1本だけ起動し、固定ポート5170を使う。

```bash
pnpm dev
```

Vite は `strictPort` で起動するため、5170が使用中なら別ポートへ移らず失敗する。
`GET http://localhost:5170/api/health` が `{"app":"workbench"}` を返せば、既存のサーバをそのまま使う。
テストサーバは `WORKBENCH_STATE_DIR` で registry を、`WORKBENCH_CACHE_DIR` で Vite の依存最適化キャッシュを分離できる。

## 作業一覧

`~/.local/state/workbench/roots.json` は、登録したリポジトリのメイン worktree の絶対パスを配列で持つ。
`tools/register-root.sh <repository-root>` が冪等に追記し、`start-implementation` の作業ディレクトリ作成後にも呼ばれる。

ホーム `http://localhost:5170/` は registry の各リポジトリを走査し、リポジトリ、ブランチ、セッションの3階層で表示する。
ブランチは `git worktree list --porcelain`、セッションは各 checkout の `tmp/NNNN_<name>/` から導出する。

セッションは `http://localhost:5170/s/<id>` で開く。
ID はチェックアウトの絶対パスと作業ディレクトリ名から決まるため、サーバ再起動後も同じパスなら変わらない。
ただし `finish-worktree` でセッションを別の checkout へ移した場合やディレクトリ名を変えた場合は ID が変わり、以前の URL は 404 になる。

## Plan レビュー

`http://localhost:5170/s/<id>?view=plan` は `plan.md` を見出しの木として表示する。
クエリが無い場合は `report.json` があれば Review、無ければ Plan を開く。
ヘッダーの Plan / Review で表示を切り替えると履歴に残るため、ブラウザの戻る・進むも使える。

`概要`、`方針`、`リスク` の葉は確認し、`判断` の葉は accept する。
文書全体の確認とすべての確認・accept が揃い、所感以外の未解決コメントが0件になると `実装を承認` を押せる。
承認は `plan.md` のバイト列ハッシュと状態 revision に紐づき、Plan またはコメント・確認状態が変わると失効する。

Plan の状態は `<work>/review/plan.json` に置く。
ブラウザの更新は revision 付きの API を通し、エージェントは人間が付けたコメントのラベルと発言、`confirmations`、`approval` を書き換えない。

## 差分データの生成

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
```

`--findings` は実装検証の指摘を取り込むときだけ渡す。
省くと findings は反映されない。

## データと監視

ブラウザはセッション別の API を通して `review/thread.json` に人間のターンを書き、エージェントは同じファイルに自分のターンを足す。
互いに相手の領域を触らない。

開いたセッションの `thread.json` が外から変わると、そのセッションだけが再取得する。
`report.json` が変わると、そのセッションのページが自動でリロードする。
`plan.md` または `review/plan.json` が変わると、開いている Plan だけが再取得する。
計画段階で `review/` や `report.json` が無いセッションもホームに並び、ページには diff がまだ無いことを表示する。

## Plan 描画の手動確認

安全性確認は実際の計画を変更しない専用セッションで行う。
`src/components/plan/manual/plan.md` をそのセッションの `plan.md` へコピーし、セッション ID を解決して Plan を開く。

```bash
WORK_DIR=/absolute/path/to/repository/tmp/NNNN_plan-render-check
cp src/components/plan/manual/plan.md "$WORK_DIR/plan.md"
SESSION_ID="$(curl -fsS -G --data-urlencode "workDir=$WORK_DIR" \
  http://localhost:5170/api/resolve | jq -r .id)"
open "http://localhost:5170/s/$SESSION_ID?view=plan"
```

ブラウザの開発者ツールで次を確認する。

- `javascript:` の文字列は見えるがリンク要素にならず、クリックしても実行されない。
- 外部画像は画像要素にならず、alt テキストと URL だけが見える。Network に `example.invalid` への要求が出ない。
- `<script>` 要素は生成されず、内容は実行されないプレーンテキストとして見える。ノードの「原文」ではタグを含む文字列として見える。
- 表のセル内の `<strong>` は要素にならず、前後のテキストと Markdown の強調は残る。

watcher は Plan を開いたまま `plan.md` の本文を編集し、リロードなしで表示と確認状態が更新されることを確認する。
続けて開発者ツールの Network を開き、`touch "$WORK_DIR/review/plan.json"` の後に Plan API が再取得されることを確認する。

## 制約

`vite build` と `vite preview` は動く成果物を作らない。
API は `configureServer` にしか実装されておらず、`configurePreviewServer` が無いためである。
このツールは dev サーバ専用として使う。
