return {
  -- Markdown 用 LSP (marksman)
  -- 見出し・リンクの補完、[](#見出し) や [[wikilink]] のジャンプ、
  -- 見出しリネーム連動、壊れたリンクの検出などを提供する。
  -- mason-lspconfig 経由で marksman 本体は自動インストールされる。
  -- ※ lint(markdownlint) / 整形(prettier) は意図的に入れていない:
  --   主筆は Claude Code なので、生成文への大量のスタイル警告や
  --   保存時オートフォーマットによる差分の膨張を避けるため。
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        marksman = {},
      },
    },
  },

  -- ブラウザで完成形をプレビュー (GitHub 型)
  -- 普段はインライン描画 (render-markdown) で確認し、
  -- 清書前など本物に近い見た目を見たいときだけ <leader>cp で起動する。
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = function()
      require("lazy").load({ plugins = { "markdown-preview.nvim" } })
      vim.fn["mkdp#util#install"]()
    end,
    keys = {
      {
        "<leader>cp",
        ft = "markdown",
        "<cmd>MarkdownPreviewToggle<cr>",
        desc = "Markdown Preview",
      },
    },
    config = function()
      vim.cmd([[do FileType]])
    end,
  },
}
