-- ファイル可視性の単一ソース（Single Source of Truth）。
-- oil（plugins/oil.lua）と snacks picker（plugins/snacks.lua）の双方がここを参照する。
-- 「常に隠すもの（キャッシュ・依存ディレクトリ等）」をここだけで管理し、二重管理を避ける。
--
-- 方針:
--   - ドットファイルや .gitignore 対象（tmp/ 等）は基本的に「見せる」
--   - 下の always_hidden_* に挙げたものだけを常に隠す（oil の is_always_hidden 相当）
--   - .env / .envrc などの env 系は always_shown_prefixes で「必ず表示」を明示する

local M = {}

-- 完全名一致で常に隠すディレクトリ/ファイル
M.always_hidden_names = {
  -- 汎用
  ".git",
  ".DS_Store",
  -- JS / TS / フロントエンド
  "node_modules",
  ".next", -- Next.js のビルドキャッシュ
  ".nuxt", -- Nuxt のビルドキャッシュ
  ".turbo", -- Turborepo のキャッシュ
  -- Python
  ".venv", -- 仮想環境
  "venv",
  "__pycache__", -- バイトコードキャッシュ
  ".mypy_cache",
  ".pytest_cache",
  ".ruff_cache",
  ".import_linter_cache",
}

-- 名前が可変なもの（glob。`*.ext` 形式を想定）
M.always_hidden_globs = {
  "*.pyc",
  "*.egg-info",
}

-- oil の view_options.is_always_hidden 用コールバック
function M.oil_is_always_hidden(name, _)
  for _, n in ipairs(M.always_hidden_names) do
    if name == n then
      return true
    end
  end
  for _, g in ipairs(M.always_hidden_globs) do
    local suffix = g:match("^%*(.+)$") -- "*.pyc" -> ".pyc"
    if suffix and name:sub(-#suffix) == suffix then
      return true
    end
  end
  return false
end

-- snacks picker の exclude 用（fd/rg の glob 配列）。
-- always_hidden_names と always_hidden_globs をそのまま結合して返す。
function M.snacks_exclude()
  local ex = {}
  vim.list_extend(ex, M.always_hidden_names)
  vim.list_extend(ex, M.always_hidden_globs)
  return ex
end

-- snacks のファイル系ピッカー(files / grep など)で共有する可視性オプション。
-- oil と同じ見え方（ドット表示・gitignore 無視・上記だけ除外）にする。
function M.snacks_source_opts()
  return {
    hidden = true, -- ドットファイルを表示（fd --hidden）
    ignored = true, -- .gitignore を無視＝tmp/ 等も表示（fd --no-ignore）
    exclude = M.snacks_exclude(), -- 上の一覧だけ常に除外（fd -E）
  }
end

return M
