---
name: consult-session
description: Conducts a focused confirmation or Q&A session and records only its conclusion for the main implementation session.
disable-model-invocation: true
argument-hint: /consult-session <work-dir> [confirm|qa]
---

# 相談セッション

`/start-implementation` から渡された作業ディレクトリについて、`confirm` は未決事項の判断、`qa` は実装内容の説明を扱う。
作業ディレクトリの plan.md と必要なコードを読み、対話の結論だけを `consult-<topic>.md` に書く。
結論ファイルには決定、理由、残る未決事項を一文一行で記録する。
コード変更はしない。

herdr の右ペインで起動されたセッションであり、ペインの切り替えは herdr の操作を使う。
`spawn-consult.sh` から起動された場合は、main セッションへ結論を再掲せずファイルを保存する。
