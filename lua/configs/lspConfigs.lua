-- Central LSP and language settings configurator

-- Define a single augroup for all language-specific editor settings.
-- This prevents files from overwriting each other's autocommands.
local lang_settings_group = vim.api.nvim_create_augroup('LanguageSettings', { clear = true })

-- List of servers to configure
local servers = {
  'lua_ls',
  'gopls',
  'markdown_oxide',
  'marksman',
  'clangd',
  'copilot',
  'csharp_ls',
  'scls',
}

for _, server_name in ipairs(servers) do
    vim.lsp.enable(server_name)
  -- Each language file is expected to be a module in '~/.config/nvim/lsp/'
  -- It should return a function that takes the augroup and returns an LSP config table.
  local server_config_loader = require('lsp.' .. server_name)
  if type(server_config_loader) == 'function' then
    local lsp_config = server_config_loader(lang_settings_group)
    -- Configure the LSP server with the returned table
    vim.lsp.config(server_name, lsp_config)
  else
    -- Fallback for files that just return a table (legacy)
    vim.lsp.config(server_name, server_config_loader)
  end
end

