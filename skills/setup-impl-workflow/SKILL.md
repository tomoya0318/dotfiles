---
name: setup-impl-workflow
description: Interactively discovers project DoD and worktree setup commands and writes .claude/impl-workflow.md.
disable-model-invocation: true
argument-hint: /setup-impl-workflow
---

# 実装ワークフローを設定する

リポジトリ直下で実行する。

1. `mise.toml`、`package.json`、`Makefile`、`CLAUDE.md` を読み、lint、typecheck、test などの DoD 候補を自動検出してユーザーに確認する。
2. worktree 作成後に新 workspace で実行するセットアップコマンドを質問する。
3. 恒常的な高リスク知識であるレビュー重点領域を任意で収集する。
4. 理解ゲートのドメイン文言を任意で収集する。
5. `tmp/` が gitignore されているか確認し、なければ追記を提案する。
6. 合意した内容を `.claude/impl-workflow.md` に書き出す。

設定ファイルの形式は次のとおりとする。

```markdown
# 実装ワークフロー設定

## DoD コマンド
- lint: <command>
- typecheck: <command>
- test: <command>

## worktree セットアップコマンド
<command>

## レビュー重点領域
<任意>

## 理解ゲートのドメイン文言
<任意>

## 作業 dir
tmp/
```

ユーザーが確認していない候補を確定値として書かない。
既存の設定があれば内容を提示し、上書き範囲を確認してから更新する。
