---
name: monthly-report
description: Claude Code の月次利用実績を集計し、家事按分比率（事業割合）を算出するレポートを生成する
argument-hint: "[YYYY-MM]"
---

Claude Code の月次家事按分レポートを生成します。

## 手順

1. 以下のコマンドを Bash ツールで実行する：

```bash
python3 ~/.claude/skills/monthly-report/scripts/generate-report.py $ARGUMENTS
```

2. 出力結果をそのまま表示する。

3. 必要に応じて以下を補足する：
   - 「家事按分比率」欄の数値が確定申告で使用する経費計上割合
   - 事業用フォルダの変更: `~/.claude/skills/monthly-report/config/business-folders.conf` を編集
   - レポート保存先の変更: `~/.claude/skills/monthly-report/.env` の `REPORT_OUTPUT_DIR=` に絶対パスを設定

## 引数

- 引数なし → 当月
- `YYYY-MM` 形式 → 指定月（例: `2026-03` → 2026年3月）
