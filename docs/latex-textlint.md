# LaTeX 執筆環境 + textlint（Zed / Neovim / VSCode 共有）

日本語 LaTeX の「編集 → コンパイル → プレビュー」と、textlint による文章校正を
Zed・Neovim・VSCode の 3 エディタで共有するための設定とその増やし方。

> このファイルは `.chezmoiignore` で除外しており、`~` には展開されない（リポジトリ内部の手順書）。

## 全体像

- **ビルドは `latexmk` に一本化**。tool 定義（uplatex/dvipdfmx/biber/upmendex）は
  `~/.latexmkrc`（= `dot_latexmkrc`）に集約し、3 エディタと CLI が同じビルドを共有する。
- **PDF プレビューは外部 [Skim](https://skim-app.sourceforge.io/)**（ファイル変更で自動リロード）。
  Zed も Neovim も内蔵ビュワーを持たないため外部 Skim を使う（VSCode だけは内蔵タブ）。
- **textlint はプロジェクトローカル**（`.textlintrc` + `node_modules`）を各エディタが
  自動検出して使う。グローバル install はしていない。

## 構成ファイル一覧

| 役割 | ファイル（chezmoi ソース） | 展開先 |
|---|---|---|
| 共有ビルド定義 | `dot_latexmkrc` | `~/.latexmkrc` |
| nvim: LaTeX extra 有効化 | `dot_config/nvim/lua/config/lazy.lua` | `lang.tex` を import |
| nvim: vimtex 上書き（Skim/uplatex） | `dot_config/nvim/lua/plugins/vimtex.lua` | — |
| nvim: textlint 連携 | `dot_config/nvim/lua/plugins/textlint.lua` | — |
| nvim: `.pdf` を Skim へ受け流す | `dot_config/nvim/lua/config/autocmds.lua` | — |
| Zed: texlab ビルド/前方検索・拡張自動導入 | `dot_config/zed/private_settings.json` | `~/.config/zed/settings.json` |
| Skim | `brew install --cask skim` + `SKAutoReloadFileUpdate=YES` | — |
| VSCode | 各プロジェクトの `.vscode/settings.json`（`-norc` で独立） | — |

## ビルドの仕組み（要点）

```
.tex 編集
  ↓ latexmk（uplatex → DVI → dvipdfmx）       ← tool 定義は ~/.latexmkrc
.pdf 再生成
  ↓ Skim がファイル変更を検知して自動リロード
最新 PDF 表示（+ SyncTeX 前方検索）
```

- `~/.latexmkrc` は **グローバル**（uplatex 前提）。別エンジン（pdflatex 等）の
  プロジェクトでは、そのディレクトリに `./.latexmkrc` を置けば上書きできる
  （latexmk は user rc → project rc の順に読む）。
- **VSCode は無影響**。LaTeX Workshop が `latexmk -norc` で呼ぶため `~/.latexmkrc` を
  読まず、`.vscode/settings.json` のインライン recipe で独立して動く。

## エディタ別の操作

### Neovim（vimtex）
`.tex` を開くと自動で有効化。localleader は `\`。

| キー | 動作 |
|---|---|
| `\ll` | 継続コンパイル ON/OFF（保存のたび自動ビルド → Skim 自動更新）|
| `\lv` | PDF を Skim で該当行に表示（前方ジャンプ）|
| `\lk` | コンパイル停止 |
| `\lc` | 中間ファイル掃除 |
| `\le` | エラー一覧（quickfix）|
| `\lt` | 目次トグル |

### Zed（texlab）
`.tex` を保存すると latexmk ビルド → Skim が該当箇所を表示。
LaTeX 拡張（texlab 同梱）は `auto_install_extensions` で自動導入。
入らなければ拡張パネルで "LaTeX" を検索して手動インストール。

### VSCode（LaTeX Workshop）
従来どおり。プロジェクトの `.vscode/settings.json` の recipe を使用。

## 新しい LaTeX プロジェクトを用意する

1. uplatex 系なら **何もしなくてよい**（`~/.latexmkrc` がグローバルに効く）。
   pdflatex 等を使うなら、そのプロジェクト直下に `./.latexmkrc` を置いて上書き。
2. nvim / Zed は `.tex` を開けば自動でビルド/プレビューが動く。

## textlint を新しいプロジェクトに入れる

nvim 側は「**`.textlintrc` を上方向に探して、見つかったらそのプロジェクトのローカル
`node_modules/.bin/textlint` で校正**」という作りなので、各プロジェクトに textlint を
ローカル install するだけでよい（グローバル install 不要）。

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
- これで **nvim**（保存/挿入抜けで自動診断・`]d`/`[d` で移動・`:TextlintFix` で自動修正）と
  **Zed / VSCode**（拡張側で校正）が同じルールで動く。
- `.textlintrc` が無いプロジェクトでは nvim の textlint は何も走らない（余計な指摘を出さない）。

## 既知の未設定・補足

- **Skim 逆検索（PDF → エディタ）** は Skim 側の設定が必要（未設定）。Skim の
  Preferences → Sync で Preset=Custom にして nvim/Zed を呼ぶよう設定すれば
  ⌘⇧クリックでソースへ戻れる。前方検索（エディタ → PDF）は設定済み。
- **Skim 自動リロード** は `defaults write net.sourceforge.skim-app.skim SKAutoReloadFileUpdate -bool YES` で有効化済み。
- 設定変更後は各エディタ（nvim/Zed）の**再起動**で反映。chezmoi ソースを直したら `chezmoi apply`。
