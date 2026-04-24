{ config, pkgs, lib, ... }: {
  home.packages = with pkgs; [
    # brew formula からの移行
    awscli
    cmake
    coreutils
    curl
    ffmpeg
    gh
    tree
    uv
    wireguard-tools

    # Mac 固有
    terminal-notifier
    macism  # IME 切替 (nvim の im-select.nvim が呼ぶ)
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.mise.enable = true;

  home.sessionVariables = {
    EDITOR = "zed --wait";
    VISUAL = "zed --wait";
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/Library/pnpm"
  ];

  programs.zsh.initExtra = lib.mkAfter ''
    # Homebrew 環境 (Cask 管理のため残す)
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
      # brew shellenv が PATH 先頭を上書きするので Nix profile を戻す
      export PATH="$HOME/.nix-profile/bin:$PATH"
    fi

    # RN/Android 環境 (JDK/SDK が存在する時だけ)
    if [ -d /Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home ]; then
      export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
    fi
    if [ -d "$HOME/Library/Android/sdk" ]; then
      export ANDROID_HOME=$HOME/Library/Android/sdk
      export PATH="$PATH:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools"
    fi

    # OrbStack
    [ -f ~/.orbstack/shell/init.zsh ] && source ~/.orbstack/shell/init.zsh
  '';
}
