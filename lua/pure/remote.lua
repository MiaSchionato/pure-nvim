-- =============================================================================
--  Remote
-- =============================================================================
--  Two ways for something outside (a launcher plugin, a script) to open a
--  file in a Neovim that is already running instead of starting another.
--
--  1. The address file. Every Neovim with a UI writes its own address
--     (v:servername) to a file when the UI attaches and each time it gets the
--     focus, so the file always names the Neovim used last:
--
--       line 1  the address   (\\.\pipe\nvim.1234.0, /run/user/1000/nvim.1234.0)
--       line 2  its process id
--
--     The program outside reads it and runs
--
--       nvim --server ADDRESS --remote FILE
--
--     Nothing is fixed, so any number of Neovims may be open, in any terminal
--     or GUI, and one left behind without a window is never the one named
--     (it gets no focus). A Neovim that quits takes its own line away. Works
--     everywhere, Windows included.
--
--  2. The fixed address (not on Windows). The first Neovim started also
--     listens at a fixed socket:
--
--       nvim --server /tmp/nvim-remote.sock --remote 'vault/inbox.org'
--
--     The ones after it find it taken and are left alone. A socket left
--     behind by a Neovim that died is removed first.
--
--  Settings:
--    vim.g.remote_address_file  the address file (default
--                               stdpath('data')/remote-address); '' or false:
--                               none is written
--    vim.g.remote_socket        the fixed address (default
--                               '/tmp/nvim-remote.sock'); '' or false: do not
--                               listen
--  Skipped when nvim runs headless (tests, scripts): no UI ever attaches.
-- =============================================================================

local M = {}

local DEFAULT = '/tmp/nvim-remote.sock'

--- The address file, or nil when it is turned off.
function M.addressFile()
  local path = vim.g.remote_address_file
  if path == nil then path = vim.fn.stdpath('data') .. '/remote-address' end
  if not path or path == '' then return nil end
  return vim.fs.normalize(vim.fn.expand(path))
end

--- Name this Neovim in the address file: it is the one in use now.
function M.register()
  local path, address = M.addressFile(), vim.v.servername
  if not path or not address or address == '' then return end
  pcall(vim.fn.writefile, { address, tostring(vim.fn.getpid()) }, path)
end

--- Take this Neovim out of the address file, if it is the one named there.
function M.unregister()
  local path = M.addressFile()
  if not path then return end
  local ok, lines = pcall(vim.fn.readfile, path)
  if ok and lines[1] == vim.v.servername then pcall(vim.uv.fs_unlink, path) end
end

--- True when a Neovim answers at `path`.
local function alive(path)
  if not vim.uv.fs_stat(path) then return false end
  local ok, chan = pcall(vim.fn.sockconnect, 'pipe', path, { rpc = true })
  if ok and type(chan) == 'number' and chan > 0 then
    pcall(vim.fn.chanclose, chan)
    return true
  end
  return false
end

function M.start()
  local path = vim.g.remote_socket
  if path == nil then path = DEFAULT end
  if not path or path == '' or path == false then return end
  if vim.fn.has('win32') == 1 then return end -- named pipes there: the address file is the way
  if alive(path) then return end              -- another Neovim owns it
  pcall(vim.uv.fs_unlink, path)               -- a stale one, or nothing
  pcall(vim.fn.serverstart, path)
end

local group = vim.api.nvim_create_augroup('Remote', { clear = true })

if #vim.api.nvim_list_uis() > 0 then
  vim.api.nvim_create_autocmd('UIEnter', { group = group, once = true, callback = M.start })
end

-- UIEnter and FocusGained never happen in a headless run, so these need no
-- check of their own. A GUI attaches after the configuration is read: UIEnter.
vim.api.nvim_create_autocmd({ 'UIEnter', 'FocusGained' }, { group = group, callback = M.register })
vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = M.unregister })
if #vim.api.nvim_list_uis() > 0 then M.register() end

return M
