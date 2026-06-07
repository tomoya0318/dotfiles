{ pkgs, pkgs-unstable, ... }: {
  home.username = "tomoya-n";
  home.homeDirectory = "/mnt/data1/tomoya-n";
  home.stateVersion = "24.11";

  home.packages = (with pkgs; [
    git
    lefthook
    fzf
    ripgrep
    fd
    jq
    chezmoi
  ]) ++ (with pkgs-unstable; [
    neovim
  ]);
  # claude-code はシステム共有 profile (/nix/var/nix/profiles/default) で管理。
  # 詳細は system-shared-tools.md。home-manager で持つと PATH が二重になるため除外。

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    history = {
      size = 1000000;
      save = 1000000;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
    };
    shellAliases = {
      dev = "cd ~/dev";
    };
    initExtra = ''
      zstyle ':completion:*' menu select
      zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
    '';
  };

  programs.starship.enable = true;
  programs.fzf.enable = true;
  programs.git = {
    enable = true;
    userName = "tomoya0318";
    userEmail = "tmox13e@gmail.com";
    extraConfig = {
      url."git@github.com:".insteadOf = "https://github.com/";
    };
    ignores = [
      ".DS_Store"
      "*.swp"
      "*.swo"
      "*~"
      ".netrwhist"
      "*.local"
      "*.secret"
      "*.env"
      ".venv/"
      "venv/"
      "__pycache__/"
      "*.py[cod]"
      ".ipynb_checkpoints/"
      "node_modules/"
      ".mise.local.toml"
      "mise.local.toml"
    ];
  };
}
