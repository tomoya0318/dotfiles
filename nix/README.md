# nix/

Mac と Linux 環境を Nix + Home Manager で宣言的に管理する flake。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `flake.nix` | エントリポイント。`homeConfigurations.research` (Linux) と `mac` を定義 |
| `home-common.nix` | 両 OS 共通設定 (packages, programs.zsh/starship/fzf/git)。`home.homeDirectory` は `stdenv.isDarwin` で OS 分岐 |
| `home-mac.nix` | Mac 固有設定 (brew 移行 CLI, macism, RN/Android env, OrbStack 等) |
| `home-research.nix` | Linux/研究サーバ固有 (claude-code 等、Mac は公式インストーラ採用のため対象外) |
| `flake.lock` | 入力パッケージのバージョンを pin (nixpkgs 24.11, unstable, home-manager) |
| `teardown-server.sh` | 研究サーバから Nix + Home Manager を段階的に撤去する shell スクリプト (multi-user 対応) |
| `../.chezmoiscripts/` | Mac/Linux 両対応の chezmoi セットアップスクリプト (Homebrew install, Nix install/verify, home-manager switch, brew bundle) |

---

## Mac セットアップ (新規マシン)

**1 コマンド bootstrap**:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply tomoya0318
```

これで以下が順次自動実行される:

1. chezmoi バイナリ取得
2. dotfiles repo を `~/.local/share/chezmoi` に clone
3. `.chezmoiscripts/run_once_before_10_install-brew.sh` — Homebrew 未導入なら install
4. `.chezmoiscripts/run_once_before_20_install-nix.sh` — Nix (Determinate Installer) install + flakes 有効化
5. chezmoi apply で dotfiles を deploy (nvim LazyVim 設定, `~/.claude/`, `~/Brewfile`, 等)
6. `.chezmoiscripts/run_onchange_after_30_apply-home-manager.sh` — `home-manager switch --flake .#mac` で zsh/starship/git/各種 CLI を Nix 管理下に
7. `.chezmoiscripts/run_onchange_after_40_brew-bundle.sh` — `brew bundle` で Cask GUI アプリ (ghostty, orbstack, warp, karabiner, codeql, ngrok, mactex) を install

完了後、**新しい Terminal を開けば** Nix 経由の CLI が利用可能。

### bootstrap 後のオプション

**Claude Code セットアップ** (Mac は公式インストーラ採用):

```bash
# Anthropic 公式インストーラで ~/.local/bin/claude に install
curl -fsSL https://claude.ai/install.sh | bash

# サブスクログイン
claude login
```

> Mac で Nix 経由 (`pkgs-unstable.claude-code`) を使わない理由:
> 公式版が常に最新 (unstable lock より早い)、cmux.app 等の他ツールとの統合
> もスムーズなため。研究サーバ (Linux) のほうは Nix 管理 (`home-research.nix`)。

**RN / iOS / Android 開発する場合**:
```bash
brew bundle --file=~/Brewfile.mobile
~/scripts/setup-mobile.sh
```

### 既存 Mac での継続運用

flake (`home-mac.nix`, `flake.lock` 等) や Brewfile を編集した後:

```bash
cd ~/.local/share/chezmoi
chezmoi update   # git pull + apply + run_onchange を自動再実行
```

内部で `home-manager switch` や `brew bundle` が再発火する (`.chezmoiscripts/run_onchange_*` の include hash が変化するため)。

### `claude-code` の更新

unstable 追従のため `flake.lock` を明示的に bump する:

```bash
cd ~/.local/share/chezmoi/nix
nix flake update nixpkgs-unstable
cd ..
chezmoi apply   # home-manager switch で新版 claude-code が入る
```

### Mac 側 teardown (手動)

Mac 側に一括 teardown スクリプトは未用意 (需要が出たら追加)。手動では:

```bash
# Nix 撤去 (Determinate Installer が uninstall コマンドを提供)
/nix/nix-installer uninstall

# chezmoi が展開した dotfiles 削除
chezmoi purge

# brew/Cask は手動で必要なものだけ
```

---

## 研究サーバ セットアップ (新規サーバ)

multi-user mode で Nix を導入し、共有サーバで複数ユーザが安全に使える状態にする。
`/nix/store` は全ユーザで共有・重複排除され、各ユーザは自身の `~/.nix-profile` を持つ。

**前提**:
- 管理者 (root 権限保持者) が手順 1〜4 を 1 度だけ実行する (システム全体の整備)
- 各ユーザは手順 5 以降を自身で実行する (ユーザ毎の dotfiles bootstrap)

### 1. (該当する場合) 旧 single-user / bind mount を解除 (root)

過去に single-user mode で `/nix` を運用していた場合は事前に片付ける:

```bash
# /nix を握っているプロセスがいないことを確認 (空ならクリア)
sudo ls -la /proc/*/exe 2>/dev/null | grep -E '/nix/store|tomoya-n/nix'
sudo ls -la /proc/*/cwd 2>/dev/null | grep -E '/nix/store|tomoya-n/nix'

# bind mount 解除と /etc/fstab 整理
sudo umount /nix 2>/dev/null
sudo rmdir /nix 2>/dev/null
sudo sed -i.bak '/\/nix none bind/d' /etc/fstab
```

旧 store の実体 (`~/nix` など) はロールバック用にしばらく残し、移行確認後に削除。

### 2. multi-user Nix を install (root)

```bash
# RHEL/CentOS 系で SELinux が Enforcing なら一時的に permissive へ
getenforce   # Enforcing なら次行を実行
sudo setenforce 0

# 公式 multi-user installer
sh <(curl -L https://nixos.org/nix/install) --daemon
```

