{
  description = "Dotfiles flake (Home Manager configurations)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # 使い方:
  #   cd nix/
  #   研究サーバ: nix run home-manager/release-24.11 -- switch --flake .#research
  #
  # ファイル構成:
  #   home-research.nix  Linux/研究サーバの全設定
  outputs = { nixpkgs, nixpkgs-unstable, home-manager, ... }:
    let
      allowedUnfree = [];
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
            ./home-research.nix
          ];
        };
      };
    };
}
