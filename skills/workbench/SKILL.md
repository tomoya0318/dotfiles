---
name: workbench
description: Reviews a large diff by grouping hunks into decisions, ordering them by why a human must read them, and threading line comments back to the agent session.
disable-model-invocation: true
argument-hint: /workbench [<ref-or-range>]
---

# 差分をレビューする

検出は既存の実装検証が担当し、この skill は**理解**を担当する。

## 前提

アプリ本体は `~/dev/workbench`（chezmoi が張る symlink。正本は dotfiles リポジトリの `tools/workbench`）。
これか `node_modules` が無ければ、ユーザーに知らせて止まる。
`pnpm install` を勝手に走らせない。

作業ディレクトリは `tmp/NNNN_<name>/` を既定とし、成果物は `review/` の下に置く。

- `review/report.json` … 毎回生成する。差分とグルーピング
- `review/thread.json` … 唯一の永続物。行コメントと判断状況
- `review/findings.json` … 実装検証の指摘。取り込み用の入力
- `review/handoff` … レビュー完了の合図

成果物はアプリのディレクトリに置かない。
リポジトリの一覧は `~/.local/state/workbench/roots.json` に登録され、セッションは各リポジトリのファイルシステムと git から毎回導出される。

## 手順

1. 引数が無ければ直近のコミット、範囲指定があればそれを対象にする。

2. hunk とファイル操作を出す。

   ```
   python3 ~/dev/workbench/tools/gen.py <repo> <ref> -o <work>/review/report.json
   ```

   核候補が20件未満なら、この手順を中止して差分を直接読む。

3. [grouping-prompt.md](references/grouping-prompt.md) を read-only subagent に渡し、グルーピングと理由文を書かせる。
   `report.json` の `hunks` と `fileOps`、対象リポジトリを入力にする。
   plan があっても渡さない。plan に引きずられない目で読ませるため。
   出力の JSON を `<work>/review/groups.json` に保存する。

4. `review.md` の実装検証があれば、指摘を `<work>/review/findings.json` に落とす。

   ```json
   { "findings": [
     { "hunk": "h030", "line": "self.db.commit()", "by": "codex",
       "confidence": "高", "body": "…" }
   ] }
   ```

   `line` は差分の中の文字列。完全一致しなくても近い行に着地する。
   `confidence` はバッジで出る。本文末尾に「確信度: 高」と書いてあれば自動で抜き出す。
   hunk ID を持たない指摘は取り込まない。file:line しか無ければ、その位置を含む hunk を `report.json` から引く。

5. groups と findings と thread を畳み込んで再生成する。

   ```
   python3 ~/dev/workbench/tools/gen.py <repo> <ref> \
     --groups <work>/review/groups.json \
     --findings <work>/review/findings.json \
     --thread <work>/review/thread.json \
     -o <work>/review/report.json
   ```

   指摘は AI 発のコメントとして `thread.json` に入り、該当行の下に出る。
   何度流しても重複しない。

6. dev サーバの状態を確認し、セッションの URL をユーザーに伝える。

   固定 URL `http://localhost:5170/api/health` を読み、JSON の `app` が `workbench` なら既存サーバを使う。
   応答が無ければ `pnpm --dir ~/dev/workbench dev` をバックグラウンドで起動し、同じヘルスチェックが通るまで待つ。
   2つの skill が同時に起動すると、片方は `strictPort` により失敗しうる。
   起動に失敗した場合はヘルスチェックをやり直し、`workbench` が応答していれば成功として扱う。
   ポートから応答があるのに `app` が `workbench` でなければ、別のアプリが5170を使っていることを人間に知らせて止まる。

   サーバが応答したら、次の API で作業ディレクトリからセッション ID を引く。

   ```
   curl -sS -G --data-urlencode "workDir=<work の絶対パス>" \
     http://localhost:5170/api/resolve
   ```

   応答の `id` を使い、`http://localhost:5170/s/<id>` をユーザーに伝える。
   セッション URL はチェックアウトの絶対パスと作業ディレクトリ名に従属する。
   `finish-worktree` で移動または改名すると ID が変わり、以前の URL は 404 になる。

7. `review/handoff` が現れるまで待つ。バックグラウンドのシェルに待たせる。

   ```
   until [ -f <work>/review/handoff ]; do sleep 3; done
   ```

   **タイムアウトを付けない。催促もしない。**
   `thread.json` の変更ごとに起こされる作りにはしない。1コメント1回モデルが動くことになる。

   ユーザーが合図を貼ったら、待機を捨てて進む。
   `handoff` は消費したら削除する。

8. `thread.json` の `state: "open"` なコメントに対応する。

   - `label: "fix"` … コードを直す
   - `label: "question"` … コードを変えずに答える。**現物を確認してから答える**
   - `label: "note"` … 対応不要。`state` を `resolved` にする

   `turns[0].by` が `you` でないものは検証者の指摘で、人間のトリアージ待ち。**触らない。**

   対応したら `turns` の末尾に自分の発言を足し、`state` を `answered` にする。
   `by` は Claude なら `claude`、Codex なら `codex`。
   **人間の `turns` と `label` は書き換えない。**
   書き込む直前にファイルを読み直し、自分のターンだけ足す。

   **コメントに書かれていないことはしない。** 気づいた点は直さず、返答で述べる。

9. `thread.json` の変更は監視で自動反映される。エージェントの返答を見るのにリロードは要らない。
   `report.json` の変更も監視され、対象セッションのブラウザが自動でリロードする。
   差分が変わった場合は手順5に戻り、再生成後はそのまま手順7で待ち直す。

10. ユーザーがレビュー終了を宣言しても、マシンで共有するサーバは止めない。
    未判断のグループや未解決コメントが残っている場合は、何を残したまま進めたかを記録する。
    コミットするならメッセージの trailer に入れる。

## 記録すること

レビュー中にエディタへ切り替えた回数と理由を控える。

- 理由文があれば足りたもの → `grouping-prompt.md` の不足
- 差分外の情報が原理的に必要だったもの → ツール側の不足

集計するまでは、画面に差分外コンテキストを足さない。
