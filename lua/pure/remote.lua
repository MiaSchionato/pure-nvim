-- =============================================================================
--  Remote
-- =============================================================================
--  One Neovim answers at a fixed address, so something outside (the Flow
--  Launcher plugin "nv") can open a file in it instead of starting another:
--
--    nvim --server /tmp/nvim-atlas.sock --remote 'Atlas/0-Inbox/Note.md'
--
--  The first Neovim started owns the address; the ones after it find it
--  taken and are left alone (they are still reachable by their own
--  `:echo v:servername`). A socket left behind by a Neovim that died is
--  removed first.
--
--  Settings:
--    vim.g.remote_socket   the address (default '/tmp/nvim-atlas.sock');
--                          '' or false: do not listen
--  Skipped when nvim runs headless (tests, scripts).
-- =============================================================================

local M = {}

local DEFAULT = '/tmp/nvim-atlas.sock'

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
  if vim.fn.has('win32') == 1 then return end -- named pipes there: not this
  if alive(path) then return end              -- another Neovim owns it
  pcall(vim.uv.fs_unlink, path)               -- a stale one, or nothing
  pcall(vim.fn.serverstart, path)
end

if #vim.api.nvim_list_uis() > 0 then
  vim.api.nvim_create_autocmd('UIEnter', {
    group = vim.api.nvim_create_augroup('Remote', { clear = true }),
    once = true,
    callback = M.start,
  })
end

return M
