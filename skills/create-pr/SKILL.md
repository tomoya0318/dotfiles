---
name: create-pr
description: Analyzes committed branch changes and creates a pull request with a concise Japanese summary.
disable-model-invocation: true
argument-hint: /create-pr [base-branch]
---

# Pull Request を作る

base branch は省略時 `main` とする。
`git status`、`git log <base>..HEAD`、`git diff <base>..HEAD` を確認する。
未コミットの変更があれば中止して `/commit` を案内する。
変更の目的、変更内容、テスト、関連 issue を日本語でまとめ、必要なら `git push -u origin HEAD` の後に `gh pr create` を非対話で実行する。
PR のタイトルはコミットと同じ `<type>: <日本語の主題>` 形式にする。
プロジェクト固有の DoD は `.claude/impl-workflow.md` を参照する。
