# nix/

研究サーバ (Linux/CentOS) 環境を Nix + Home Manager で宣言的に管理する flake。

> **Mac は Nix を使わない。** ローカル Mac の CLI/GUI は Homebrew (`Brewfile`) と
> mise (`~/.config/mise/config.toml`) で管理する。Nix はカーネル/glibc が古い
> 研究サーバでモダンなツールチェインを入れるためだけに使う。Mac とサーバを
> 完全に揃える利点が薄かったため、ローカルは素直に brew/mise に寄せた。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `flake.nix` | エントリポイント。`homeConfigurations.research` (Linux) のみ定義 |
| `home-research.nix` | 研究サーバの全設定 (packages, programs.zsh/starship/fzf/git)。claude-code はシステム共有 profile 管理 (`system-shared-tools.md`) のため除外 |
| `flake.lock` | 入力パッケージのバージョンを pin (nixpkgs 24.11, unstable, home-manager) |
| `system-shared-tools.md` | claude-code 等をシステム共有 profile で管理する手順 |
| `teardown-server.sh` | 研究サーバから Nix + Home Manager を段階的に撤去する shell スクリプト (multi-user 対応) |
| `../.chezmoiscripts/` | セットアップスクリプト (Mac: Homebrew install + brew bundle / Linux: Nix 検証 + home-manager switch) |

---

## Mac セットアップ (新規マシン)

**1 コマンド bootstrap**:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply tomoya0318
```

これで以下が順次自動実行される:

1. chezmoi バイナリ取得
2. dotfiles repo を `~/.local/share/chezmoi` に clone
3. `.chezmoi.toml.tmpl` — ntfy topic (スマホ通知用) を対話入力 (不要なら空 Enter)
4. `.chezmoiscripts/run_once_before_10_install-brew.sh` — Homebrew 未導入なら install
5. chezmoi apply で dotfiles を deploy (`.zshrc`/`.zshenv`、git/nvim/ghostty/starship/zed/mise 設定、`~/.claude/` 等)
6. `.chezmoiscripts/run_onchange_after_40_brew-bundle.sh` — `brew bundle` で CLI ツール (git, neovim, mise, ripgrep, …) と Cask (cmux, obsidian, orbstack, karabiner, mactex 等) を install

> `run_once_before_20_install-nix` と `run_onchange_after_30_apply-home-manager`
> は Linux 専用 (テンプレートで darwin 時は no-op)。Mac では何もしない。

完了後、**新しい Terminal を開けば** brew/mise 経由の CLI が利用可能。

### bootstrap 後のオプション

**mise でランタイム install** (node/pnpm 等、`~/.config/mise/config.toml` に宣言):

```bash
mise install
```

**Claude Code セットアップ** (Anthropic 公式インストーラ):

```bash
curl -fsSL https://claude.ai/install.sh | bash   # ~/.local/bin/claude に install
claude login                                      # サブスクログイン
```

**RN / iOS / Android 開発する場合** (Brewfile は ~/ に展開しないので source を直接指定):

```bash
brew bundle --file=~/.local/share/chezmoi/Brewfile.mobile
~/.local/share/chezmoi/scripts/setup-mobile.sh
```

### 既存 Mac での継続運用

`Brewfile` や各種設定を編集した後:

```bash
cd ~/.local/share/chezmoi
chezmoi update   # git pull + apply + run_onchange を自動再実行
```

`Brewfile` の内容が変わると `.chezmoiscripts/run_onchange_after_40_brew-bundle.sh`
の include hash が変化して `brew bundle` が再発火する。

未宣言のパッケージを掃除したいとき:

```bash
brew bundle --file=~/.local/share/chezmoi/Brewfile cleanup --force
```

### Mac 側 teardown (手動)

```bash
chezmoi purge    # chezmoi が展開した dotfiles を削除
# brew で入れたものは手動で必要に応じて: brew uninstall <formula/cask>
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

`.zshrc` / `.zshenv` / `.config/git/` は `.chezmoiignore` の Linux 向け除外で展開されない
(home-manager が `home-research.nix` の `programs.zsh`/`git` から生成する)。
Mac 用の `.config/karabiner/`・`raycast_scripts/` も同様に除外。
`Brewfile`・`scripts/` は全 OS で展開対象外 (source 内でのみ使用)。

### 6. (cmux/Ghostty 利用時) terminfo をサーバに転送

Mac の cmux (libghostty ベース) / Ghostty は `TERM=xterm-ghostty` を送出する。RHEL 系には `xterm-ghostty` の terminfo が無いため、zsh の行入力が崩れる (文字化け・Delete 効かない等)。

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
