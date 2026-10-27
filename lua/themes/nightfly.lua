vim.pack.add({
	{ src = 'https://github.com/bluz71/vim-nightfly-colors',
  name = 'nightfly' }
})
local ok, nightfly = pcall(require, "nightfly")
vim.g.nightflyTransparent = false
