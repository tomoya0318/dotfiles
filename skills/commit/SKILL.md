---
name: commit
description: Analyzes current changes and creates a commit using the project's commit rules.
disable-model-invocation: true
argument-hint: /commit
---

# コミットする

`git status` と `git diff` を確認し、変更の主目的に合う type を選ぶ。
形式は `<type>: <日本語の主題>` とし、type は `feat`、`fix`、`docs`、`style`、`refactor` のいずれかにする。
主題は簡潔にする。
ユーザーがコミットを求めていない場合は実行しない。
実行時は `git add .` と `git commit -m` を使い、対話的なエディタを起動しない。
