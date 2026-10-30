---@brief
---
--- https://github.com/bash-lsp/bash-language-server
---
--- Installed with: npm install -g bash-language-server
--- It uses shellcheck for diagnostics when that is on the PATH.

---@type vim.lsp.Config
return {
  cmd = { 'bash-language-server', 'start' },
  filetypes = { 'sh', 'bash' },
  root_markers = { '.git' },
  settings = {
    bashIde = {
      -- Files of the folder are indexed for go-to-definition; a glob that skips the rest of the tree.
      globPattern = '*@(.sh|.inc|.bash|.command)',
    },
  },
}
