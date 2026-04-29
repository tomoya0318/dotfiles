#!/usr/bin/env bash
set -euo pipefail

# 研究サーバの multi-user Nix + Home Manager 環境を撤去する
# 使い方: bash ~/.local/share/chezmoi/nix/teardown-server.sh
#
# 2 段階で確認しながら実行:
#   Phase A: ユーザレベル (このユーザの home-manager 状態のみ)
#   Phase B: システムレベル (nix-daemon, /nix, nixbld*, nix group を全削除)
#
# 共有サーバで他ユーザが Nix を使っている場合は Phase B をスキップしてください。

USER_NAME=$(whoami)

cat <<EOF
=== Nix teardown (multi-user mode) ===

[Phase A] ユーザレベル
  1. home-manager generations を expire
  2. nix store の自分の roots を GC
  3. ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.local/state/nix ~/.config/nix を削除
  4. /nix/var/nix/{profiles,gcroots}/per-user/${USER_NAME}/ を削除 (sudo)
  5. ~/.local/share/chezmoi symlink を削除 (存在すれば)

[Phase B] システムレベル (sudo 必要、共有サーバでは慎重に)
  6. nix-daemon.service / .socket を停止・disable
  7. /etc/systemd/system/nix-daemon.* を削除
  8. /etc/bashrc を installer 前の状態に復元
  9. /etc/profile.d/nix.sh を削除
  10. /etc/nix/ を削除
  11. /nix/ を削除 (時間がかかる場合あり)
  12. nixbld1..32 ユーザと nixbld グループを削除
  13. nix グループを削除

残るもの (必要に応じて手動で削除):
  - ~/.terminfo (Ghostty 用 terminfo)
  - ~/.config/nvim ~/.claude (chezmoi apply で展開)
  - dotfiles repo (~/dotfiles 等)
  - 旧 single-user 移行時のバックアップ (~/.zshrc.old-nix 等、存在する場合)

EOF

read -r -p "Phase A (ユーザレベル撤去) を実行しますか？ [yes/N] " ans_a
[[ "$ans_a" == "yes" ]] || { echo "中止"; exit 0; }

# === Phase A ===

# 1. home-manager generations expire
if command -v nix >/dev/null 2>&1; then
    nix run home-manager/release-24.11 -- expire-generations "-1 seconds" 2>/dev/null || true
    echo "✓ home-manager generations を expire"
fi

# 2. ユーザ side の GC
if command -v nix-collect-garbage >/dev/null 2>&1; then
    nix-collect-garbage -d 2>/dev/null || true
    echo "✓ nix store の自分の roots を GC"
fi

# 3. ユーザディレクトリ削除
rm -rf "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.nix-channels" \
       "$HOME/.local/state/nix" "$HOME/.config/nix"
echo "✓ ~/.nix-* と ~/.config/nix を削除"

# 4. システム側 per-user state (root 所有)
sudo rm -rf "/nix/var/nix/profiles/per-user/${USER_NAME}" \
            "/nix/var/nix/gcroots/per-user/${USER_NAME}" 2>/dev/null || true
echo "✓ /nix/var/nix/{profiles,gcroots}/per-user/${USER_NAME}/ を削除"

# 5. chezmoi source symlink
if [ -L "$HOME/.local/share/chezmoi" ]; then
    rm "$HOME/.local/share/chezmoi"
    echo "✓ chezmoi source symlink を削除"
fi

echo
echo "=== Phase A 完了 ==="
echo

# === Phase B ===
read -r -p "Phase B (システムレベル撤去) も実行しますか？他ユーザが Nix を使っている場合は中止してください [yes/N] " ans_b

if [[ "$ans_b" != "yes" ]]; then
    cat <<'EOF'

Phase B はスキップ。ユーザレベル撤去のみ完了。

システム全体の Nix を撤去する場合は、再度このスクリプトを実行し
Phase A は no、Phase B のみ yes と回答してください。

EOF
    exit 0
fi

# 6-7. systemd unit 停止・disable・削除
sudo systemctl stop nix-daemon.service nix-daemon.socket 2>/dev/null || true
sudo systemctl disable nix-daemon.service nix-daemon.socket 2>/dev/null || true
sudo rm -f /etc/systemd/system/nix-daemon.service /etc/systemd/system/nix-daemon.socket
sudo systemctl daemon-reload
echo "✓ nix-daemon サービスを停止・disable し、systemd unit を削除"

# 8. /etc/bashrc 復元 (installer がバックアップしたものがあれば)
if [ -f /etc/bashrc.backup-before-nix ]; then
    sudo mv /etc/bashrc.backup-before-nix /etc/bashrc
    echo "✓ /etc/bashrc を installer 前の状態に復元"
fi

# 念のため /etc/zshrc 系も
for f in /etc/zshrc /etc/zsh/zshrc; do
    if [ -f "${f}.backup-before-nix" ]; then
        sudo mv "${f}.backup-before-nix" "$f"
        echo "✓ $f を installer 前の状態に復元"
    fi
done

# 9. /etc/profile.d/nix.sh 削除
sudo rm -f /etc/profile.d/nix.sh
echo "✓ /etc/profile.d/nix.sh を削除"

# 10. /etc/nix 削除
sudo rm -rf /etc/nix
echo "✓ /etc/nix/ を削除"

# 11. /nix 削除 (大きいので時間がかかる)
if [ -d /nix ]; then
    echo "  /nix/ を削除中... (時間がかかる場合あり)"
    sudo rm -rf /nix
    echo "✓ /nix/ を削除"
fi

# 12. nixbld* ユーザ + nixbld グループ削除
for i in $(seq 1 32); do
    sudo userdel "nixbld${i}" 2>/dev/null || true
done
sudo groupdel nixbld 2>/dev/null || true
echo "✓ nixbld1..32 ユーザと nixbld グループを削除"

# 13. nix グループ削除
sudo groupdel nix 2>/dev/null || true
echo "✓ nix グループを削除"

cat <<EOF

=== Phase B 完了 ===

サーバから multi-user Nix を完全に撤去しました。

login shell が ~/.nix-profile/bin/zsh だった場合は dangling になっています。
必要なら戻してください:
  sudo chsh -s /bin/bash ${USER_NAME}

その他、残ったファイルで不要なものは手動で削除:
  rm ~/.zshrc.old-nix ~/.zshenv.old-nix ~/.nix-profile.old ~/.nix-channels.old ~/.nix-defexpr.old 2>/dev/null
  rm -rf ~/.config/nvim ~/.claude
  rm -rf ~/dotfiles

EOF
