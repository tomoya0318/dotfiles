# workbench

複数のリポジトリと作業ディレクトリを一覧し、大きな差分を「1つの決定とその波及」で読めるローカル作業コンソール。

差分レビューは VSCode で読む運用へ移したため、この作業コンソールを駆動する skill は削除した。
アプリと `tools/gen.py` は残してあり、手動で起動すれば使える。
`~/dev/workbench` は chezmoi が張る symlink なので、編集するときはリポジトリ側を直す。

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

## 差分データの生成

```bash
# 1. hunk とファイル操作を出す
python3 tools/gen.py <repo> <ref> -o <work>/review/report.json

# 未コミットの変更を見るなら --uncommitted を付ける（未追跡ファイルも含む。index は触らない）
python3 tools/gen.py <repo> HEAD --uncommitted -o <work>/review/report.json

# 2. AI にグルーピングと理由文を書かせて groups.json を得る

# 3. groups と findings と thread を畳み込む
python3 tools/gen.py <repo> <ref> \
  --groups <work>/review/groups.json \
  --findings <work>/review/findings.json \
  --thread <work>/review/thread.json \
  -o <work>/review/report.json
```

`--findings` は実装検証の指摘を取り込むときだけ渡す。
省くと findings は反映されない。

`--uncommitted` を使う場合は、再生成のときも同じフラグを付ける。
`report.json` は生成時点の写しなので、レビュー中にコードを直すと hunk がずれる。
コメントは `lineText` で照合し直すため迷子になるだけで壊れないが、ずれたら再生成する。

## データと監視

ブラウザはセッション別の API を通して `review/thread.json` に人間のターンを書き、エージェントは同じファイルに自分のターンを足す。
互いに相手の領域を触らない。

開いたセッションの `thread.json` が外から変わると、そのセッションだけが再取得する。
`report.json` が変わると、そのセッションのページが自動でリロードする。
`review/` や `report.json` がまだ無いセッションもホームに並び、ページには diff がまだ無いことを表示する。

## 制約

`vite build` と `vite preview` は動く成果物を作らない。
API は `configureServer` にしか実装されておらず、`configurePreviewServer` が無いためである。
このツールは dev サーバ専用として使う。
