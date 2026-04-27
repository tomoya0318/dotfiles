{ pkgs-unstable, ... }: {
  # Linux/研究サーバ専用の追加設定
  # Mac は home-mac.nix を参照
  home.packages = [
    # Mac は公式インストーラ (~/.local/bin/claude) を使うため、Nix 管理は Linux のみ
    pkgs-unstable.claude-code
  ];
}
