---
name: run-codex-tab
description: Codexを別タブで起動して実装・レビュー・調査・相談などを委譲するときに使う。herdr環境では対話タブを開き、結果ファイルを通じて完了・ユーザー判断待ち・異常を扱う。
argument-hint: /run-codex-tab <config.yaml>
---

# Codexを別タブで走らせる

別の Codex に作業を委譲し、ユーザーが進行を見たり途中で介入したりできるようにする。
実装、実装検証、計画検証、読み取り専用の相談など、親のコンテキストから分離したい作業に使う。

## 起動

この skill のディレクトリを `<skill-dir>` とする。
プロンプトと結果ファイルを先に用意し、起動条件を YAML に書いて `scripts/spawn-codex-tab.sh --config <config.yaml>` で起動する。
結果ファイルの親ディレクトリは事前に作成しておく。

```bash
# <config.yaml>
task: impl
model: gpt-5.6-luna
effort: xhigh
sandbox: workspace-write
name: impl-feature-name
cwd: /path/to/repository
prompt_file: /path/to/prompt.md
result_file: /path/to/result.md
no_wait: true
```

```bash
bash <skill-dir>/scripts/spawn-codex-tab.sh --config <config.yaml>
```

YAML はトップレベルのスカラー項目だけを受け付ける。
`task`、`model`、`effort` は毎回明示し、`task` は `impl`・`review`・`consult` のいずれかにする。
`name` はタブと pane のラベルになるため、英数字・ハイフン・アンダースコアだけの短い名前にする。
`cwd` は Codex が実際に作業するリポジトリのルートを必ず指定する。
`prompt_file` には目的、担当範囲、変更してよい範囲、検証方法、結果ファイルへの報告形式を書く。
`result_file` は起動時に削除されるため、既存の重要なファイルを指定しない。
`no_wait: true` で起動だけして戻り値を受け取り、長い作業や並行実行は wait script で待つ。

`--config` と CLI オプションを併用した場合は、CLI オプションが YAML の値を上書きする。
CLI では `task` の代わりに `--role` または `--task` を指定できる。
YAML の読み込みに失敗した場合は `spawn-failed` として返る。

役割ごとの推奨設定は次のとおりとする。

| role | 用途 | sandbox | model / effort |
|---|---|---|---|
| `impl` | コードや成果物の実装 | `workspace-write` | `gpt-5.6-luna` / `xhigh` |
| `review` | 差分・計画・成果物の検証 | `workspace-write` または指示に合わせる | `gpt-5.6-luna` / `xhigh` |
| `consult` | 上位モデルへの読み取り専用相談 | `read-only` | `gpt-5.6-sol` / `xhigh` |

`review` を指摘だけに限定する場合は、プロンプトで編集可能なファイルを結果ファイルなどに限定する。
`consult` は `--sandbox read-only` を指定し、結果ファイルの保存先を `--cwd` の外に置く。

## 待機と再開

`--no-wait` で起動した run は、戻り値の `pane_id` と `result_file` を保存してから `scripts/wait-codex-tabs.sh` で待つ。
複数 run はすべて `--no-wait` で起動し、`--target <pane_id>=<result-file>` を run ごとに指定する。

```bash
bash <skill-dir>/scripts/wait-codex-tabs.sh \
  --target <pane-id>=<result-file> \
  --timeout 540
```

`timeout` が返った場合は、同じ target で待機を繰り返す。
長時間 run を一度の同期呼び出しで待たない。

戻り値の `status` で分岐する。

| status | 対応 |
|---|---|
| `completed` | 結果ファイルを読み、成果物と報告を確認する |
| `needs-user` | `issue` をユーザーへ提示し、回答を得て再開する |
| `no-result` | タブを開いて原因を確認し、失敗または質問返しとして扱う |
| `timeout` | 同じ引数で待ち直すか、タブの進行を確認する |
| `pane-gone` | タブが閉じられたことを伝え、やり直すか判断する |
| `running` | `--no-wait` で起動済み。wait script に渡す |
| `spawn-failed` / `resume-failed` / `dirty-input` | `error` または `issue` を読み、呼び出しを修正する |

Codex が判断をユーザーへ上げた場合、結果ファイルの1行目は `NEEDS_USER_DECISION: <論点>` とする。
親は代わりに判断せず、ユーザーの回答を `<answer-file>` に書いて再開する。

```bash
bash <skill-dir>/scripts/resume-codex-tab.sh \
  --pane <pane-id> \
  --answer-file <answer-file> \
  --result-file <result-file> \
  --role <impl|review|consult>
```

再開前にタブを閉じない。
決着後もログを確認できるよう、関連作業が終わるまでタブは開いたままにする。

## 実行環境

`HERDR_ENV=1` の herdr 環境では、スクリプトが Codex の対話タブを作り、親 pane とのメタデータを設定する。
herdr の外では同じ引数のまま `codex exec` にフォールバックするため、pane の待機・再開は行わず、起動コマンドの戻り値と結果ファイルを確認する。
Codex CLI が無い場合は、同じプロンプトとスコープを fresh な subagent に渡す。
この代替では別タブの可視性と途中介入は提供できないため、その制約を報告する。

起動・待機・再開の詳細な契約、停止の伝播、既知の落とし穴は [references/run-in-tab.md](references/run-in-tab.md) にまとめている。
