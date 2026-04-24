# 常用 Brewfile
# 適用: brew bundle --file=~/Brewfile
# 同期(未宣言を削除): brew bundle --file=~/Brewfile cleanup --force
#
# CLI は基本 Nix (home-mac.nix) で管理中。
# im-select のみ例外で brew 管理 (nixpkgs に代替が無いため)。
# このファイルには他は GUI アプリ (Cask) のみ。
# Phase 2b で nix-darwin 導入後に homebrew 宣言に統合予定。

# --- Formula: Nix で管理不能な Mac CLI ---
tap "daipeihust/tap"
brew "daipeihust/tap/im-select"   # nvim の im-select.nvim が呼ぶ

# --- Cask: ターミナル ---
cask "ghostty"
cask "warp"

# --- Cask: 仮想化/コンテナ ---
cask "orbstack"

# --- Cask: Mac 拡張 ---
cask "karabiner-elements"

# --- Cask: 開発ツール ---
# codeql は将来 project-scope の Nix に移行予定
cask "codeql"
cask "ngrok"

# --- Cask: 文書/組版 ---
cask "mactex"
