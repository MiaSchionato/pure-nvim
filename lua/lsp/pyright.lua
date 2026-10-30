---@brief
---
--- https://github.com/microsoft/pyright
---
--- Installed with: npm install -g pyright
--- (the server itself is the `pyright-langserver` it puts in the npm folder)

---@type vim.lsp.Config
return {
  cmd = { 'pyright-langserver', '--stdio' },
  filetypes = { 'python' },
  root_markers = {
    'pyrightconfig.json',
    'pyproject.toml',
    'setup.py',
    'setup.cfg',
    'requirements.txt',
    'Pipfile',
    '.git',
  },
  settings = {
    python = {
      analysis = {
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        -- Only the files that are open: a whole project's diagnostics are slow on a big repo.
        diagnosticMode = 'openFilesOnly',
      },
    },
  },
}
