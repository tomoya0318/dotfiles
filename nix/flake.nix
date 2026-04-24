{
  description = "Dotfiles flake (Home Manager configurations)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # 使い方:
  #   cd nix/
  #   cp local.nix.example local.nix      # 初回のみ: ホームパスを記述
  #   nix run home-manager/release-24.11 -- switch --flake .#research
  outputs = { nixpkgs, home-manager, ... }: {
    homeConfigurations = {
      "research" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [
          ./home-research.nix
          ./local.nix
        ];
      };
      # 将来 Mac 用プロファイルを追加する場合:
      # "mac" = home-manager.lib.homeManagerConfiguration {
      #   pkgs = nixpkgs.legacyPackages.aarch64-darwin;
      #   modules = [ ./home-mac.nix ./local.nix ];
      # };
    };
  };
}
