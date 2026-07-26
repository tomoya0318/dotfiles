---
name: commit
description: Creates a commit whose message carries the full plan text, so the history records why the change was made and not just what changed.
disable-model-invocation: true
argument-hint: /commit
---

# コミットする

ユーザーがコミットを求めていない場合は実行しない。

## 主題

`git status` と `git diff` を確認する。

**主題の形式は `git log` の直近を見て、そのリポジトリの慣習に合わせる。**
慣習が読み取れないときだけ `<type>: <日本語の主題>` とし、
type は `feat`、`fix`、`docs`、`style`、`refactor` のいずれかにする。
主題は簡潔にする。

## 本文に plan を全文入れる

作業ディレクトリ `tmp/NNNN_<name>/plan.md` があれば、**全文をコミット本文に入れる**。
要約しない。節を落とさない。

plan が複数ある、またはどれが対象か曖昧なときはユーザーに確認する。
plan が無ければ、なぜその変更をしたかを数行書く。主題だけで済ませない。

コード側で plan と食い違う箇所があれば、コミット前にユーザーへ伝える。
plan を後から書き換えて辻褄を合わせない。

## レビューの積み残し

`review/thread.json` があり、未判断のグループか未解決コメントが残っていれば、
本文の末尾に trailer として記録する。

```
Review-pending: g2, g4 / 未解決コメント 3
```

残っていても止めない。何を残したまま進めたかを後から `git log --grep` で引けるようにする。

## 実行

対話的なエディタを起動しない。
本文が複数行になるので `-m` ではなく `-F` を使う。

```
git add .
git commit -F <一時ファイル>
```

一時ファイルは作業ディレクトリの下に置き、コミット後に消す。
