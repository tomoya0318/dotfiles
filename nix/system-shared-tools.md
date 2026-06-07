# システム共有ツールの提供 (option)

特定のツール (claude-code 等) をシステム全体の Nix profile に install し、
**サーバにログインできる全ユーザに開放**する手順。

各ユーザに個人 flake を持たせず、`nix` group への追加すら不要で
claude-code を使えるようにしたい場合に使う。

## 想定ユースケース

- 「研究室メンバー全員が claude-code を使える状態にしておきたい」
- 「version は管理者が決める。各自の Anthropic アカウントで認証してもらう」
- 「Nix を本格的に使いたくない人にも使わせたい」

## 仕組み

`/nix/var/nix/profiles/default/` (システム共通 profile) に install すると、
installer が配置した `/etc/profile.d/nix.sh` 経由で全ユーザの PATH に
`/nix/var/nix/profiles/default/bin` が追加される。

claude-code は通常の binary 実行 (nix-daemon 不要) なので、
`nix` group に居ないユーザでも `claude` を叩ける。
認証情報は `~/.claude/.credentials.json` で per-user に分離される。

## 前提

- multi-user Nix インストール完了 (`README.md` の Phase 1〜4)
- 管理者が `trusted-users` に入っていること (`/etc/nix/nix.conf`)
- claude-code は unfree license のため、install / upgrade コマンドには
  `env NIXPKGS_ALLOW_UNFREE=1 ... --impure` を毎回付ける (本 doc で明示)。
  flake registry 経由の評価では nix.conf や `~/.config/nixpkgs/config.nix` は
  効かないので、env var を渡すのが唯一の手段。

## 初回セットアップ

### 標準: nixpkgs から直接 install (推奨)

「全員いつでも最新」を最小手数で実現するルート。研究室運用ではこちらで十分。

```bash
sudo -i env NIXPKGS_ALLOW_UNFREE=1 nix profile add --profile /nix/var/nix/profiles/default --impure nixpkgs#claude-code
```

- `env NIXPKGS_ALLOW_UNFREE=1`: unfree license 同意 (`sudo` が env を剥がすので `env` 経由)
- `--impure`: env var の参照と registry 解決のため必須
- `add`: 新しめの nix では `install` は deprecated alias、`add` が正規

### オプション: バージョンを pin したい場合

更新タイミングを管理者が厳密にコントロールしたい / 過去の正確な
version に戻せる台帳を残したい場合のみ。`/etc/nix-system/flake.nix` を作って
lock を生成する:

```bash
sudo mkdir -p /etc/nix-system
sudo tee /etc/nix-system/flake.nix <<'EOF'
{
  description = "system-wide nix profile";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfreePredicate = p:
          builtins.elem (nixpkgs.lib.getName p) [ "claude-code" ];
      };
    in {
      packages.x86_64-linux.default = pkgs.buildEnv {
        name = "system-tools";
        paths = [ pkgs.claude-code ];
      };
    };
}
EOF

cd /etc/nix-system
sudo -i nix flake lock
sudo -i nix profile add --profile /nix/var/nix/profiles/default /etc/nix-system
```

`/etc/nix-system/flake.lock` がバージョン台帳。
git 管理したい場合は `/etc/nix-system/` 自体を git init するか、
`~/dotfiles/system-flake/` 等に置いて symlink でも可。

## 動作確認

```bash
which claude
ls -la /nix/var/nix/profiles/default/bin/claude

# 別ユーザでも (nix group 不要)
sudo -u <user> -i bash -c 'which claude && claude --version'
```

## ユーザへの案内例

```
このサーバに claude-code がシステム共有で install されました。
- 再ログイン後、`claude --version` で確認
- `claude login` で各自の Anthropic アカウントで認証
- 認証情報は ~/.claude/.credentials.json (mode 0600) に保存
- 利用は各自の責任 (API 課金は個人アカウント)
```

`/etc/motd` に書いておくと SSH ログイン時に自動表示される。

## バージョン更新

### 標準 (pin なし)

