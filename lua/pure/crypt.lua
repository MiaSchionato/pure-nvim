-- =============================================================================
--  Encrypted outside folders (gocryptfs)
-- =============================================================================
--  A folder of vim.g.pure_outside_folders (pure/notes.lua) can be written as a
--  table instead of a path:
--
--    vim.g.pure_outside_folders = {
--      ['6-Private'] = { dir = '~/Private', cipher = '~/.Private.enc', idle = '5m', fido2 = true },
--    }
--
--  `cipher` holds the encrypted files (gocryptfs -init made it); `dir` is where
--  it shows up in the clear once mounted. `idle` unmounts it by itself after
--  that long without use, so the notes only exist in the clear while they are
--  in use. `fido2 = true` unlocks it with the FIDO2 key (hmac-secret, a touch)
--  instead of a typed password.
--
--  Unmounted, `dir` is an empty folder: writing there would put a note on the
--  disk in the clear, under the mount point. Everything that opens, makes or
--  writes a note in such a folder asks here first (guard), and a write that
--  finds it unmounted is refused (BufWritePre). Linux only: elsewhere the
--  folder is taken as a plain one.
-- =============================================================================

local M = {}

local function expand(p) return (vim.fs.normalize(p):gsub('/+$', '')) end

--- The settings of the folder called `name` when it is encrypted, else nil:
--- { dir, cipher, idle, fido2 }, paths expanded.
--- @param name string
function M.config(name)
  if vim.fn.has('linux') ~= 1 then return nil end
  local v = (vim.g.pure_outside_folders or {})[name]
  if type(v) ~= 'table' or not v.cipher then return nil end
  return { dir = expand(v.dir), cipher = expand(v.cipher), idle = v.idle or '5m', fido2 = v.fido2 == true }
end

--- Whether a gocryptfs filesystem is mounted on `dir`.
--- @param dir string
function M.mounted(dir)
  local ok, lines = pcall(vim.fn.readfile, '/proc/mounts')
  if not ok then return false end
  local want = expand(dir)
  for _, l in ipairs(lines) do
    local mp, fstype = l:match('^%S+ (%S+) (%S+)')
    if mp and expand((mp:gsub('\\040', ' '))) == want and fstype:find('fuse', 1, true) then return true end
  end
  return false
end

