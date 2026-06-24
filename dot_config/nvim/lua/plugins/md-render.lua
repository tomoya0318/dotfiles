return {
  -- 編集バッファに extmark を重ねず、別ウィンドウ/タブに静的レンダリングする previewer。
  -- markview や render-markdown は「編集できる同一バッファに装飾を重ねる」方式のため、
  -- 高速スクロール時に可視範囲の再描画レースが起きて崩れる。md-render は編集バッファに
  -- 一切触れず別の場所に描くので、その崩れの仕組み自体が存在しない（切り替えて使う）。
  --
  -- 要件: Neovim 0.12+（本環境は 0.12.3）。画像/動画のインライン表示には
  -- Kitty graphics protocol 対応端末が必要で、Ghostty は対応済み。
  -- markview（<leader>um）と併存させ、しばらく見比べて好みの方に寄せる方針。
  "delphinus/md-render.nvim",
  version = "*",
  -- Markdown を開いたときだけ遅延読み込み
  ft = { "markdown" },
  dependencies = {
    -- コードブロックのファイル種別アイコン（任意）
    { "nvim-tree/nvim-web-devicons", version = "*" },
    -- 日本語の文節単位での折返し（任意・段落や表が自然に折り返る）
    { "delphinus/budoux.lua", version = "*" },
  },
  keys = {
    -- 別フロートウィンドウに描画して切替（普段使い）
    { "<leader>mp", "<cmd>MdRender float<cr>", ft = "markdown", desc = "Markdown 描画 (フロート切替)" },
    -- 別タブに描画して切替（じっくり読むとき）
    { "<leader>mt", "<cmd>MdRender tab<cr>", ft = "markdown", desc = "Markdown 描画 (タブ切替)" },
    -- ソース/描画を現在窓でトグル
    { "<leader>mr", "<cmd>MdRender toggle<cr>", ft = "markdown", desc = "Markdown 描画 (この窓でトグル)" },
  },
}
