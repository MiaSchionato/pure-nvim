-- The only few plugins on this config

vim.pack.add({
  {src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main'},
  -- {src = 'https://github.com/nvim-treesitter/nvim-treesitter-textobjects', version = 'master'}
})

local treesitter = require('nvim-treesitter')

-- The 'main' branch dropped the old options table entirely: setup() now takes
-- nothing but `install_dir`, and ensure_installed / sync_install / auto_install
-- / highlight / indent / textobjects are ignored outright. Passing them here
-- meant no parser was ever installed and highlighting was never switched on.
treesitter.setup()

local ensure_installed = {
  "c",
  "cpp",
  "c_sharp",       -- the parser is 'c_sharp', not 'cs'
  "lua",
  "json",
  "vim",
  "vimdoc",
  "query",
  "markdown",
  "markdown_inline",
  "go",
  "bash",
  "dockerfile",    -- was 'dockerle'
  "python",
}

-- language.add() returns true / nil rather than throwing, so the return value
-- has to be checked: a bare pcall() around it always succeeds and would report
-- every parser as present. This also sees the parsers Neovim itself ships
-- (c, lua, markdown, markdown_inline, query, vim, vimdoc), which
-- nvim-treesitter's own get_installed() does not.
local function parser_available(lang)
  local ok, added = pcall(vim.treesitter.language.add, lang)
  return ok and added == true
end

local missing = vim.tbl_filter(function(lang)
  return not parser_available(lang)
end, ensure_installed)

-- install() shells out to the tree-sitter CLI on the 'main' branch. When the
-- CLI is absent, installing is skipped silently here: warning on every launch
-- about languages you may never open is just noise. The FileType handler below
-- reports it instead, once, and only for a language you actually opened.
local wanted = {}
for _, lang in ipairs(ensure_installed) do wanted[lang] = true end

if #missing > 0 and vim.fn.executable('tree-sitter') == 1 then
  treesitter.install(missing)
end

-- One notice per session, not one per language: the remedy is the same for all
-- of them and repeated popups are just noise.
local warned = false
local function warnMissingParser(lang)
  if warned or not wanted[lang] then return end
  warned = true
  vim.schedule(function()
    vim.notify(
      'nvim-treesitter: no parser for ' .. lang .. ' and no tree-sitter CLI on PATH.'
        .. '\nInstall with: npm install -g tree-sitter-cli',
      vim.log.levels.WARN)
  end)
end

-- On 'main', highlighting is opt-in per buffer via vim.treesitter.start().
local max_filesize = 100 * 1024 -- 100 KB

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('PureTreesitter', { clear = true }),
  callback = function(args)
    local lang = vim.treesitter.language.get_lang(args.match)
    if not lang then
      return
    end

    local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(args.buf))
    if ok and stats and stats.size > max_filesize then
      return
    end

    -- start() throws when the language has no parser; that is the cheapest and
    -- most accurate availability check.
    if pcall(vim.treesitter.start, args.buf, lang) then
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    elseif vim.fn.executable('tree-sitter') == 0 then
      warnMissingParser(lang)
    end
  end,
})

-- Textobjects need the nvim-treesitter-textobjects plugin above to be
-- uncommented; on 'main' they are configured through its own setup(), not here.
-- keymaps: iq/aq @string, if/af @function, ic/ac @class
