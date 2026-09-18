# empirical-prompt-tuning

agent 向けテキスト指示（skill / slash command / task プロンプト / CLAUDE.md 節 / コード生成プロンプトなど）を、バイアスを排した実行者に動かしてもらい、両面（実行者の自己申告 + 指示側メトリクス）で評価して反復改善する手法をまとめたスキル。改善が頭打ちになるまで回す想定で使う。

プロンプトや skill を新規作成・大幅改訂した直後や、エージェントの挙動が期待通りにならない原因を指示側の曖昧さに求めたいときに呼び出す。

## 出典

`SKILL.md` は以下からコピーしてきました。

- コピー元: https://github.com/mizchi/chezmoi-dotfiles/blob/main/dot_claude/skills/empirical-prompt-tuning/SKILL.md
- 原著者: [@mizchi](https://github.com/mizchi)

コピー元のリポジトリにはライセンスが設定されていないため、配布・改変の扱いは原著者の意向に従ってください。このファイルは原著者へのクレジット明示のために置いています。
