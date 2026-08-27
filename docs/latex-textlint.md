# LaTeX 執筆環境 + textlint（VSCode / CLI）

日本語 LaTeX の「編集 → コンパイル → プレビュー」と、textlint による文章校正の設定。
編集は VSCode（LaTeX Workshop）、CLI からは `latexmk` を直接叩く。

> このファイルは `.chezmoiignore` で除外しており、`~` には展開されない（リポジトリ内部の手順書）。

## 全体像

- **VSCode のビルドは各プロジェクトの `.vscode/settings.json`** に定義した LaTeX Workshop の
  recipe が担当する。LaTeX Workshop は `latexmk -norc` で呼ぶため `~/.latexmkrc` を読まない。
- **CLI の `latexmk` は `~/.latexmkrc`（= `dot_latexmkrc`）** の tool 定義
  （uplatex/dvipdfmx/biber/upmendex）を使う。VSCode の recipe を移植したもので、
  両者が同じビルド結果になるよう揃えてある。
- **PDF プレビューは VSCode 内蔵タブ**。CLI ビルドの確認には
  [Skim](https://skim-app.sourceforge.io/)（ファイル変更で自動リロード）を使える。
- **textlint はプロジェクトローカル**（`.textlintrc` + `node_modules`）を VSCode 拡張が
  自動検出して使う。グローバル install はしていない。

## 構成ファイル一覧

| 役割 | ファイル（chezmoi ソース） | 展開先 |
|---|---|---|
| CLI 用ビルド定義 | `dot_latexmkrc` | `~/.latexmkrc` |
| VSCode のビルド recipe | 各プロジェクトの `.vscode/settings.json`（`-norc` で独立） | — |
| Skim（任意） | `brew install --cask skim` + `SKAutoReloadFileUpdate=YES` | — |

## ビルドの仕組み（要点）

```
.tex 編集
  ↓ latexmk（uplatex → DVI → dvipdfmx）  ← CLI は ~/.latexmkrc、VSCode は settings.json の recipe
.pdf 再生成
  ↓ VSCode 内蔵ビュワー（CLI 経由なら Skim が自動リロード）
最新 PDF 表示（+ SyncTeX 前方検索）
```

- `~/.latexmkrc` は **グローバル**（uplatex 前提）。別エンジン（pdflatex 等）の
  プロジェクトでは、そのディレクトリに `./.latexmkrc` を置けば上書きできる
  （latexmk は user rc → project rc の順に読む）。

## 新しい LaTeX プロジェクトを用意する

1. CLI から `latexmk` を叩くだけなら、uplatex 系は **何もしなくてよい**
   （`~/.latexmkrc` がグローバルに効く）。pdflatex 等を使うなら
   そのプロジェクト直下に `./.latexmkrc` を置いて上書き。
2. VSCode で編集するなら `.vscode/settings.json` に LaTeX Workshop の recipe を用意する
   （`ai-research-workspace` のものを流用するのが早い）。

## textlint を新しいプロジェクトに入れる

各プロジェクトに textlint をローカル install するだけでよい（グローバル install 不要）。

```sh
cd <project>
npm init -y   # まだ package.json が無ければ
npm i -D \
  textlint \
  textlint-plugin-latex2e \
  textlint-rule-preset-ja-technical-writing \
  textlint-rule-preset-ja-spacing \
  textlint-rule-prh
```

`.textlintrc`（`node_modules` と同じ階層に置く）の例 —
`ai-research-workspace/paper/.textlintrc` を流用するのが早い:

```json
{
  "plugins": ["latex2e"],
  "rules": {
    "preset-ja-technical-writing": {
      "ja-no-mixed-period": { "periodMark": "．" },
      "ja-no-mixed-comma": { "commaMark": "，" },
      "no-mix-dearu-desumasu": { "preferInBody": "である", "strict": true }
    },
    "preset-ja-spacing": { "ja-space-between-half-and-full-width": "always" },
    "prh": { "rulePaths": ["./prh.yml"] }
  }
}
```

- `prh` ルールを使うなら `.textlintrc` と同階層に `prh.yml`（用語ゆれ辞書）も用意。
- VSCode 側は textlint 拡張が `.textlintrc` を検出して校正する。
  `.textlintrc` が無いプロジェクトでは何も走らない。
- CLI では `npx textlint <file>` / `npx textlint --fix <file>`。

## 補足

- **Skim 自動リロード** は `defaults write net.sourceforge.skim-app.skim SKAutoReloadFileUpdate -bool YES` で有効化済み。
- chezmoi ソース（`dot_latexmkrc`）を直したら `chezmoi apply`。
