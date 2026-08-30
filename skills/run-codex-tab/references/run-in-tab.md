# codex を herdr の tab で走らせる

実装、レビュー、相談は `codex exec` の同期実行ではなく herdr の tab を1枚立てて対話モードの codex を走らせる。
ユーザーが進行を見られ、詰まったときにその場で介入できる。
main のコンテキストには結果ファイルしか入らない。

呼び出し側は main でも codex でもよい。
階層が何段でも同じ引数で使える。

## スクリプト

`scripts/` の3本を使う。
中身を読む必要はなく、通常は引数と戻り値だけで扱える。

### spawn-codex-tab.sh

tab を1枚立てて codex を起動する。
既定では決着するまで待つ。

| 引数 | 既定 | 説明 |
|---|---|---|
| `--name` | 必須 | tab と pane のラベル。`impl-<要件名>` `review-<要件名>` `consult-<論点名>` |
| `--cwd` | 必須 | codex の作業ルート |
| `--prompt-file` | 必須 | プロンプト。起動時に argv で渡す |
| `--result-file` | 必須 | codex に書かせる結果ファイル。決着の判定に使う |
| `--role` | `impl` | `impl` / `review` / `consult` |
| `--model` | `gpt-5.6-luna` | 相談だけ `gpt-5.6-sol` |
| `--effort` | `xhigh` | |
| `--sandbox` | `workspace-write` | 相談は `read-only` |
| `--timeout` | `1800` | 秒 |
| `--parent` | 呼び出し元の pane | 階層を辿るためのメタデータ |
| `--no-wait` | — | 起動だけして返す。並行実行で使う |
| `--config` | — | 下記の YAML 設定を読み込む。CLI オプションが優先 |

`--config` はトップレベルのスカラー項目だけを持つ YAML ファイルを受け付ける。
`task`、`model`、`effort` は必須で、`task` は `impl`・`review`・`consult` のいずれかにする。
`name`、`cwd`、`prompt_file`、`result_file`、`sandbox`、`timeout`、`parent`、`no_wait` も指定できる。
`task: consult` では `sandbox: read-only` を指定し、結果ファイルの保存先を `--cwd` の外に置く。

### wait-codex-tabs.sh

`--no-wait` で起動した run をまとめて待ち、最初に決着した1本を返す。

| 引数 | 既定 | 説明 |
|---|---|---|
| `--target` | 必須 | `<pane_id>=<result_file>`。run の数だけ並べる。区切りは `=`（pane_id 自身がコロンを含むため） |
| `--timeout` | `540` | 秒 |

決着した run を除いて呼び直す。
残りが無くなるまで繰り返す。

### resume-codex-tab.sh

`needs-user` で止まっている tab に回答を届けて再開する。

| 引数 | 既定 | 説明 |
|---|---|---|
| `--pane` | 必須 | 対象 pane |
| `--answer-file` | 必須 | ユーザーの回答。何を書くかも指示に含める |
| `--result-file` | 必須 | 再開後の判定に使う。送信前に削除される |
| `--role` | `impl` | |
| `--timeout` | `1800` | 秒 |

## 戻り値

3本とも1行の JSON を返す。
`status` で分岐する。

| status | 意味 | 呼び出し元の対応 |
|---|---|---|
| `completed` | 結果ファイルが書かれた | 読んで次へ進む |
| `needs-user` | 判断をユーザーへ上げてきた | `issue` を提示し、回答を得て resume |
| `no-result` | 落ち着いたのに結果ファイルが無い | tab を開いて原因を読む。質問返しか失敗 |
| `timeout` | 期限内に決着しなかった | 同じ引数で待ち直すか tab を見る |
| `pane-gone` | tab が閉じられたか異常終了した | ユーザーに伝える。やり直しはユーザーが決める |
| `running` | `--no-wait` で起動した | `wait-codex-tabs.sh` で待つ |
| `spawn-failed` `resume-failed` `dirty-input` | 呼び出しの不備 | `error` か `issue` を読んで直す |

## 停止の伝播

判断がユーザーに要ると分かった時点で、その階層から上が全部止まる。
どの階層も入力待ちのまま生きているので、回答が出たら上から順に再開できる。

| 段階 | 合図 | 受け手の動作 |
|---|---|---|
| 上位モデルが判断不能 | 結果ファイルの行頭に `NEEDS_USER_DECISION: <論点>` | — |
| スクリプトが検出 | 戻り値 `needs-user`、`issue` に論点 | 呼び出し元へ返す |
| 実装者が受領 | 自分の結果ファイルにも同じ行を書いて応答を終える | 自分も入力待ちで止まる |
| main が受領 | `issue` をユーザーへ提示 | 回答を `--answer-file` にして再開 |

## 共通キー

各 pane に貼られる。
`herdr pane get <pane_id>` の `tokens` で読める。
キーは `^[A-Za-z0-9_-]{1,32}$` しか使えない。
ドットを含めると `invalid_metadata_token` になる。

| キー | 値 |
|---|---|
| `codex_role` | `impl` / `review` / `consult` |
| `codex_status` | `running` / `completed` / `needs-user` / `no-result` / `timeout` |
| `codex_result` | 結果ファイルの `<作業ディレクトリ名>/<ファイル名>`。値は64文字ほどで切られるため絶対パスは載せない |
| `codex_parent` | 呼び出し元の pane_id。辿ると階層が復元できる |
| `codex_issue` | `needs-user` のときの論点 |

## main が守ること

Bash ツールのタイムアウト上限は10分である。
長い run は `--no-wait` で起動して `wait-codex-tabs.sh --timeout 540` を返るまで呼び直す。
待っている間はツールの結果を待つだけなのでトークンを消費しない。

tab は決着しても閉じない。
関連作業が完了してログを確認するまで残す。

## 落とし穴

以下はスクリプトの中で対処済みである。
手で herdr を叩くときだけ気にする。

`herdr tab create` は root_pane を1枚含む tab を返す。
そこへ `agent start --tab` すると空のシェルが1枚余るので、root_pane をそのまま使う。

`--workspace` と `--cwd` は省略できない。
省くと最後にアクティブだった別 workspace や、workspace 既定の cwd に飛ぶ。

完了後の状態は `done` になる run と `idle` になる run があり、`done` は一瞬で消えることもある。
`herdr wait agent-status --status done` は取り逃す。
決着は結果ファイルの有無で判定する。

TUI へ文字を送るのは、入力欄が空のときだけにする。
`/usage` のようなサジェストが残っていると送信内容が連結されて壊れる。

入力欄のクリアに `send-keys ctrl+c` を使わない。
codex ごと終了する。
落ちた場合は pane に出る `codex resume <session-id>` で復帰できる。

`codex exec` と対話 codex のどちらも、上位モデルへの相談には
`--add-dir "$HOME/.codex"` と `-c sandbox_workspace_write.network_access=true` の両方が要る。
片方だけでは子 codex が app-server を初期化できずに落ちる。

## herdr が無い環境

`HERDR_ENV` が `1` でなければ、`spawn-codex-tab.sh` は `codex exec` の同期実行に落ちる。
戻り値の形は同じで、`pane_id` と `tab_id` が空になる。
`wait-codex-tabs.sh` と `resume-codex-tab.sh` はこの環境では使わない。
