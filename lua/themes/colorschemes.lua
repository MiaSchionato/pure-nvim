-- The colorscheme applied at startup. This was never set anywhere, so
-- g:MY_THEME was nil on every launch and the VimEnter handler in
-- configs/autocmds.lua silently failed to apply any theme. "myghtfly" is the
-- local colorscheme in colors/ and the only one that defines the statusline
-- groups (BlueMode, IconsBlue, ...) that pure/statusline.lua renders.
vim.g.MY_THEME = vim.g.MY_THEME or "myghtfly"

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

for name, link in pairs(colorschemes) do
  vim.pack.add({{ src = 'https://github.com/' .. link, name = name }})
end

local floatGrous = {
  NormalFloat = { bg = "NONE" },
  FloatBorder = { bg = "NONE" },
}

-- Required defensively: a bare require() here aborted this whole module when a
-- theme plugin was missing or failed to clone, taking the transparency setup
-- and the <leader>ctx mapping down with it.
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

vim.keymap.set('n','<leader>ctx', function()
   for _, colors in pairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = colors, link = false })
    local new_hl = vim.tbl_extend("force", hl, { bg = "NONE", ctermbg = "NONE" })
    vim.api.nvim_set_hl(0, colors, new_hl)
   end
end, {silent = true, desc = "Transparent mode"})


