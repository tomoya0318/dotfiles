---
name: apply-review
description: Classifies implementation review findings, obtains user approval, and applies only approved fixes.
disable-model-invocation: true
argument-hint: /apply-review <work-dir>
---

# レビュー指摘を適用する

`review.md` の実装検証を読み、各指摘を修正、保留、却下に分類する。
指摘を黙って捨てず、理由と file:line、確信度を表に残す。
ユーザーが修正対象を承認するまで編集しない。
承認後、実装した codex に承認済み指摘だけを修正させ、差分を確認する。
コミットメッセージやコメントの主張ではなく現物で確認する。
修正範囲に応じて `.claude/impl-workflow.md` の DoD コマンドを実行し、結果を review.md に追記する。
