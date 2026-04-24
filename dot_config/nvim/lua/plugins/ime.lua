return {
  -- 日本語入力の自動切り替え (Mac のみ)
  -- Linux (SSH 先の研究サーバ等) では IME 切替は client 側 (Mac) の責務なので無効化
  {
    "keaising/im-select.nvim",
    enabled = function() return vim.fn.has("mac") == 1 end,
    config = function()
      require("im_select").setup({
        -- CLI は Nix (pkgs-unstable.macism) 経由でインストール
        default_command = "macism",
        set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
        set_previous_events = { "InsertEnter" },
        async_switch_im = true,
      })
    end,
  },
}
