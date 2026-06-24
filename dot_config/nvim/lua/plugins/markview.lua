return {
  -- Markdown をバッファ内でリッチに描画する previewer。
  -- render-markdown.nvim から乗り換え。最大の理由は markview-smart-tables で
  -- 「窓幅を超える広い表」をセル内で折り返して自動フィットでき、
  -- 横スクロール無しで全体を読めること（render-markdown では不可能だった）。
  --
  -- 既定で描画 ON。normal モードで描画され、insert モードに入ると生テキストに
  -- 戻る（markview のデフォルト hybrid 挙動）ので、編集時は素のまま扱える。
  -- leader を覚えずとも i / <Esc> で素⇔描画が自然に切り替わる。
  -- 高速スクロール時の描画崩れは離散移動（j/k・<C-d>/<C-u>）で回避できる。
  -- tmux 内ではホイールを矢印キーに変換して同経路へ寄せている（tmux.conf 参照）。
  -- normal のまま完全に素で見たいときは <leader>um で描画トグル（保険）。
  -- 画像や巨大な表を別ウィンドウで見る用途は md-render（render-markdown）に
  -- 分担する想定（ただし <leader>mp キーは未実装。md-render.lua の TODO 参照）。
  "OXY2DEV/markview.nvim",
  -- Markdown を開いたときだけ遅延読み込み
  ft = { "markdown" },
  dependencies = {
    -- 必須パーサー (markdown / markdown_inline) は LazyVim 既定で導入済み
    "nvim-treesitter/nvim-treesitter",
    -- アイコン供給元（mini.icons / nvim-web-devicons どちらでも可）
    -- ※ mini.nvim は GitHub org が echasnovski → nvim-mini に移管済み
    "nvim-mini/mini.icons",
    -- 広い表をセル折返しで窓幅に収める拡張（markview 専用・Neovim 0.11+）
    "gunasekar/markview-smart-tables.nvim",
  },
  config = function()
    -- 表フィットの設定: 窓幅の 0.9 倍を上限に、列は最小 5 桁まで縮める
    require("markview-smart-tables").setup({
      wrap_width = 0.9,
      wrap_minwidth = 5,
    })

    require("markview").setup({
      -- 表のレンダラを smart-tables に差し替える（公式フック方式）
      renderers = {
        markdown_table = function(buffer, item)
          require("markview-smart-tables").render(buffer, item)
        end,
      },
    })

    -- <leader>um で描画の ON/OFF をトグル（render-markdown 時代と同じキー）
    vim.keymap.set("n", "<leader>um", "<cmd>Markview<cr>", { desc = "Markdown 描画 ON/OFF (markview)" })
  end,
}
