---@type vim.lsp.Config
---@param group any
  return {
    cmd = { 'simple-completion-language-server' },
    filetypes = { 'go', 'lua' },
    root_markers = { '.git', 'init.lua' },
    settings = {
      ext_snippets = {
        -- The one-file build (scripts/bundle.lua) unpacks them elsewhere.
        (vim.g.pure_bundle_dir or vim.fn.stdpath('config')) .. '/snippets',
      },
    },

    capabilities = {
      textDocument = {
        completion = {
          completionItem = {
            snippetSupport = true,
          },
        },
      },
    },
  }
