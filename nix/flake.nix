{
  description = "Dotfiles flake (Home Manager configurations)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # claude-code のように頻繁に更新されるパッケージは unstable から追従する
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # 使い方:
  #   cd nix/
  #   研究サーバ: nix run home-manager/release-24.11 -- switch --flake .#research
  #   Mac:        nix run home-manager/release-24.11 -- switch --flake .#mac
  #
  # ファイル構成:
  #   home-common.nix   両 OS 共通の設定 (packages, programs, home.homeDirectory は OS 分岐)
  #   home-mac.nix      Mac 固有 (brew formula 移行分、RN/Android env、OrbStack 等)
  #   home-research.nix Linux/研究サーバ固有 (現時点では未使用、必要になれば作成)
  outputs = { nixpkgs, nixpkgs-unstable, home-manager, ... }:
    let
      # unfree ライセンスのパッケージ (claude-code 等) を明示的に許可する
      allowedUnfree = [ "claude-code" ];
      mkUnstablePkgs = system: import nixpkgs-unstable {
        inherit system;
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs-unstable.lib.getName pkg) allowedUnfree;
      };
      mkExtraArgs = system: {
        pkgs-unstable = mkUnstablePkgs system;
      };
    in {
      homeConfigurations = {
        "research" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = mkExtraArgs "x86_64-linux";
          modules = [
            ./home-common.nix
          ];
        };
        "mac" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          extraSpecialArgs = mkExtraArgs "aarch64-darwin";
          modules = [
            ./home-common.nix
            ./home-mac.nix
          ];
        };
      };
    };
}
