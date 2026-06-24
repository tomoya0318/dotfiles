-- file 系ピッカー(files / grep)の見え方を oil と揃える。
-- 除外リスト等の実体は config/file_visibility.lua（単一ソース）に集約し、ここでは参照のみ。
local fv = require("config.file_visibility")

-- 共有可視性オプションを、対象ソースぶん複製して割り当てる
-- （deepcopy しないと exclude テーブルを複数ソースで共有してしまうため）
local sources = {}
for _, name in ipairs({ "files", "grep" }) do
  sources[name] = vim.deepcopy(fv.snacks_source_opts())
end

return {
  "folke/snacks.nvim",
  -- picker プレビューの markdown を「軽い treesitter ハイライトだけ」にする。
  -- snacks 標準のプレビューは markdown に当たると markview を強制 require して
  -- strict_render を同期実行する（util/markdown.lua）。これが UI スレッドを
  -- ブロックし「README にカーソルを当てた瞬間に固まる」原因だった。
  -- 大きい README（幅広テーブル＋画像）だと smart-tables の列フィット計算と
  -- 画像処理まで乗って実質ハングする。プレビューにリッチ描画は不要なので
  -- render 関数を差し替えて殺す。実ファイルを開いたときの markview 描画は
  -- markview.lua 側でそのまま効く（こちらは無関係）。
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        local ok, md = pcall(require, "snacks.picker.util.markdown")
        if ok then
          md.render = function(buf)
            pcall(vim.treesitter.start, buf, "markdown")
          end
        end

        -- PDF にカーソルが当たると固まる対策。
        -- snacks.image の既定 formats は "pdf" を含み、picker は画像対応ファイルを
        -- magick/gs(ghostscript) で「同期変換」してプレビューする（preview.lua の
        -- supports_file → M.image 経路）。PDF はページ→画像変換が重く、カーソルが
        -- 当たった瞬間に UI スレッドをブロックしてハングする（markdown の固まりと同型）。
        -- formats から "pdf" だけ外して画像扱いをやめ、通常のバイナリ placeholder に
        -- 落とす。画像(png/jpg 等)のプレビューはそのまま効く。opts で formats を渡すと
        -- リスト全置換になり既定の増減に追従できないため、実行時に "pdf" だけ除去する。
        local ok_img, img = pcall(require, "snacks.image")
        if ok_img and type(img.config) == "table" and type(img.config.formats) == "table" then
          img.config.formats = vim.tbl_filter(function(ext)
            return ext ~= "pdf"
          end, img.config.formats)
        end
      end,
    })
  end,
  opts = {
    picker = {
      sources = sources,
    },
  },
}
