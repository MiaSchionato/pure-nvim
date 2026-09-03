vim.cmd("hi clear")
if vim.fn.exists("syntax_on") ~= 0 then
  vim.cmd("syntax reset")
end

-- Vital: Set the global name variable so Neovim knows the theme is active
vim.g.colors_name = "myghtfly"

require("themes.myghtfly").setup()
