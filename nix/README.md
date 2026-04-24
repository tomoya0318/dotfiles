# nix/

Mac と Linux 環境を Nix + Home Manager で宣言的に管理する flake。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `flake.nix` | エントリポイント。`homeConfigurations.research` を定義 |
| `home-common.nix` | 両 OS 共通設定 (packages, programs.zsh/starship/fzf/git)。`home.homeDirectory` は `stdenv.isDarwin` で OS 分岐 |
| `teardown-server.sh` | 研究サーバ上の環境を完全に撤去する shell スクリプト |

## 研究サーバ 初回セットアップ手順

新しい研究サーバに Nix + Home Manager を導入する流れ。サーバ側 sudo 権限が必要。

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

`exec` が失敗しても (zsh バイナリが破損等) bash で起動を継続するよう存在チェックを入れている。

### 8. (Ghostty 利用時) terminfo をサーバに転送

Mac の Ghostty は `TERM=xterm-ghostty` を送出する。CentOS 7 には `xterm-ghostty` の terminfo が無いため、zsh の行入力が崩れる (文字化け・Delete 効かない等)。

**Mac 側**で以下を実行:

```bash
infocmp -x | ssh <host> -- tic -x -
```

これでサーバの `~/.terminfo/x/xterm-ghostty` にコンパイル済み terminfo が配置される。SSH 再接続後から効く。

---

## 環境完全初期化 (teardown)

以下で Nix + Home Manager 環境を全撤去できる:

```bash
bash ~/dotfiles/nix/teardown-server.sh
```

撤去内容・対象は `teardown-server.sh` 冒頭の確認プロンプトに表示される。`~/.zshrc.bak` などのバックアップは残るので、必要なら手動で元の dotfiles に戻せる。

---

## Mac 側 (将来対応)

現在は研究サーバ用プロファイル (`research`) のみ。Mac 用を追加する場合:

1. `home-mac.nix` を新設 (Mac 固有の設定を記述)
2. `flake.nix` のコメントアウトされた `"mac"` プロファイルを有効化
3. Mac 側で `nix run home-manager/release-24.11 -- switch --flake ~/.local/share/chezmoi/nix#mac`
