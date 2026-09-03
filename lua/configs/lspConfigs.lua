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
  -- 'copilot',  -- provided by the copilot.vim plugin (plugins/copilot.lua),
  --                which runs its own language server. Enabling it here too
  --                started a second, redundant Copilot client.
  'csharp_ls',
  'scls',
}

-- Windows: npm and winget install shims with no file extension next to the
-- real .cmd/.exe. Neovim's executable() finds those via PATHEXT and reports 1,
-- but libuv spawns the literal name and fails with ENOENT -- which is what
-- produced the "Spawning language server with cmd ... failed" popup on every
-- buffer. Resolve to a full path Windows can actually execute.
local function resolveCommand(bin)
  if type(bin) ~= 'string' or bin == '' then return nil end

  local path = vim.fn.exepath(bin)
  if path == '' then return nil end
  if vim.fn.has('win32') == 0 then return path end
  if path:lower():match('%.%a+$') then return path end

  for _, ext in ipairs({ '.cmd', '.exe', '.bat' }) do
    local candidate = vim.fn.exepath(bin .. ext)
    if candidate ~= '' then return candidate end
  end
  return nil
end

for _, server_name in ipairs(servers) do
  -- Each language file is a module in 'lua/lsp/'. It returns either a function
  -- taking the augroup and returning an LSP config table, or the table itself.
  local server_config_loader = require('lsp.' .. server_name)
  local lsp_config = server_config_loader
  if type(server_config_loader) == 'function' then
    lsp_config = server_config_loader(lang_settings_group)
  end

  local cmd = type(lsp_config) == 'table' and lsp_config.cmd or nil
  local bin = type(cmd) == 'table' and cmd[1] or nil
  local resolved = bin and resolveCommand(bin) or nil

  if resolved and resolved ~= bin then
    lsp_config = vim.tbl_extend('force', lsp_config, {
      cmd = vim.list_extend({ resolved }, vim.list_slice(cmd, 2, #cmd)),
    })
  end

  -- config() before enable(): enable() reads the config to work out which
  -- filetypes to attach on, so registering it afterwards was too late.
  vim.lsp.config(server_name, lsp_config)

  -- Only enable a server that is actually installed and runnable. Enabling a
  -- missing one just yields a warning popup every time you open a file.
  if resolved or bin == nil then
    vim.lsp.enable(server_name)
  end
end
