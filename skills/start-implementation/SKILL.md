---
name: start-implementation
description: Starts an implementation with an investigation plan, an understanding gate, and adversarial plan and implementation reviews.
disable-model-invocation: true
argument-hint: /start-implementation <description>
---

# 実装を開始する

`tmp/NNNN_<name>/` に `plan.md` と `review.md` を作り、調査、計画検証、承認、実装、実装検証を分離して進める。

## 前提

リポジトリ直下の `.claude/impl-workflow.md` を読む。
存在しなければ `/setup-impl-workflow` の実行を促し、設定が確定するまで実装しない。
作業ディレクトリは設定の上書きがなければ `tmp/` とする。

## 書き方

日本語で書く。一文ごとに改行し、段落は空行で区切る。

短く、要点だけを書く。前置きと但し書きに文字数を使わない。
検討の経緯は書かず、結論と理由と代替案の評価だけを残す。
同じ判断を複数の節へ重複させない。

確かめていないことは、確かめていないまま書く。推量を断定に変えない。
「重要なのは」「〜において」「多角的に」のような、論点を増やさない言い回しを使わない。

`概要`、`判断`、`方針`、`リスク` は人間が読む節なので特に短くする。
`現状の作り` と `実装手順` は実装 AI 向けなので、短さより具体の精度を優先する。

## 規模の判定

対象が2ファイル以内で、調査が数回の grep で済むなら、手順2・4・7 の委譲を飛ばす。
main が直接 `plan.md` を書いて実装し、手順8 の実装検証だけ残す。

サブエージェントは、広い範囲にまたがる調査と、範囲が重ならない単位へ分けられる実装にだけ使う。
main が数回の操作で終わる作業を委譲しない。台数分のコストと時間がそのまま乗る。

## 手順

1. 作業名は英語のハイフン区切りで渡す。ユーザーが説明的な日本語・文章の名前を指定した場合は、main が先に変換する。
   `init-work-dir.sh "<作業名>" "<base-dir>"` を実行し、JSON の作業パスを読む。
   `~/dev/workbench` と `node_modules` がある場合は、任意で `http://localhost:5170/api/health` を確認し、`workbench` が応答しなければ共有 dev サーバを起動してよい。
   サーバを起動できなくても作業開始は失敗させず、`init-work-dir.sh` 自体からは起動しない。
2. [planning-prompt.md](references/planning-prompt.md) の入力プレースホルダーを作業ディレクトリとリポジトリルートの具体的な値で置換してから read-only subagent に渡して調査する。
3. main が要件と調査結果から `概要` を書き、調査結果の `判断`、`方針`、`現状の作り`、`実装手順`、`リスク` を計画テンプレートの同名節へ転記する。
   調査結果の `実装に不可欠なファイル` は main への受け渡しにだけ使い、`plan.md` へ転記しない。
4. [plan-review-prompt.md](references/plan-review-prompt.md) の入力プレースホルダーを作業ディレクトリとリポジトリルートの具体的な値で置換してから、実装者とは別の fresh な codex に渡し、指摘だけを `review.md` の「計画検証」へ記録する。
5. 指摘を計画へ反映し、反映内容を同節へ追記する。
6. 作業ディレクトリを `WORK_DIR` とし、`GET http://localhost:5170/api/resolve?workDir=...` でセッション ID を取得する。
   ユーザーには `http://localhost:5170/s/<id>?view=plan` を伝える。
   `判断` に accept されていないものが残る、または `question` コメントが未解決の場合は理解ゲートを通過させず、必要なら `spawn-consult.sh` を使う。
   `confirmations` と `approval` は AI がファイルへ書かず、workbench での人間の操作だけに委ねる。
   待機前に次のように承認をリセットし、残っている `review/plan-approved` とサーバ上の承認状態を両方消す。
   ```bash
   SESSION_ID="$(curl -fsS -G --data-urlencode "workDir=$WORK_DIR" \
     http://localhost:5170/api/resolve | jq -r .id)"
   curl -fsS -X POST -H 'content-type: application/json' -d '{}' \
     "http://localhost:5170/api/sessions/$SESSION_ID/plan/approve/reset" >/dev/null
   ```
   `until [ -f "$WORK_DIR/review/plan-approved" ]; do sleep 3; done` をバックグラウンドのシェル実行として開始し、タイムアウトを付けずにユーザーの承認を待つ。
   再開時はセンチネルの `nonce` を `POST /plan/approve/consume` へ渡す。
   応答の `approval.nonce` と `approval.planHash` がセンチネルと一致し、センチネルの `planHash` が現在の `plan.md` のバイト列 SHA-256 と一致することを照合する。
   ```bash
   SENTINEL_JSON="$(cat "$WORK_DIR/review/plan-approved")"
   NONCE="$(printf '%s' "$SENTINEL_JSON" | jq -r .nonce)"
   APPROVED_HASH="$(printf '%s' "$SENTINEL_JSON" | jq -r .planHash)"
   CONSUMED_JSON="$(curl -fsS -X POST -H 'content-type: application/json' \
     -d "$(jq -cn --arg nonce "$NONCE" '{nonce:$nonce}')" \
     "http://localhost:5170/api/sessions/$SESSION_ID/plan/approve/consume")"
   CURRENT_HASH="$(shasum -a 256 "$WORK_DIR/plan.md" | awk '{print $1}')"
   test "$(printf '%s' "$CONSUMED_JSON" | jq -r .approval.nonce)" = "$NONCE"
   test "$(printf '%s' "$CONSUMED_JSON" | jq -r .approval.planHash)" = "$APPROVED_HASH"
   test "$CURRENT_HASH" = "$APPROVED_HASH"
   test ! -f "$WORK_DIR/review/plan-approved"
   ```
   consume が失敗した場合、またはいずれかの照合が外れた場合は実装せずユーザーへ戻す。
   consume に成功したセンチネルはサーバが削除するため、残っていないことを確認してから実装へ進む。
   ユーザーの承認前にコードを変更しない。
7. 承認後に実装する。
   規模が大きく、範囲が重ならない単位へ分けられるなら、codex plugin の codex-rescue subagent へ委譲する。分けた単位は並行させてよい。
   codex plugin が利用できない環境では fresh な subagent に委譲する。
   それ以外は main が自分で実装する。
   設定の DoD コマンドを変更範囲に応じて main が実行する。
8. [impl-review-prompt.md](references/impl-review-prompt.md) の入力プレースホルダーを作業ディレクトリとリポジトリルートの具体的な値で置換してから、実装者とは別の fresh な codex に渡し、修正させず指摘だけを「実装検証」へ追記する。
   指摘をどう直すかはユーザーが判断し、承認された指摘だけを実装側へ修正させる。

## バイアス分離

検証は実装したインスタンスと別の fresh な codex に依頼する。
検証者には指摘だけをさせ、手を動かさせない。
検証者は、コミットメッセージ、計画、実装側の主張を信用せず、コード、差分、実行結果の現物で確認する。

main はこの検証と重ねて自分で差分を読み直さない。
main が行うのは DoD コマンドの実行と、指摘のユーザーへの提示である。
