-- =============================================================================
--  The vault's Obsidian fixes the links to a renamed heading
-- =============================================================================
--  In a Markdown vault a heading that a link points to carries an `id::` line.
--  The vault's Obsidian (files/config/scripts/headlinks.js there) keeps where
--  each id was in a state file ({ id: [note, title] }), and when a heading with
--  an id has a new title, or now lives in another note, it rewrites every link
--  to it. When Obsidian is open it sees a note saved here at once; when it is
--  closed it catches up the next time it starts.
--
--  This module does not rewrite those links itself (one implementation, the
--  Obsidian one). It only:
--    - notices, when a note of the vault is saved, a heading with an id whose
--      title or note is not the one of the state file (`pending`);
--    - on :VaultFixLinks, or when Neovim quits with something pending and
--      Obsidian closed, starts Obsidian on the vault, waits until it has written
--      its state file again (the end of its start: the links are fixed), and
--      closes it again (only when it was started here);
--    - after grow, compost or move of pure/vault/md.lua, which rewrite the links
--      of the heading they move, writes the heading's new note into the state
--      file while Obsidian is closed, so that is not taken for a rename.
--
--  The vault's entry in vim.g.pure_vaults names it:
--    obsidian = { vault = '<the vault's name in Obsidian>', state = 'files/config/headlinks.json' }
--  Without `obsidian` nothing here runs.
-- =============================================================================

local B = {}

local function V() return require('pure.vault') end
local function md() return require('pure.vault.md') end

-- How Obsidian is found, started and closed: replaced by the tests.
B.sys = {}

function B.sys.running()
  if vim.fn.has('win32') == 1 then
    local out = vim.fn.system({ 'tasklist', '/FI', 'IMAGENAME eq Obsidian.exe', '/NH' })
    return out:find('Obsidian.exe', 1, true) ~= nil
  end
  return vim.system({ 'pgrep', '-x', 'obsidian' }):wait().code == 0
end

function B.sys.open(name)
  local url = 'obsidian://open?vault=' .. name:gsub('[^%w%-._~]', function(c) return ('%%%02X'):format(c:byte()) end)
  if vim.fn.has('win32') == 1 then
    vim.system({ 'cmd.exe', '/c', 'start', '', url }, { detach = true })
  else
    vim.system({ 'xdg-open', url }, { detach = true })
  end
end

function B.sys.close()
  if vim.fn.has('win32') == 1 then
    vim.system({ 'taskkill', '/IM', 'Obsidian.exe' }):wait() -- a normal close, not /F: it saves its state
  else
    vim.system({ 'pkill', '-x', 'obsidian' }):wait()
  end
end

-- How long to wait for Obsidian to start and fix the links, in ms.
B.timeout = 60000

--- The Markdown vault with an `obsidian` entry, and its settings, or nil.
local function vaultOf(path)
  local v = path and V().of(path) or V().resolve('md')
  if not v or v.format ~= 'md' then return nil end
  local cfg = (vim.g.pure_vaults or {})[v.name]
  local o = type(cfg) == 'table' and cfg.obsidian
  if type(o) ~= 'table' or not o.vault then return nil end
  return v, { vault = o.vault, state = v.dir .. '/' .. (o.state or 'files/config/headlinks.json') }
end

local function readState(file)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then return {} end
  local okj, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  return okj and type(data) == 'table' and data or {}
end

local function writeState(file, state)
  if vim.tbl_isempty(state) then return end
  vim.fn.writefile({ vim.json.encode(state) }, file)
end

--- The headings with an id of `lines`: { id = title }.
function B.idsOf(lines)
  local out = {}
  local hs = md().headings(lines)
  for i, h in ipairs(hs) do
    local stop = hs[i + 1] and hs[i + 1].line - 1 or #lines
    for n = h.line + 1, stop do
      local l = lines[n]
      local id = l:match('^id::%s*(%w+)%s*$')
      if id then out[id:lower()] = h.title break end
      if not (l:match('^#[^%s#]') or l:match('^[%w_-]+::')) then break end -- past the tag and property lines
    end
  end
  return out
end

-- ids whose heading was renamed or moved by hand since Obsidian last wrote its state: { id = true }.
B.pending = {}

--- After a note of the vault was saved: its ids against the state file.
function B.check(path)
  local v, o = vaultOf(path)
  if not v then return end
  local rel = vim.fs.normalize(path):sub(#v.dir + 2)
  local state = readState(o.state)
  local cmp = md().compareKey
  for id, title in pairs(B.idsOf(vim.fn.readfile(path))) do
    local known = state[id]
    if type(known) == 'table' and (known[1] ~= rel or cmp(known[2] or '') ~= cmp(title)) then
      B.pending[id] = true
    else
      B.pending[id] = nil
    end
  end
end

--- pure/vault/md.lua moved the headings with `ids` (their titles) to the note `rel` and rewrote their links:
--- with Obsidian closed, the state file learns the new note, so it is not taken for a move to fix.
function B.moved(ids, rel)
  if vim.tbl_isempty(ids) then return end
  local v, o = vaultOf(V().dir('md') .. '/' .. rel)
  if not v or B.sys.running() then return end
  local state = readState(o.state)
  local changed = false
  for id, title in pairs(ids) do
    if state[id] then state[id] = { rel, title } changed = true end
    B.pending[id] = nil
  end
  if changed then writeState(o.state, state) end
end

--- Whether something is waiting for Obsidian.
function B.hasPending() return next(B.pending) ~= nil end

--- Have Obsidian fix the links now: start it on the vault when it is closed, wait until its state file is written
--- again, close it again. With Obsidian open there is nothing to do: it sees the saved notes itself.
function B.fix(opts)
  opts = opts or {}
  local v, o = vaultOf()
  if not v then
    if not opts.quiet then vim.notify('Vault: no Markdown vault with an obsidian entry in vim.g.pure_vaults', vim.log.levels.WARN) end
    return false
  end
  if B.sys.running() then
    B.pending = {}
    if not opts.quiet then vim.notify('Vault: Obsidian is open, it fixes the links itself') end
    return true
  end
  local stat = vim.uv.fs_stat(o.state)
  local before = stat and stat.mtime.sec + stat.mtime.nsec / 1e9 or 0
  vim.notify('Vault: Obsidian fixes the links…')
  B.sys.open(o.vault)
  local done = vim.wait(B.timeout, function()
    local s = vim.uv.fs_stat(o.state)
    return s ~= nil and (s.mtime.sec + s.mtime.nsec / 1e9) > before
  end, 200)
  -- A moment for the last writes after the state file, then close it.
  vim.wait(1000, function() return false end)
  B.sys.close()
  if not done then
    vim.notify('Vault: Obsidian did not finish in time; it fixes the links the next time it starts', vim.log.levels.WARN)
    return false
  end
  B.pending = {}
  vim.notify('Vault: links fixed')
  return true
end

local group = vim.api.nvim_create_augroup('PureVaultObsidian', { clear = true })
vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  pattern = '*.md',
  callback = function(args) pcall(B.check, vim.api.nvim_buf_get_name(args.buf)) end,
})
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = group,
  callback = function()
    if B.hasPending() then pcall(B.fix, { quiet = true }) end
  end,
})
vim.api.nvim_create_user_command('VaultFixLinks', function() B.fix() end,
  { desc = 'Have the vault\'s Obsidian fix the links to renamed headings (starts it, then closes it)' })

return B
