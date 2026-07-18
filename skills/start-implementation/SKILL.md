---
name: start-implementation
description: Starts an implementation with an investigation plan, an understanding gate, adversarial plan and implementation reviews, and a recorded prompt history.
disable-model-invocation: true
argument-hint: /start-implementation <description>
---

# 実装を開始する

`tmp/NNNN_<name>/` に `plan.md`、`review.md`、`prompt.md` を作り、調査、計画検証、承認、実装、実装検証を分離して進める。

## 前提

リポジトリ直下の `.claude/impl-workflow.md` を読む。
存在しなければ `/setup-impl-workflow` の実行を促し、設定が確定するまで実装しない。
作業ディレクトリは設定の上書きがなければ `tmp/` とする。

本文や計画は日本語で書く。
計画と作業記録は一文一行、パラグラフライティング、LLM 口調の禁止、不確実性の保持に従うため、`~/.claude/skills/japanese-tech-writing/SKILL.md` を読む。

## 手順

1. 作業名は英語のハイフン区切りで渡す。ユーザーが説明的な日本語・文章の名前を指定した場合は、main が先に変換する。
   `init-work-dir.sh "<作業名>" "<base-dir>"` を実行し、JSON の作業パスを読む。
   init直後に、ユーザーの初回指示を `prompt.md` に要約・省略せずそのまま記録する。
2. [planning-prompt.md](references/planning-prompt.md) の入力プレースホルダーを作業ディレクトリとリポジトリルートの具体的な値で置換してから read-only subagent に渡して調査する。
3. 調査結果から計画テンプレートの各節を日本語で埋める。
4. [plan-review-prompt.md](references/plan-review-prompt.md) の入力プレースホルダーを作業ディレクトリとリポジトリルートの具体的な値で置換してから、実装者とは別の fresh な codex に渡し、指摘だけを `review.md` の「計画検証」へ記録する。
5. 指摘を計画へ反映し、反映内容を同節へ追記する。
6. `plan.md` をユーザーへ提示する。
   「対象コードの理解」が薄い、または未決事項が残る場合は理解ゲートを通過させず、必要なら `spawn-consult.sh` を使う。
   ユーザーの承認前にコードを変更しない。
7. 承認後、main が Claude Code なら codex plugin の codex-rescue subagent に委譲し、返った diff を検査する。
   codex plugin が利用できない環境では、fresh な subagent に委譲する。
   main が Codex なら自分で実装する。
   実施内容を `prompt.md` に追記し、設定の DoD コマンドを変更範囲に応じて実行する。
8. [impl-review-prompt.md](references/impl-review-prompt.md) の入力プレースホルダーを作業ディレクトリとリポジトリルートの具体的な値で置換してから、実装者とは別の fresh な codex に渡し、修正させず指摘だけを「実装検証」へ追記する。
   指摘をどう直すかはユーザーが判断し、承認された指摘だけを実装側へ修正させる。

## バイアス分離

検証は実装したインスタンスと別の fresh な codex に依頼する。
検証者には指摘だけをさせ、手を動かさせない。
コミットメッセージ、計画、実装側の主張を信用せず、コード、差分、実行結果の現物で確認する。