--- The encrypted folder (settings) that holds `path`, or nil.
--- @param path string
function M.folderOf(path)
  if not path or path == '' then return nil end
  local p = expand(path)
  for name in pairs(vim.g.pure_outside_folders or {}) do
    local cfg = M.config(name)
    if cfg and (p == cfg.dir or p:sub(1, #cfg.dir + 1) == cfg.dir .. '/') then return cfg, name end
  end
end

--- The first FIDO2 device `fido2-token -L` lists, or nil. When the key is not
--- attached to WSL (no /dev/hidraw*), attach it first with usbipd, which sits on
--- Windows' side: vim.g.pure_fido2_id ('1ea8:fe29', the key's USB vendor:product,
--- from `usbipd list`; stable, unlike the port) names it. The second result is
--- true when this call attached it, so unlock() can give it back to Windows: the
--- key is only needed to mount, not while it is mounted.
local function fidoDevice()
  local function listed()
    if vim.fn.executable('fido2-token') ~= 1 then return nil end
    local res = vim.system({ 'fido2-token', '-L' }, { text = true }):wait(5000)
    return (res.stdout or ''):match('^(/dev/[^:%s]+)')
  end
  local dev = listed()
  if dev then return dev, false end
  local id = vim.g.pure_fido2_id
  if id and vim.fn.executable('powershell.exe') == 1 then
    vim.system({ 'powershell.exe', '-NoProfile', '-Command', 'usbipd attach --wsl --hardware-id ' .. id }):wait(15000)
    vim.wait(2500)
    return listed(), true
  end
end

--- Mount the folder (asks for the FIDO2 touch, or a password). True when it is
--- mounted afterwards.
--- @param cfg table  from config()
function M.unlock(cfg)
  if M.mounted(cfg.dir) then return true end
  if vim.fn.executable('gocryptfs') ~= 1 then
    vim.notify('gocryptfs is not installed', vim.log.levels.ERROR)
    return false
  end
  if vim.fn.isdirectory(cfg.cipher) ~= 1 then
    vim.notify('No encrypted folder at ' .. cfg.cipher .. ' (gocryptfs -init)', vim.log.levels.ERROR)
    return false
  end
  vim.fn.mkdir(cfg.dir, 'p')

  local cmd = { 'gocryptfs', '-idle', cfg.idle, '-nosyslog' }
  local stdin
  local attachedHere = false
  -- Back to Windows once the mount is done (or failed), if this call took it.
  local function giveBack()
    if attachedHere and vim.g.pure_fido2_id then
      vim.system({ 'powershell.exe', '-NoProfile', '-Command', 'usbipd detach --hardware-id ' .. vim.g.pure_fido2_id }):wait(15000)
    end
  end
  if cfg.fido2 then
    local dev, attached = fidoDevice()
    attachedHere = attached
    if not dev then
      giveBack()
      vim.notify('No FIDO2 key found: plug it in (or set vim.g.pure_fido2_id, see docs/notes.md)', vim.log.levels.ERROR)
      return false
    end
    vim.list_extend(cmd, { '-fido2', dev })
    vim.notify('Touch the FIDO2 key…')
    vim.cmd('redraw')
  else
    local ok, pw = pcall(vim.fn.inputsecret, 'Private password: ')
    if not ok or pw == '' then return false end
    stdin = pw .. '\n'
  end
  vim.list_extend(cmd, { cfg.cipher, cfg.dir })

  local res = vim.system(cmd, { text = true, stdin = stdin }):wait(60000)
  giveBack()
  if res.code ~= 0 or not M.mounted(cfg.dir) then
    vim.notify('Could not unlock: ' .. vim.trim((res.stderr or '') .. (res.stdout or '')), vim.log.levels.ERROR)
    return false
  end
  vim.notify('Unlocked ' .. cfg.dir .. ' (locks itself after ' .. cfg.idle .. ' idle)')
  return true
end

--- Unmount now.
--- @param cfg table
function M.lock(cfg)
  if not M.mounted(cfg.dir) then return true end
  local tool = vim.fn.executable('fusermount3') == 1 and 'fusermount3' or 'fusermount'
  local res = vim.system({ tool, '-u', cfg.dir }, { text = true }):wait(10000)
  if res.code ~= 0 then
    vim.notify('Could not lock (a file is open?): ' .. vim.trim(res.stderr or ''), vim.log.levels.WARN)
    return false
  end
  vim.notify('Locked ' .. cfg.dir)
  return true
end

--- Make sure `path` can be used: true when it is not in an encrypted folder or
--- that folder is mounted; else offers to unlock it and returns the result.
--- @param path string
function M.guard(path)
  local cfg = M.folderOf(path)
  if not cfg or M.mounted(cfg.dir) then return true end
  if vim.fn.confirm('The private folder is locked. Unlock it?', '&Yes\n&No', 1) ~= 1 then return false end
  return M.unlock(cfg)
end

-- A write into the folder after it locked itself would land in the clear under
-- the empty mount point: refused (an error here cancels the write).
vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('PureCrypt', { clear = true }),
  callback = function(args)
    local cfg = M.folderOf(vim.api.nvim_buf_get_name(args.buf))
    if cfg and not M.mounted(cfg.dir) and not M.guard(vim.api.nvim_buf_get_name(args.buf)) then
      error('The private folder is locked: not written (:PrivateUnlock, then :w)', 0)
    end
  end,
})

--- The settings for the commands: the first encrypted folder.
local function first()
  local names = vim.tbl_keys(vim.g.pure_outside_folders or {})
  table.sort(names)
  for _, n in ipairs(names) do
    local cfg = M.config(n)
    if cfg then return cfg end
  end
  vim.notify('No encrypted outside folder set (vim.g.pure_outside_folders)', vim.log.levels.WARN)
end

vim.api.nvim_create_user_command('PrivateUnlock', function()
  local cfg = first()
  if cfg then M.unlock(cfg) end
end, { desc = 'Mount the encrypted private folder' })
vim.api.nvim_create_user_command('PrivateLock', function()
  local cfg = first()
  if cfg then M.lock(cfg) end
end, { desc = 'Unmount the encrypted private folder now' })

return M
