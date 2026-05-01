{ pkgs, pkgs-unstable, ... }: {
  home.username = "tomoya-n";
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then "/Users/tomoya-n"
    else "/mnt/data1/tomoya-n";
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
    neovim  # LazyVim が Neovim >= 0.11.2 を要求するため unstable から取得
  ]);
  # claude-code は OS で扱いを分ける:
  #   Linux (研究サーバ): システム共有 profile で管理 (system-shared-tools.md)
  #   Mac:                Anthropic 公式インストーラで ~/.local/bin/claude 管理

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
      # OS generated
      ".DS_Store"

      # Editor / IDE temp
      "*.swp"
      "*.swo"
      "*~"
      ".netrwhist"

      # Secrets / env
      "*.local"
      "*.secret"
      "*.env"

      # Python / data science
      ".venv/"
      "venv/"
      "__pycache__/"
      "*.py[cod]"
      ".ipynb_checkpoints/"

      # JS / frontend
      "node_modules/"

      # mise
      ".mise.local.toml"
      "mise.local.toml"
    ];
  };
}
