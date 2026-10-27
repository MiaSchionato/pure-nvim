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

--- The first FIDO2 device `fido2-token -L` lists, or nil.
local function listedDevice()
  if vim.fn.executable('fido2-token') ~= 1 then return nil end
  local res = vim.system({ 'fido2-token', '-L' }, { text = true }):wait(5000)
  return (res.stdout or ''):match('^(/dev/[^:%s]+)')
end

--- Give the key back to Windows (see unlock).
local function detach()
  if vim.g.pure_fido2_id and vim.fn.executable('powershell.exe') == 1 then
    vim.system({ 'powershell.exe', '-NoProfile', '-Command', 'usbipd detach --hardware-id ' .. vim.g.pure_fido2_id })
  end
end

--- Mount the folder in the background (Neovim keeps working while the key
--- waits for its touch). `done(true|false)` is called when it is over.
---
--- With fido2 the key is found with `fido2-token -L`; when it is not attached to
--- WSL (no /dev/hidraw*), usbipd attaches it first (it sits on Windows' side):
--- vim.g.pure_fido2_id ('1ea8:fe29', the key's USB vendor:product, from
--- `usbipd list`; stable, unlike the port) names it. It is given back to Windows
--- right after, since the key is only needed to mount, not while mounted.
---
--- gocryptfs runs through `sh` with its output in a file: it forks into the
--- background, and a pipe it inherited would keep this call waiting for good.
--- @param cfg table  from config()
--- @param done function|nil
function M.unlock(cfg, done)
  done = done or function() end
  if M.mounted(cfg.dir) then return done(true) end
  local function fail(msg)
    vim.notify(msg, vim.log.levels.ERROR)
    done(false)
  end
  if vim.fn.executable('gocryptfs') ~= 1 then return fail('gocryptfs is not installed') end
  if vim.fn.isdirectory(cfg.cipher) ~= 1 then
    return fail('No encrypted folder at ' .. cfg.cipher .. ' (gocryptfs -init)')
  end
  vim.fn.mkdir(cfg.dir, 'p')

  local function mount(dev, attached)
    local args = { '-idle', cfg.idle, '-nosyslog' }
    local stdin
    if cfg.fido2 then
      if not dev then
        return fail('No FIDO2 key found: plug it in (or set vim.g.pure_fido2_id, see docs/notes.md)')
      end
      vim.list_extend(args, { '-fido2', dev })
      vim.notify('Touch the FIDO2 key…')
    else
      local ok, pw = pcall(vim.fn.inputsecret, 'Private password: ')
      if not ok or pw == '' then return done(false) end
      stdin = pw .. '\n'
    end
    vim.list_extend(args, { cfg.cipher, cfg.dir })

    local errfile = vim.fn.tempname()
    local cmd = { 'sh', '-c', 'exec gocryptfs "$@" >/dev/null 2>"$0"', errfile }
    vim.list_extend(cmd, args)
    vim.system(cmd, { stdin = stdin, timeout = 60000 }, function(res)
      vim.schedule(function()
        if attached then detach() end
        local ok2, lines = pcall(vim.fn.readfile, errfile)
        pcall(vim.fn.delete, errfile)
        if res.code ~= 0 or not M.mounted(cfg.dir) then
          return fail('Could not unlock: ' .. vim.trim(ok2 and table.concat(lines, '\n') or ('exit ' .. res.code)))
        end
        vim.notify('Unlocked ' .. cfg.dir .. ' (locks itself after ' .. cfg.idle .. ' idle)')
        done(true)
      end)
    end)
  end

  if not cfg.fido2 then return mount() end
  local dev = listedDevice()
  if dev then return mount(dev, false) end
  local id = vim.g.pure_fido2_id
  if not (id and vim.fn.executable('powershell.exe') == 1) then return mount(nil) end
  vim.notify('Attaching the FIDO2 key to WSL…')
  vim.system({ 'powershell.exe', '-NoProfile', '-Command', 'usbipd attach --wsl --hardware-id ' .. id }, {}, function()
    vim.defer_fn(function() mount(listedDevice(), true) end, 2500)
  end)
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

--- Whether `path` can be used now: true when it is not in an encrypted folder
--- or that folder is mounted. Otherwise false, after offering to unlock it in
--- the background; `retry` is called once it is mounted, to do again what was
--- asked.
--- @param path string
--- @param retry function|nil
function M.ensure(path, retry)
  local cfg = M.folderOf(path)
  if not cfg or M.mounted(cfg.dir) then return true end
  if vim.fn.confirm('The private folder is locked. Unlock it?', '&Yes\n&No', 1) == 1 then
    M.unlock(cfg, function(ok)
      if ok and retry then retry() end
    end)
  end
  return false
end

-- A write into the folder after it locked itself would land in the clear under
-- the empty mount point: refused (an error here cancels the write).
vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('PureCrypt', { clear = true }),
  callback = function(args)
    local name = vim.api.nvim_buf_get_name(args.buf)
    local cfg = M.folderOf(name)
    if cfg and not M.mounted(cfg.dir) then
      error('The private folder is locked: not written (:PrivateUnlock, then :w)', 0)
    end
  end,
})

-- What Neovim writes on the side would leave the note in the clear on the plain
-- disk while the folder is mounted: the swap file, the undo history and the
-- backups. None of them for a note of an encrypted folder.
vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, {
  group = vim.api.nvim_create_augroup('PureCryptNoTraces', { clear = true }),
  callback = function(args)
    if M.folderOf(vim.api.nvim_buf_get_name(args.buf)) then
      vim.opt_local.swapfile = false
      vim.opt_local.undofile = false
      vim.opt_local.backup = false
      vim.opt_local.writebackup = false
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
