-- Central LSP and language settings configurator

-- Define a single augroup for all language-specific editor settings.
-- This prevents files from overwriting each other's autocommands.
local lang_settings_group = vim.api.nvim_create_augroup('LanguageSettings', { clear = true })

-- List of servers to configure
local servers = {
  'lua_ls',
  'gopls',
  'markdown_oxide', -- Obsidian-aware; marksman was a second markdown server
  'clangd',
  -- 'copilot',  -- provided by the copilot.vim plugin (plugins/copilot.lua),
  --                which runs its own language server. Enabling it here too
  --                started a second, redundant Copilot client.
  'csharp_ls',
  'scls',
  'pyright', -- Python (npm install -g pyright)
  'bashls', -- bash and sh (npm install -g bash-language-server)
  'orgls', -- org notes of the vault: hover on links (in-process, no executable; lua/lsp/orgls.lua)
}

local isWindows = vim.fn.has('win32') == 1
local isWsl = vim.fn.has('wsl') == 1

-- WSL: its PATH carries the Windows directories (/mnt/c/...), and every lookup in them crosses into the Windows file system:
-- on Mia's machine 58 of 67 PATH entries, and 18 exepath() calls took 1.4 s at every start. Servers installed in WSL are never
-- in /mnt, so a lookup there skips those entries.
local function exepathFast(bin)
  if not isWsl then return vim.fn.exepath(bin) end
  for _, dir in ipairs(vim.split(vim.env.PATH or '', ':', { plain = true })) do
    if dir ~= '' and not dir:match('^/mnt/%a/') then
      local full = dir .. '/' .. bin
      if vim.fn.executable(full) == 1 then return full end
    end
  end
  return ''
end

-- Windows: npm and winget install shims with no file extension next to the
-- real .cmd/.exe. Neovim's executable() finds those via PATHEXT and reports 1,
-- but libuv spawns the literal name and fails with ENOENT -- which is what
-- produced the "Spawning language server with cmd ... failed" popup on every
-- buffer. Resolve to a full path Windows can actually execute.
local function resolveCommand(bin)
  if type(bin) ~= 'string' or bin == '' then return nil end

  local path = exepathFast(bin)
  if path == '' then return nil end
  if not isWindows then return path end
  if path:lower():match('%.%a+$') then return path end

  for _, ext in ipairs({ '.cmd', '.exe', '.bat' }) do
    local candidate = vim.fn.exepath(bin .. ext)
    if candidate ~= '' then return candidate end
  end
  return nil
end

-- The resolved path of each server is kept in a small file in the state directory, so a start does not search PATH at all. A hit
-- is only used while the file still exists; a server that was not found is not remembered (it is looked for again next time).
local cacheFile = vim.fn.stdpath('state') .. '/lsp-command-cache.json'
local cache

local function loadCache()
  if cache then return cache end
  cache = {}
  local fh = io.open(cacheFile, 'r')
  if fh then
    local ok, data = pcall(vim.json.decode, fh:read('*a'))
    fh:close()
    if ok and type(data) == 'table' then cache = data end
  end
  return cache
end

local function resolveCached(bin)
  local known = loadCache()
  local hit = known[bin]
  if hit and vim.uv.fs_stat(hit) then return hit end

  local path = resolveCommand(bin)
  if path then
    known[bin] = path
    vim.fn.mkdir(vim.fn.stdpath('state'), 'p')
    local fh = io.open(cacheFile, 'w')
    if fh then
      fh:write(vim.json.encode(known))
      fh:close()
    end
  end
  return path
end

local function configureServer(server_name, lsp_config, bin, cmd)
  local resolved = bin and resolveCached(bin) or nil

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
  local filetypes = type(lsp_config) == 'table' and lsp_config.filetypes or nil

  if bin and type(filetypes) == 'table' and #filetypes > 0 then
    -- Looking for the server and registering it waits for the first file of one of its filetypes: a start that opens no such
    -- file pays nothing. enable() also attaches to the buffers that are already open, so that first file gets its server too.
    vim.api.nvim_create_autocmd('FileType', {
      group = lang_settings_group,
      pattern = filetypes,
      once = true,
      callback = function() configureServer(server_name, lsp_config, bin, cmd) end,
    })
  else
    configureServer(server_name, lsp_config, bin, cmd)
  end
end

-- Automatic hover: once the cursor has rested on a spot for vim.g.lsp_auto_hover_delay ms (default 500), the hover
-- of whichever server has one shows by itself; nothing is said when there is nothing to show. K does the same on
-- demand. vim.g.lsp_auto_hover = false turns it off. A timer of its own, so 'updatetime' (which other things
-- use) stays as it is.
local hoverTimer = assert(vim.uv.new_timer())

local function autoHoverNow(buf, win, row, col)
  if vim.g.lsp_auto_hover == false or vim.api.nvim_get_current_win() ~= win or vim.api.nvim_get_current_buf() ~= buf then return end
  if vim.api.nvim_get_mode().mode ~= 'n' or vim.fn.pumvisible() == 1 then return end
  if vim.bo[buf].buftype ~= '' or vim.api.nvim_win_get_config(win).relative ~= '' then return end
  local pos = vim.api.nvim_win_get_cursor(win)
  if pos[1] ~= row or pos[2] ~= col then return end
  if #vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/hover' }) == 0 then return end
  vim.lsp.buf.hover({ silent = true })
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter' }, {
  group = lang_settings_group,
  callback = function(args)
    hoverTimer:stop()
    if vim.g.lsp_auto_hover == false then return end
    local win = vim.api.nvim_get_current_win()
    local pos = vim.api.nvim_win_get_cursor(win)
    hoverTimer:start(vim.g.lsp_auto_hover_delay or 2000, 0, vim.schedule_wrap(function()
      autoHoverNow(args.buf, win, pos[1], pos[2])
    end))
  end,
})
vim.api.nvim_create_autocmd('InsertEnter', { group = lang_settings_group, callback = function() hoverTimer:stop() end })

-- Locale. The shell here exports LANG=C.UTF-8 and LC_ALL=C.UTF-8; Windows' C library does not know
-- "C.UTF-8", so Neovim stays in the plain "C" locale and :checkhealth says the locale does not
-- support UTF-8. ".UTF-8" is the system default locale with the UTF-8 code page, which it does know.
-- (Only the character classes change; the text was always UTF-8 inside Neovim.)
if vim.v.ctype == 'C' then
  pcall(vim.cmd, 'language ctype .UTF-8')
end

