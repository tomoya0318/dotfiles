---
name: start-worktree
description: Creates a feature branch and worktree with herdr, then starts the implementation workflow in the new workspace.
disable-model-invocation: true
argument-hint: /start-worktree <branch name or feature description>
---

# worktree を開始する

引数が英数字、スラッシュ、ハイフンで構成された branch 名ならそのまま使う。
説明なら `feature/`、`fix/`、`chore/`、`refactor/` のいずれかを付け、英語のハイフン区切りへ変換する。

`herdr worktree create --cwd . --branch <name> --focus` で作成し、新しい workspace を起動する。
作成後、その workspace で `.claude/impl-workflow.md` の worktree セットアップコマンドを実行する。
設定がなければ `/setup-impl-workflow` を案内する。
セットアップ完了後、新 workspace で `/start-implementation` を実行する。
