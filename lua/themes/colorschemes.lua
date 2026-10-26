-- The colorscheme applied at startup (configs/autocmds.lua applies it, and
-- falls back to "myghtfly", the local one in colors/, when it is missing).
-- The statusline has its own colours for themes that do not define its
-- groups, so any theme works.
--
-- The theme picked with <leader>fc is remembered across restarts in
-- stdpath('data')/colorscheme (see pure/omarchy-theme.lua); configs/autocmds.lua
-- reads it when it applies the colorscheme. MY_THEME is only the default and
-- the session's current pick: ShaDa also saved it, but only on a clean exit.
vim.g.MY_THEME = vim.g.MY_THEME or "NeoSolarized"

local utils = require("configs.functions")
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

-- Required defensively: a bare require() here aborted this whole module when a
-- theme plugin was missing or failed to clone, taking the transparency setup
-- and the <leader>ox mapping down with it.
local okNeo, NeoSolarized = pcall(require, "NeoSolarized")
local okOsaka, Solarized_osaka = pcall(require, "solarized-osaka")

vim.schedule(function()
  local transparent = not vim.g.neovide

  if okNeo then
    NeoSolarized.setup({ style = "dark", transparent = transparent })
  end
  if okOsaka then
    Solarized_osaka.setup({ style = "dark", transparent = transparent })
  end
end)


local groups = {
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

-- Real toggle: the first press saves the groups' current highlights and
-- clears their bg; the second restores them. A colorscheme change drops the
-- saved copy (the new theme already set its own colours).
local savedHl
vim.api.nvim_create_autocmd("ColorScheme", { callback = function() savedHl = nil end })

vim.keymap.set('n','<leader>ox', function()
  if savedHl then
    for name, hl in pairs(savedHl) do
      vim.api.nvim_set_hl(0, name, hl)
    end
    savedHl = nil
    return
  end
  savedHl = {}
  for _, name in ipairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    savedHl[name] = hl
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", hl, { bg = "NONE", ctermbg = "NONE" }))
  end
end, {silent = true, desc = "Toggle transparent mode"})
