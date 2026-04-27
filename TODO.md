# TODO / 未対応のセットアップ項目

最終更新: 2026-04-27

このメモは個人用備忘。`.chezmoiignore` でホーム展開対象外にしている。

---

## Mac (本機、現状の dev 機)

### 保留中タスク

- [ ] **mactex の upgrade** — 現在 `20250308`、cask 上の最新は `20260324`。4GB+ の DL になるので時間あるとき `brew upgrade --cask mactex`
- [ ] **mise の version pin** — `~/.config/mise/config.toml` の `pnpm = "latest"` を `pnpm = "10"` に変更（再現性、warning 消し）
- [ ] **mise 古い version の prune** — `mise prune --yes` で `node 22.13.1` `node 24.x` `pnpm 9.x` `pnpm 10.28.x` を整理
- [ ] **PATH 重複の確認** — cmux session 内で `~/.local/bin` `~/.orbstack/bin` `Android SDK` が 2 重に出る（実害なし、優先度低）

### 既知の制約・現状の構成

- **claude-code**: Mac は公式インストーラ `~/.local/bin/claude` 採用、Nix 版は削除済み
- **cmux 内 vs Ghostty 通常**: cmux 内では cmux wrapper が claude を hook、Ghostty 通常起動では公式版が直接動く（健全）
- **`~/.nix-profile/bin`** は cmux session 内では PATH に出ない（cmux が PATH を設定し直す挙動）。通常 Ghostty では正常

---

## 研究サーバ (CentOS 7, socsel-brain-002)

### 保留中タスク
- 特になし（Phase 1 完了状態）

### 監視事項
- `claude-code` は `pkgs-unstable.claude-code` で追従。**月次更新推奨**:
  ```bash
  cd ~/dotfiles/nix
  nix flake update nixpkgs-unstable
  cd .. && chezmoi apply
  ```
- `flake.lock` は Mac 側で生成・commit 済み。サーバでも `git pull` すれば同一バージョンで pin 可（現状: サーバは独自 lock の可能性、要確認）

---

## Phase 進行状況

| Phase | 状態 | 内容 |
|---|---|---|
| Phase 0 | ✅ | Brewfile 化、Mac 環境 dotfile 化 |
| Phase 1 | ✅ | 研究サーバに Nix + Home Manager 導入、Claude Code 導入 |
| Phase 2a | ✅ | Mac に Nix + Home Manager 導入、brew formula 全 Nix 化 |
| **Phase 2b** | 🟡 未着手 | nix-darwin 導入、macOS システム設定の宣言化、Cask の宣言的管理 |
| Phase 2c | ⬜ Phase 2b 後 | `Brewfile` 廃止 (nix-darwin の `homebrew.casks/brews` に統合) |

---

## 細かい follow-up（気が向いたら）

- [ ] **claude-code 月次更新の自動化**: `/schedule` で recurring task 化検討
- [ ] **nvim diffview の LazyVim extras 化**: 現状 `dot_config/nvim/lua/plugins/diff.lua` で手書き。`lazyvim.json` に `lazyvim.plugins.extras.editor.diffview` を入れる方が idiomatic
- [ ] **Brewfile.mobile の Nix 化**: `cocoapods` / `ruby-build` / `watchman` / `zulu@17`。Phase 2b の nix-darwin 統合タイミングで処理
- [ ] **`flake.lock` の運用確定**: Mac/サーバ で同期するか、各マシン独立にするか方針決定

---

## 既に完了した主な項目（備忘）

### Phase 0
- brew インベントリ整理、`Brewfile` / `Brewfile.mobile` 分離
- 不要 brew (gawk, just, nginx, ssh-copy-id, copilot-cli, poppler, sentencepiece, gnupg, unbound) を削除
- ディスク約 41GB 解放（mobile キャッシュ含む）
- chezmoi で Brewfile / nvim 設定 / Claude Code 設定 / Karabiner / Raycast を管理化

### Phase 1
- 研究サーバ (`/mnt/data1/$USER/nix` bind mount → `/nix`) に Nix single-user 導入
- `home-manager` で zsh / starship / git / fzf / rg / fd / jq / neovim / chezmoi / claude-code / mise (programs.mise) / direnv 設定
- `~/.bash_profile` で SSH ログイン時に Nix の zsh に自動切替
- Ghostty `xterm-ghostty` terminfo をサーバに転送
- chezmoi で `~/.config/nvim/` `~/.claude/` を server にも展開
- Claude Code (Pro/Max サブスク) device flow login

### Phase 2a
- Mac に Nix (Determinate Installer multi-user) 導入
- `flake.nix` に `mac` プロファイル追加 (aarch64-darwin)
- brew formula を全 Nix 化（im-select は `pkgs-unstable.macism` で代替）
- `dot_zshrc.tmpl` / `dot_gitconfig` を chezmoi から削除（home-manager 管理に移行）
- `Brewfile` を Cask のみに純化
- bootstrap scripts (`.chezmoiscripts/`) で新 Mac 1 コマンド構築可能化

### その他改善
- `claude-code` を OS で分岐（Mac は公式、Linux は Nix）
- `neovim` を `pkgs-unstable` に（LazyVim 0.11.2+ 要件）
- `statusline.sh` の UTF-8 progress bar 修正（`tr` → bash loop）
- nvim plugin 再編成: `claude.lua` → `ime.lua` + `diff.lua`（toggleterm 削除）
- `chezmoi.toml` から `[data.git]` 廃止、`dot_gitconfig` 直書き
- `claude-code` の unfree allowlist 設定