installer が以下を作成:
- `/nix/` (root:root, 755) と `/nix/store/` (root:nixbld, 1775)
- `nixbld1..32` ユーザと `nixbld` グループ (gid 30000) — ビルドサンドボックス用
- `nix-daemon.service` / `.socket` (systemd unit、enable 済み)
- `/etc/profile.d/nix.sh` (全ユーザの PATH に nix を追加)
- `/etc/bashrc` を編集 (`/etc/bashrc.backup-before-nix` にバックアップ)

完了後、Enforcing に戻して動作確認:

```bash
sudo setenforce 1
sudo systemctl restart nix-daemon
sudo systemctl status nix-daemon                    # active (running) を確認
sudo ausearch -m AVC -ts recent | grep nix          # AVC denied が無いこと
```

AVC denied が出る場合は `audit2allow` で個別ポリシー作成、または運用上は permissive のまま。

### 3. `/etc/nix/nix.conf` を調整 (root)

```bash
sudo tee /etc/nix/nix.conf <<'EOF'
build-users-group = nixbld
experimental-features = nix-command flakes
allowed-users = root @nix
trusted-users = root tomoya-n
auto-optimise-store = true
# RHEL/CentOS 系では nix-daemon が CA bundle を見つけられないため明示する
ssl-cert-file = /etc/pki/tls/certs/ca-bundle.crt
EOF

sudo systemctl restart nix-daemon
```

各ディレクティブの意味:

| 設定 | 役割 |
|---|---|
| `build-users-group = nixbld` | ビルドサンドボックス用 UID プール (installer 既定) |
| `experimental-features = nix-command flakes` | `nix` 新 CLI と flake を有効化 |
| `allowed-users = root @nix` | nix-daemon に接続できるユーザ (Docker socket と同じ pattern) |
| `trusted-users = root tomoya-n` | 設定上書き等の特権を持つ管理者 |
| `auto-optimise-store = true` | 同一ファイルを hardlink で重複排除 |
| `ssl-cert-file` | substituter ダウンロード時の CA bundle (RHEL 系のみ必要、Ubuntu/Debian は省略可) |

### 4. `nix` グループ作成とユーザ追加 (root)

Docker と同じパターンで、`nix` グループに入っているユーザだけが Nix を使える運用にする:

```bash
sudo groupadd nix
sudo usermod -aG nix tomoya-n      # 各 Nix 利用ユーザ毎に実行
sudo systemctl restart nix-daemon
```

ユーザは **再ログインで group が反映** される。確認:

```bash
id                  # 出力に "nix" が含まれていること
nix --version
nix store ping
```

### 5. dotfiles bootstrap (各ユーザ)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply tomoya0318
```

これで以下が順次自動実行される:

1. chezmoi バイナリ取得
2. dotfiles repo を `~/.local/share/chezmoi` に clone
3. `.chezmoiscripts/run_once_before_20_install-nix.sh` — nix が利用可能か検証 (install 自体は手順 2 で完了済み)
4. chezmoi apply で `~/.config/nvim`, `~/.claude` 等の dotfiles を deploy
5. `.chezmoiscripts/run_onchange_after_30_apply-home-manager.sh` — `home-manager switch --flake .#research` で zsh/starship/git/各種 CLI を Nix 管理下に

`.zshrc` / `.gitconfig` は `.chezmoiignore` の Linux 向け除外で展開されない (home-manager が生成)。
Mac 用の `Brewfile`・`raycast_scripts/` 等も同様に除外。

### 6. (Ghostty 利用時) terminfo をサーバに転送

Mac の Ghostty は `TERM=xterm-ghostty` を送出する。RHEL 系には `xterm-ghostty` の terminfo が無いため、zsh の行入力が崩れる (文字化け・Delete 効かない等)。

**Mac 側**で実行:

```bash
infocmp -x | ssh <host> -- tic -x -
```

これでサーバの `~/.terminfo/x/xterm-ghostty` に配置される。SSH 再接続後から効く。

### 7. Claude Code にログイン

```bash
claude login
```

Device Flow 方式。ターミナルに表示された URL を Mac のブラウザで開いてコード入力。
認証情報は `~/.claude/.credentials.json` (mode 0600) に保存される。共有サーバでは sudo を持つ他メンバーから読める可能性があることは認識しておく。

### 既存サーバでの継続運用

`flake.lock`、`home-research.nix` 等を編集した後:

```bash
chezmoi update      # git pull + apply + run_onchange を自動再実行
```

内部で `home-manager switch --flake .#research` が再発火する (`.chezmoiscripts/run_onchange_*` の hash が変化するため)。

### 他ユーザのオンボード

新メンバーを追加する場合:

```bash
# 管理者 (root)
sudo usermod -aG nix <new-user>
sudo systemctl restart nix-daemon

# 新メンバー (再ログイン後、自身の dotfiles repo で)
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <github-user>
```

`flake.nix` は **ユーザ毎に独立**。各自が自分の dotfiles repo で自分用の構成を持つ。`/nix/store` は drv ハッシュベースで自動的に重複排除されるため、共有 flake である必要はない。

### 研究サーバ teardown

```bash
bash ~/.local/share/chezmoi/nix/teardown-server.sh
```

2 段階で確認しながら撤去する:
- **Phase A** (ユーザレベル): 自分の home-manager 状態だけ削除。共有サーバで他ユーザに影響しない
- **Phase B** (システムレベル): multi-user Nix そのものを撤去。他ユーザがいる場合は禁止
