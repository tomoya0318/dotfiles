<!-- SEMBLE_START -->
## Semble Code Search

`mcp__semble__search`（自然言語・コードクエリでの検索）と `mcp__semble__find_related`（指定ファイル・行に似たコードの検索）が常駐ツールとして使える。

コード内で「どこに実装されているか」を探すときは、Grep や Glob でファイルを探し回る前に `mcp__semble__search` を使う。返ってきた file と line に直接移動して読み、同じ内容を grep し直さない。Grep はリポジトリ全体でリテラル文字列の全出現が必要なとき（リネームした関数の全呼び出し元など）に限る。

`content` は `docs`（ドキュメント・散文）、`config`（設定ファイル）、`all`（コード＋ドキュメント＋設定）を指定できる。ローカルプロジェクトでは `repo` にプロジェクトルートを渡す。
<!-- SEMBLE_END -->