`nixpkgs` registry の最新を取りに行くので、これだけで claude-code は最新になる:

```bash
sudo -i env NIXPKGS_ALLOW_UNFREE=1 nix profile upgrade --profile /nix/var/nix/profiles/default --impure '.*'
```

cron 等で自動化する場合もこの 1 行で OK (env を inline で持ってるので素直に動く)。

### pin 運用の場合

```bash
cd /etc/nix-system
sudo -i nix flake update                                              # lock 更新
sudo -i nix profile upgrade --profile /nix/var/nix/profiles/default '.*'
```

更新後にユーザ通知 (`wall` / Slack 等)。
重要な作業中のメンバーが居ないタイミングで実施するのが望ましい。

## ロールバック

```bash
# 履歴確認
sudo nix profile history --profile /nix/var/nix/profiles/default

# 1 つ前に戻す
sudo nix profile rollback --profile /nix/var/nix/profiles/default

# 特定 generation 指定
sudo nix profile rollback --to N --profile /nix/var/nix/profiles/default
```

## 撤去

### claude-code だけ抜く

```bash
sudo nix profile remove --profile /nix/var/nix/profiles/default claude-code
sudo nix-collect-garbage -d
```

### システム profile 自体を空にする

```bash
sudo nix profile remove --profile /nix/var/nix/profiles/default '.*'
sudo nix-collect-garbage -d
```

## 他のツールも追加する場合

### 標準 (pin なし)

個別に add を重ねるだけ:

```bash
sudo -i nix profile add --profile /nix/var/nix/profiles/default --impure nixpkgs#ripgrep nixpkgs#fd
```

unfree ツール (claude-code 等) を追加する場合は `env NIXPKGS_ALLOW_UNFREE=1` を頭に付ける:

```bash
sudo -i env NIXPKGS_ALLOW_UNFREE=1 nix profile add --profile /nix/var/nix/profiles/default --impure nixpkgs#claude-code
```

### pin 運用の場合

`/etc/nix-system/flake.nix` の `paths = [ pkgs.claude-code ];` を拡張:

```nix
paths = with pkgs; [
  claude-code
  ripgrep
  fd
  # ... 追加したいツール
];
```

`unfree` ライセンスのものは `allowUnfreePredicate` の許可リストにも追加。
編集後:

```bash
cd /etc/nix-system
sudo -i nix flake lock --update-input nixpkgs   # nixpkgs を bump したい場合
sudo -i nix profile upgrade --profile /nix/var/nix/profiles/default '.*'
```

## 注意点

| 注意 | 対処 |
|---|---|
| tomoya-n 自身も home-manager 経由で claude-code を持っている場合、PATH が二重になる (home-manager 版が優先される) | 統一したいなら `home-research.nix` から claude-code を抜き、システム profile に統合 |
| 全員いきなり影響を受ける (バグ版の即時拡散) | 更新前に通知、ロールバック手順を共有 |
| unfree 同意は flake registry 経由だと永続化手段が乏しく、毎回 env var 必須 | `sudo -i env NIXPKGS_ALLOW_UNFREE=1 ...` で inline するのが確実。`/etc/nix/nix.conf` の `allow-unfree` は無効な setting なので注意 |
| `~/.claude/.credentials.json` は root から読める | サーバポリシーで「sudoer は token 閲覧可能」を明示 |
| claude-code の install 自体には nix group は不要だが、ユーザが `nix` を直接叩くと弾かれる (PATH には見えるのに実行不能) | 気になるなら nix group 追加。気にならないなら放置 |

## 別案との関係

- これを使う ⇄ 各ユーザが個人 flake (Tier 2) を持つ: 排他ではないが、両方使うと
  store に複数 derivation が並ぶ (実害は無い、disk 食うだけ)
- これを使う ⇄ 各ユーザが home-manager (Tier 3): 同上、PATH 順で個人版が優先される

「使いたい人は自分で」ポリシーに変える場合はこの doc を捨てて、
`README.md` の「他ユーザのオンボード」セクションに従えばよい。
