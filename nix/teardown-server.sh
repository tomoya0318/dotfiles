#!/usr/bin/env bash
set -euo pipefail

# 研究サーバ上の Nix + Home Manager 環境を完全に撤去する
# 使い方: bash ~/dotfiles/nix/teardown-server.sh

cat <<EOF
以下を順番に実行します:
  1. ~/.bash_profile の exec zsh ブロックを削除
  2. home-manager generations を expire
  3. ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.local/state/nix ~/.config/nix を削除
  4. /nix の bind mount を解除 (sudo)
  5. /etc/fstab から /nix 行を削除 (sudo)
  6. /mnt/data1/<user>/nix (Nix store 実体) を削除
  7. ~/.local/share/chezmoi symlink を削除 (存在すれば)

残るもの:
  - ~/.terminfo (Ghostty 用等)
  - ~/dotfiles (手動で削除してください)
  - ~/.zshrc.bak などバックアップファイル群
  - ~/.config/nvim ~/.claude など chezmoi apply で展開したファイル群

EOF
read -r -p "続行しますか？ [yes/N] " yn
[[ "$yn" == "yes" ]] || { echo "中止"; exit 0; }

# --- 1. .bash_profile から exec zsh ブロック除去 ---
if [ -f ~/.bash_profile ]; then
    # 終了マーカーがあればそれで挟む。無ければ最初の fi まで。
    if grep -q "# --- end Nix + home-manager auto-switch ---" ~/.bash_profile; then
        sed -i '/# --- Nix + home-manager auto-switch ---/,/# --- end Nix + home-manager auto-switch ---/d' ~/.bash_profile
    elif grep -q "# --- Nix + home-manager auto-switch ---" ~/.bash_profile; then
        sed -i '/# --- Nix + home-manager auto-switch ---/,/^fi$/d' ~/.bash_profile
    fi
    echo "✓ .bash_profile の auto-switch ブロックを削除"
fi

# --- 2. home-manager generations 削除 ---
if [ -x "$HOME/.nix-profile/bin/home-manager" ]; then
    nix run home-manager/release-24.11 -- expire-generations "-1 seconds" 2>/dev/null || true
    echo "✓ home-manager generations を expire"
fi

# --- 3. Nix 関連ユーザディレクトリ削除 ---
rm -rf ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.local/state/nix ~/.config/nix
echo "✓ ~/.nix-* と ~/.config/nix を削除"

# --- 4. /nix の umount と rmdir (sudo) ---
if mount | grep -q "on /nix "; then
    sudo umount /nix && echo "✓ /nix を umount"
fi
if [ -d /nix ] && [ -z "$(ls -A /nix 2>/dev/null)" ]; then
    sudo rmdir /nix && echo "✓ /nix (空ディレクトリ) を削除"
fi

# --- 5. /etc/fstab から bind mount 行を削除 ---
if grep -qE "^/mnt/data1/.*/nix /nix " /etc/fstab; then
    sudo sed -i '\|^/mnt/data1/.*/nix /nix |d' /etc/fstab
    echo "✓ /etc/fstab から bind mount 行を削除"
fi

# --- 6. Nix store 実体を削除 ---
NIX_STORE_REAL="/mnt/data1/$(whoami)/nix"
if [ -d "$NIX_STORE_REAL" ]; then
    rm -rf "$NIX_STORE_REAL"
    echo "✓ $NIX_STORE_REAL を削除"
fi

# --- 7. chezmoi source symlink を削除 ---
if [ -L "$HOME/.local/share/chezmoi" ]; then
    rm "$HOME/.local/share/chezmoi"
    echo "✓ chezmoi source symlink を削除"
fi

cat <<EOF

=== 完了 ===

必要なら以下を手動で復元/削除してください:
  mv ~/.zshrc.bak ~/.zshrc                    (バックアップ復元)
  mv ~/.bash_profile.bak ~/.bash_profile      (バックアップ復元)
  rm -rf ~/dotfiles                            (dotfiles リポを削除)
  rm -rf ~/.config/nvim ~/.claude              (chezmoi 展開ファイルを削除)
EOF
