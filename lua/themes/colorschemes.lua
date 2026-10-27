-- The theme picked with <leader>fc is remembered across restarts in
-- stdpath('data')/colorscheme (see pure/omarchy-theme.lua); configs/autocmds.lua
-- reads it when it applies the colorscheme. MY_THEME is only the default and
-- the session's current pick: ShaDa also saved it, but only on a clean exit.
local M = {}

local colorschemes = {
  ["solarized-osaka"]  =  "craftzdog/solarized-osaka.nvim",
  eldritch =  "eldritch-theme/eldritch.nvim",
  ethereal =  "bjarneo/ethereal.nvim",
  catppuccin = "catppuccin/nvim",
  tokyonight = "folke/tokyonight.nvim",
  ["rose-pine"] = "rose-pine/neovim",
  tokyodark = "tiagovla/tokyodark.nvim",
  ["night-owl"] = "oxfist/night-owl.nvim",
  NeoSolarized = "Tsuzat/NeoSolarized.nvim",
  Palenight = "drewtempelmeyer/palenight.vim",
  Solarized_highlight = "lifepillar/vim-solarized8",
}

-- One vim.pack.add for all of them: one install / confirmation step instead
-- of eleven.
local specs = {}
for name, link in pairs(colorschemes) do
  table.insert(specs, { src = 'https://github.com/' .. link, name = name })
end
vim.pack.add(specs)


-- Every theme starts opaque, with its own background. These two plugins default to
-- transparent, so it is switched off here; the rest are opaque by default. A theme
-- is never applied from here: configs/autocmds.lua applies the saved one.
local opaque = {
  NeoSolarized = { style = "dark", transparent = false },
  ["solarized-osaka"] = { style = "dark", transparent = false },
}
for name, opts in pairs(opaque) do
  local ok, theme = pcall(require, name)
  if ok and type(theme) == "table" and type(theme.setup) == "function" then
    theme.setup(opts)
  end
end

-- Highlight groups that <leader>oxc clears while the editor is transparent
-- (see configs/functions.lua).
M.groups = {
  "Normal",
  "NormalNC",
  "NormalFloat",
  "FloatBorder",
  "FloatTitle",
  "WinBar",
  "WinBarNC",
  "WinSeparator",
  "VertSplit",
  "SignColumn",
  "LineNr",
  "CursorLineNr",
  "FoldColumn",
  "EndOfBuffer",
  "StatusLine",
  "StatusLineNC",
  "TabLine",
  "TabLineFill",
  "TabLineSel",
  "Pmenu",
  "PmenuSel",
  "PmenuSbar",
  "PmenuThumb",
  "Question",
  "QuickFixLine",
  "MsgArea",
}

return M
