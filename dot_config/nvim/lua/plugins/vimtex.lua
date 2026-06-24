-- LazyVim の lang.tex extra（vimtex 本体）に対する上書き。
-- extra 側はビュワー method を設定しないので、ここで Skim + SyncTeX と
-- 日本語 upLaTeX エンジンを指定する。ビルドの tool 定義（uplatex/dvipdfmx 等）は
-- ~/.latexmkrc に集約済み（VSCode/Zed/CLI と共有する単一ソース）。
return {
  "lervag/vimtex",
  -- vimtex は g: 変数を読み込み時に評価するため init（プラグイン読込前）で設定する。
  init = function()
    -- ビュワー: SyncTeX 対応の Skim。
    -- 保存→latexmk(継続コンパイル)→PDF 更新→Skim が自動リロード、の流れになる。
    vim.g.vimtex_view_method = "skim"
    vim.g.vimtex_view_skim_sync = 1 -- コンパイル後に PDF 側を該当行へ前方同期
    vim.g.vimtex_view_skim_activate = 1 -- 前方同期時に Skim を前面化

    -- 日本語 LaTeX: uplatex → dvipdfmx（DVI 経由）。
    -- latexmk のデフォルトエンジンを -pdfdvi（pdf_mode=3）にする。
    -- 実際に走らせる uplatex / dvipdfmx は ~/.latexmkrc の $latex / $dvipdf が担う。
    vim.g.vimtex_compiler_latexmk_engines = { ["_"] = "-pdfdvi" }
  end,
}
