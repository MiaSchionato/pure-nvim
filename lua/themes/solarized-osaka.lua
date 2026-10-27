local ok, theme = pcall(require, "solarized-osaka")
if ok and theme and vim.g.MY_THEME == "solarized-osaka" then
  if vim.g.neovide then
    theme.setup({transparent = false})
    pcall(vim.cmd.colorscheme, "solarized-osaka")
  else
    theme.setup({ transparent = true, })
    pcall(vim.cmd.colorscheme, "solarized-osaka")
  end
end

