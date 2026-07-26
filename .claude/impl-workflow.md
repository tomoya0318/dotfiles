# 実装ワークフロー設定

このリポジトリは chezmoi の dotfiles 正本と、`tools/` 配下の独立プロジェクトが同居する。
DoD コマンドは変更範囲によって切り替える。

## DoD コマンド

### tools/diff-review 配下を変更したとき
- lint: `pnpm -C tools/diff-review lint`
- typecheck: `pnpm -C tools/diff-review exec tsc -b`
- test: なし（テストランナー未導入）

### dot_* / skills 配下を変更したとき
- 展開確認: `chezmoi diff`

### 全範囲共通
- secretlint: `pnpm secretlint`

## worktree セットアップコマンド

```
pnpm -C tools/diff-review install
```

## レビュー重点領域

- chezmoi ソースと実ファイルの取り違え。
  `dot_*` を直さずホーム側の実ファイルを直接編集していないか。
  ソースを変更したのに `chezmoi apply` していない、あるいは適用範囲が意図と違っていないか。
- 秘密情報の混入。
  トークン、API キー、個人パスの直書き。
  secretlint のルールをすり抜ける形での混入。

## 理解ゲートのドメイン文言

未設定。

## 作業 dir

tmp/
