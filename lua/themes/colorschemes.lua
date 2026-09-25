-- The colorscheme applied at startup (configs/autocmds.lua applies it, and
-- falls back to "myghtfly", the local one in colors/, when it is missing).
-- The statusline has its own colours for themes that do not define its
-- groups, so any theme works.
--
-- The theme picked with <leader>fc is remembered across restarts by Neovim
-- itself: global variables named in all capitals are saved in the ShaDa file
-- (the '!' flag of 'shada'), so MY_THEME comes back on the next start.
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

local floatGrous = {
  NormalFloat = { bg = "NONE" },
  FloatBorder = { bg = "NONE" },
}

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
  if vim.g.neovide and okNeo then
    utils.ConfigHighlightByColorscheme("NeoSolarized", floatGrous)
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

vim.keymap.set('n','<leader>ox', function()
   for _, colors in pairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = colors, link = false })
    local new_hl = vim.tbl_extend("force", hl, { bg = "NONE", ctermbg = "NONE" })
    vim.api.nvim_set_hl(0, colors, new_hl)
   end
end, {silent = true, desc = "Transparent mode"})


