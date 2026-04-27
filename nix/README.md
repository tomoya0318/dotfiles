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
| `teardown-server.sh` | 研究サーバ上の環境を完全に撤去する shell スクリプト |
| `../.chezmoiscripts/` | Mac 自動セットアップ用の chezmoi スクリプト (Homebrew/Nix install, home-manager switch, brew bundle) |

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

CentOS 7 等の研究用共有サーバに Nix + Home Manager を導入する手順。sudo 権限が必要。
Mac と違い、bind mount や sudo 対話が絡むため自動化していない (半手動)。

### 1. `/nix` の bind mount を用意

Nix store の実体をホームディレクトリ配下に置き、`/nix` に bind mount する:

```bash
mkdir -p /mnt/data1/$USER/nix
chmod 700 /mnt/data1/$USER/nix
sudo mkdir /nix
sudo mount --bind /mnt/data1/$USER/nix /nix

# 再起動時に自動 mount されるよう fstab に追記
echo "/mnt/data1/$USER/nix /nix none bind,nofail 0 0" | sudo tee -a /etc/fstab
sudo mount -a   # syntax 検証
```

### 2. Nix を single-user モードでインストール

```bash
sh <(curl -L https://nixos.org/nix/install) --no-daemon
. ~/.nix-profile/etc/profile.d/nix.sh
```

### 3. flakes を有効化

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

### 4. 最新 git を Nix 経由で導入

CentOS 7 標準の git (1.8.x) は古く、Nix flakes の内部処理で使う `git -C` 等に未対応のため、Nix 経由で新しい git を用意する:

```bash
nix profile install nixpkgs#git
hash -r
git --version   # 2.x が出れば OK
```

### 5. dotfiles を clone して home-manager 初回適用

```bash
git clone https://github.com/tomoya0318/dotfiles.git ~/dotfiles
cd ~/dotfiles/nix
nix run home-manager/release-24.11 -- switch --flake .#research -b bak
```

`-b bak` は既存 `~/.zshrc` 等と衝突した場合に `.bak` サフィックス付きで退避するオプション。

### 6. ステップ 4 で入れた git を除去

home-manager が `home-common.nix` で git を入れるため、ステップ 4 でユーザプロファイルに直接入れた git と衝突する。`nix profile install` で入れた版を外す:

```bash
nix profile remove git
```

### 7. `~/.bash_profile` にシェル自動切替を追記

SSH ログイン時に bash → Nix の zsh に自動で切り替える:

```bash
cat >> ~/.bash_profile <<'EOF'

# --- Nix + home-manager auto-switch ---
[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"
[ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ] && . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
if [ -x "$HOME/.nix-profile/bin/zsh" ] && [ -z "$ZSH_VERSION" ]; then
    exec "$HOME/.nix-profile/bin/zsh" -l
fi
# --- end Nix + home-manager auto-switch ---
EOF
```

`exec` が失敗しても (zsh バイナリ破損等) bash で起動を継続するよう存在チェックを入れている。

### 8. (Ghostty 利用時) terminfo をサーバに転送

Mac の Ghostty は `TERM=xterm-ghostty` を送出する。CentOS 7 には `xterm-ghostty` の terminfo が無いため、zsh の行入力が崩れる (文字化け・Delete 効かない等)。

**Mac 側**で以下を実行:

```bash
infocmp -x | ssh <host> -- tic -x -
```

これでサーバの `~/.terminfo/x/xterm-ghostty` にコンパイル済み terminfo が配置される。SSH 再接続後から効く。

### 9. chezmoi で追加 dotfiles を展開 (nvim / Claude Code 設定)

home-manager は `home-common.nix` に宣言されたものしか配置しない。書き換えが発生する設定 (LazyVim の `lazy-lock.json`、Claude Code の `settings.json` 等) は chezmoi 側で管理しているため、`chezmoi apply` で展開する:

```bash
# chezmoi の source directory を ~/dotfiles に向ける
mkdir -p ~/.local/share
ln -s ~/dotfiles ~/.local/share/chezmoi

# 展開プレビュー (何が展開されるか事前確認)
chezmoi diff

# 問題なければ展開
chezmoi apply
```

展開対象 (Linux 環境):
- `~/.config/nvim/` (LazyVim 設定)
- `~/.claude/` (Claude Code の設定・hooks・skills)

`.zshrc` / `.gitconfig` は `.chezmoiignore` の Linux 向け除外で展開されない (home-manager が生成)。
`.chezmoiscripts/` の Mac 用 bootstrap スクリプトは `{{ if eq .chezmoi.os "darwin" }}` で本体が守られているため、Linux 上では no-op になる。

### 10. Claude Code にログイン (サブスクの場合)

```bash
claude login
```

Device Flow 方式なので、ターミナルに URL + コードが表示される:
1. 表示された URL を Mac のブラウザで開く
2. コードを入力して認証
3. ターミナルに戻り、認証完了を確認

認証情報は `~/.claude/.credentials.json` (mode 0600) に保存される。共有サーバでは sudo を持つ他メンバーから読める可能性があることは認識しておく。

### 研究サーバ teardown

以下で Nix + Home Manager 環境を全撤去できる:

```bash
bash ~/dotfiles/nix/teardown-server.sh
```

撤去内容・対象は `teardown-server.sh` 冒頭の確認プロンプトに表示される。`~/.zshrc.bak` などのバックアップは残るので、必要なら手動で元の dotfiles に戻せる。
