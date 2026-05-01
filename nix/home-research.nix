{ pkgs-unstable, ... }: {
  # Linux/研究サーバ専用の追加設定
  # Mac は home-mac.nix を参照
  #
  # claude-code はシステム共有 profile (/nix/var/nix/profiles/default) で管理。
  # 詳細は system-shared-tools.md。home-manager で持つと PATH が二重になるため除外。
  home.packages = [];
}
