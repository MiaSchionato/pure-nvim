vim.pack.add({
  'https://github.com/github/copilot.vim.git'
})

vim.g.copilot_no_tab_map = true

-- copilot.vim defaults to launching its server through `npx`, but on Windows
-- `npx` is an extensionless npm shim: executable() reports 1 while the spawn
-- fails with ENOENT, which is where the second "Spawning language server ...
-- failed" popup came from. Disabling the npx path makes it use the server it
-- already bundles, run through node.exe, which spawns fine.
vim.g.copilot_npx_command = 0
-- vim.g.copilot_filetypes = {
--   ['*'] = true,
--   ['markdown'] = false,
--   ['help'] = false,
--   ['TelescopePrompt'] = false,
--   ['NvimTree'] = false,
-- }

