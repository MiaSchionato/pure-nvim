-- =============================================================================
--  The vaults: folders of notes, org or Markdown (<leader>v)
-- =============================================================================
--  What the <leader>v group does with a vault, the way Doom's `SPC v` does (the
--  Emacs side is C:\doom\config\config.el and .config\emacs\lisp\org-vault.el):
--
--    f  find a note, a heading, an alias; a new title makes a seed
--    F  find a file of the vault
--    g  grep the vault
--    q  quick capture (the template menu)
--    n  grow the idea (SEED > SPROUT > PLANT > TREE; a seed of the inbox moves to the nursery, a sprout to a note of its own)
--    c  compost the idea (moved to the compost note; nothing is erased)
--    m  move this heading to another note (the sources/ note of its type, or one picked in the list)
--    t  state menu                     a  the agenda (its menu)
--    N  new note in its own file       i  insert a link to a note
--    b  backlinks                      r  rename this note (title and file)
--    d  delete this note (to the trash folder, nothing is erased)
--    j  journal line (today)           J  today in the journal
--    e  explore the vault              s  save the notes and commit (sync when there is an upstream)
--    p  preview the linked note
--
--  The vaults are the setting vim.g.pure_vaults (configs.lua), one entry each:
--
--    g.pure_vaults = {
--      <name> = {
--        dir = '~/folder',          the folder
--        format = 'org' | 'md',     what its notes are written in
--        notes = { inbox = 'inbox', nursery = 'garden/nursery', ... },
--                                   the notes by name, from the folder, without the
--                                   extension (the format gives it); a name ending in
--                                   '/' is a folder. A name left out keeps the default
--                                   below (NOTE_DEFAULTS).
--        readonly = true,           nothing writes into it (find, grep, open still work)
--      },
--    }
--    g.pure_vault_default = '<name>'  the vault outside of every vault's folder
--
--  The vault of a command is the one holding the current buffer, else the
--  default. Without g.pure_vaults the older single-vault settings still work:
--  g.pure_vault (the folder, an org vault), g.orgls_inbox, g.pure_vault_notes.
--
--  This module does what is the same for every format (the settings, find's
--  list, the file picker, grep, explore, delete, sync); what is a format's own
--  is in pure/vault/<format>.lua (pure/vault/org.lua: org.nvim, :ID: links).
-- =============================================================================

local M = {}

local function warn(msg) vim.notify('Vault: ' .. msg, vim.log.levels.WARN) end

-- -----------------------------------------------------------------------------
--  The settings
-- -----------------------------------------------------------------------------

--- The notes one opens often, and the folders the commands use, from the vault's folder, without the extension.
local NOTE_DEFAULTS = {
  inbox    = 'inbox',
  -- Where the sprouts grow (garden/<year>.org until 2026-11-08). Plants, trees and fruits have a note of
  -- their own in the garden folder.
  nursery  = 'garden/nursery',
  tasks    = 'tasks',
  journal  = 'journal',
  compost  = 'archive/compost',
  books    = 'sources/books',
  quotes   = 'sources/quotes',
  concepts = 'sources/concepts',
  -- Folders.
  garden   = 'garden/',
  sources  = 'sources/',
  trash    = 'archive/trash/',
}
M.NOTE_DEFAULTS = NOTE_DEFAULTS

local function normDir(dir)
  local d = vim.fs.normalize(vim.fn.expand(dir))
  return (d:gsub('(.)/+$', '%1'))
end

local function key(path)
  local p = vim.fs.normalize(vim.uv.fs_realpath(path) or path)
  if vim.fn.has('win32') == 1 then p = p:lower() end
  return p
end

--- One vault of the settings, made whole.
local function entry(name, v)
  if type(v) ~= 'table' or not v.dir or v.dir == '' then return nil end
  local format = v.format or 'org'
  if format ~= 'org' and format ~= 'md' then
    warn(('vault %s: format must be org or md, not %s'):format(name, tostring(format)))
    return nil
  end
  return { name = name, dir = normDir(v.dir), format = format, notes = v.notes or {}, readonly = v.readonly == true }
end

--- Every vault of the settings, the default one first (then by name).
function M.list()
  local cfg = vim.g.pure_vaults
  local out = {}
  if type(cfg) == 'table' and next(cfg) then
    local names = vim.tbl_keys(cfg)
    local default = vim.g.pure_vault_default
    table.sort(names, function(a, b)
      if (a == default) ~= (b == default) then return a == default end
      return a < b
    end)
    for _, name in ipairs(names) do out[#out + 1] = entry(name, cfg[name]) end
    return out
  end
  -- The older settings: one org vault.
  local dir = vim.g.pure_vault
  if not dir or dir == '' then
    local ok, zet = pcall(require, 'pure.zettelkasten')
    dir = ok and zet.vaultPath() or nil
  end
  if not dir or dir == '' then return out end
  local notes = vim.deepcopy(type(vim.g.pure_vault_notes) == 'table' and vim.g.pure_vault_notes or {})
  notes.inbox = vim.g.orgls_inbox or notes.inbox
  out[1] = entry('vault', { dir = dir, format = 'org', notes = notes })
  return out
end

--- The vault named `name`, or nil.
function M.get(name)
  for _, v in ipairs(M.list()) do if v.name == name then return v end end
end

--- The vault whose folder holds `path` (the deepest one when folders nest), or nil.
function M.of(path)
  if not path or path == '' then return nil end
  local p = key(path)
  local best
  for _, v in ipairs(M.list()) do
    local d = key(v.dir)
    if (p == d or p:sub(1, #d + 1) == d .. '/') and (not best or #v.dir > #best.dir) then best = v end
  end
  return best
end

--- The vault of the current buffer, else the default one.
function M.current(buf)
  local name = vim.api.nvim_buf_get_name(buf or 0)
  return M.of(name) or M.list()[1]
end

--- A vault: `which` is a vault, a format ('org' / 'md': the current vault when it is one, else the first of
--- that format), or nil (the current vault).
local function resolve(which)
  if type(which) == 'table' then return which end
  if which == nil then return M.current() end
  local cur = M.current()
  if cur and cur.format == which then return cur end
  for _, v in ipairs(M.list()) do if v.format == which then return v end end
end
M.resolve = resolve

--- The folder of the configured vault of `format` (or of the default vault), from g.pure_vaults only: no
--- question, no remembered answer. For pure/zettelkasten.lua, which falls back to its own answers.
function M.configuredDir(format)
  local cfg = vim.g.pure_vaults
  if type(cfg) ~= 'table' or not next(cfg) then return nil end
  local list = M.list()
  if not format then return list[1] and list[1].dir end
  for _, v in ipairs(list) do if v.format == format then return v.dir end end
end

--- The folder of the vault (see resolve), or nil. No check, no warning.
function M.dir(which)
  local v = resolve(which)
  return v and v.dir or nil
end

--- The folder of the vault, or nil (with a warning) when there is none or it is not there.
function M.path(which)
  local dir = M.dir(which)
  if not dir then
    warn('no vault folder: set vim.g.pure_vaults')
    return nil
  end
  if vim.fn.isdirectory(dir) == 0 then
    warn('folder not found: ' .. dir)
    return nil
  end
  return dir
end

--- Whether `path` is inside the vault (`which` as in resolve; nil: any vault).
function M.contains(which, path)
  if path == nil then which, path = nil, which end
  if not path or path == '' then return false end
  local v = M.of(path)
  if not v then return false end
  if which == nil then return true end
  local want = resolve(which)
  return want ~= nil and want.name == v.name
end

--- The path of the note `name` from the vault's folder (with the format's extension; a folder ends in '/'),
--- or nil for an unknown name. `which` as in resolve.
function M.note(name, which)
  local v = resolve(which)
  local rel = (v and v.notes[name]) or NOTE_DEFAULTS[name]
  if not rel then return nil end
  if rel:sub(-1) == '/' then return rel end
  rel = rel:gsub('%.org$', ''):gsub('%.md$', '')
  return rel .. '.' .. (v and v.format or 'org')
end

--- The inbox: the note where new things land.
function M.inbox(which) return M.note('inbox', which) end
--- The nursery, where grow moves a sprout.
function M.nursery(which) return M.note('nursery', which) end

--- The module of the vault's format: pure/vault/org.lua or pure/vault/md.lua.
function M.backend(v)
  v = resolve(v)
  return v and require('pure.vault.' .. v.format) or nil
end

-- -----------------------------------------------------------------------------
--  The commands of a format: they run in the current vault's module
-- -----------------------------------------------------------------------------
--- A command `name` of the format's module; `writes` ones refuse a read-only vault.
local function command(name, writes)
  return function(...)
    local v = M.current()
    if not v then return warn('no vault folder: set vim.g.pure_vaults') end
    if writes and v.readonly then return warn(v.name .. ' is read-only') end
    local fn = require('pure.vault.' .. v.format)[name]
    if not fn then return warn(('%s is not there for %s vaults yet'):format(name, v.format)) end
    return fn(...)
  end
end

M.newNote = command('newNote', true)
M.insertLink = command('insertLink', true)
M.backlinks = command('backlinks')
M.capture = command('capture', true)
M.newSeed = command('newSeed', true)
M.journalLine = command('journalLine', true)
M.journalToday = command('journalToday')
M.todoState = command('todoState', true)
M.agenda = command('agenda')
M.rename = command('rename', true)
M.preview = command('preview')
M.closePreview = function() for _, f in ipairs({ 'org', 'md' }) do
  local ok, b = pcall(require, 'pure.vault.' .. f)
  if ok and b.closePreview then b.closePreview() end
end end
M.grow = command('grow', true)
M.compost = command('compost', true)
M.move = command('move', true)
M.editLinkedNote = function(...) return require('pure.vault.org').editLinkedNote(...) end

-- The org capture's store filter (lua/plugins/org.lua) and its source notes: org's own.
M.routeNode = function(...) return require('pure.vault.org').routeNode(...) end
M.sourceFile = function(...) return require('pure.vault.org').sourceFile(...) end

-- -----------------------------------------------------------------------------
--  Find (<leader>vf): notes, headings and aliases in one picker
-- -----------------------------------------------------------------------------
--  A port of Doom's `SPC v f` (C:\doom\config\vault-open.el), with its colours:
--    a note reads     Note name                      (a file, or its title)
--    a heading reads  Note name › Heading            (the note dimmer, the heading in the colour of its level)
--    an alias reads   Alias → Note name › Heading    (the alias in its own colour, italic)
--  and on the right, dim, the path from the root of the vault and how long ago the note was written.
--  Order: every note (and its aliases) first, the notes written last first, then the headings (and their aliases) in the same order, `archive/` always last: the name of a note weighs more than a word inside it.
--  Enter opens the note (at the heading); a title that matches nothing makes a seed in the inbox.
--  The colours are pure/notecolors.lua's (PureNoteFile, PureNoteAlias, PureNoteSep, the heading colours).
--  How a note is read (its files, title, headings, aliases) is the format's: backend.files / backend.parse.

local ESC = string.char(27)

--- Every entry of the vault at `root` in the default order.
local function findEntries(root)
  local v = M.of(root) or M.list()[1]
  local b = M.backend(v or 'org')
  local groups = {}
  for _, f in ipairs(b.files(root)) do
    local info = b.parse(f.path)
    local archive = f.rel:match('^archive/') ~= nil
    local note = info.title or vim.fn.fnamemodify(f.rel, ':t:r')
    local base = { file = f.path, path = f.rel, mtime = info.mtime, archive = archive, note = note }
    -- What is in the name of the note (the note and its aliases) apart from what is inside it (headings).
    local top = { vim.tbl_extend('force', base, { kind = 'note', title = note, lnum = 1 }) }
    for _, a in ipairs(info.aliases) do
      top[#top + 1] = vim.tbl_extend('force', base, { kind = 'alias', title = a, target = note, lnum = 1 })
    end
    local inside = {}
    for _, h in ipairs(info.headings) do
      inside[#inside + 1] = vim.tbl_extend('force', base, { kind = 'heading', title = h.text, level = h.level, lnum = h.lnum })
      for _, a in ipairs(h.aliases) do
        inside[#inside + 1] = vim.tbl_extend('force', base,
          { kind = 'alias', title = a, target = h.text, level = h.level, lnum = h.lnum, heading = true })
      end
    end
    groups[#groups + 1] = { archive = archive, mtime = info.mtime, top = top, inside = inside }
  end
  table.sort(groups, function(a, b)
    if a.archive ~= b.archive then return not a.archive end
    return a.mtime > b.mtime
  end)
  -- The name of a note weighs more than a word inside it: every note (and alias of a note) comes before any
  -- heading, so on equal matches (fzf keeps the order of the list) a note is above the headings of its own or of
  -- another note whose line also holds the typed name; the notes written last first in each part, `archive/`
  -- last of all (its notes, then its headings).
  local out = {}
  for _, archive in ipairs({ false, true }) do
    for _, g in ipairs(groups) do
      if g.archive == archive then vim.list_extend(out, g.top) end
    end
    for _, g in ipairs(groups) do
      if g.archive == archive then vim.list_extend(out, g.inside) end
    end
  end
  return out
end

local function trunc(text, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  while vim.fn.strdisplaywidth(text) > width - 1 and #text > 0 do
    text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
  end
  return text .. '…'
end

local function truncLeft(text, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  while vim.fn.strdisplaywidth(text) > width - 1 and #text > 0 do
    text = vim.fn.strcharpart(text, 1)
  end
  return '…' .. text
end

--- Dired's way of saying how long ago: now, 37m ago, 1h 37m ago, 1d 17h ago, 23d ago.
local function age(mtime)
  local secs = math.max(0, os.time() - mtime)
  local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
  if secs < 60 then return 'now' end
  if secs < 3600 then return m .. 'm ago' end
  if secs < 86400 then return h .. 'h ' .. m .. 'm ago' end
  if d < 10 then return d .. 'd ' .. h .. 'h ago' end
  return d .. 'd ago'
end

--- `text` in the foreground of highlight group `group` (ANSI truecolor); `extra` adds attributes ("3;" italic).
local function paint(group, text, extra)
  local n = vim.api.nvim_get_hl(0, { name = group, link = false }).fg
  if not n then return text end
  return string.format('%s[%s38;2;%d;%d;%dm%s%s[0m', ESC, extra or '', math.floor(n / 65536), math.floor(n / 256) % 256, n % 256, text, ESC)
end

local function levelGroup(level)
  return '@markup.heading.' .. math.min(level or 1, 6) .. '.markdown'
end

--- One line of the list: the coloured text, then (after tabs) the file and the line, which fzf does not show.
local function findLine(e)
  local noteGroup = e.archive and 'PureNoteSep' or 'PureNoteFile'
  local sep = paint('PureNoteSep', ' › ')
  local arrow = paint('PureNoteSep', '  → ')
  local visible
  if e.kind == 'note' then
    visible = paint(noteGroup, trunc(e.title, 60))
  elseif e.kind == 'heading' then
    visible = paint(noteGroup, trunc(e.note, 26)) .. sep .. paint(levelGroup(e.level), trunc(e.title, 44))
  elseif e.heading then
    visible = paint('PureNoteAlias', trunc(e.title, 30), '3;') .. arrow
      .. paint(noteGroup, trunc(e.note, 22)) .. sep .. paint(levelGroup(e.level), trunc(e.target, 40))
  else
    visible = paint('PureNoteAlias', trunc(e.title, 30), '3;') .. arrow .. paint(noteGroup, trunc(e.target, 40))
  end
  local width = vim.fn.strdisplaywidth((visible:gsub(ESC .. '%[[%d;]*m', '')))
  local meta = string.format('%s  %11s', truncLeft(e.path, 36), age(e.mtime))
  return table.concat({ visible .. string.rep(' ', math.max(70 - width, 2)) .. paint('PureNoteSep', meta), e.file, e.lnum }, '\t')
end

--- A new seed called `title` in the inbox of the current vault, then open it (the format writes it).
local function newSeed(title)
  local v = M.current()
  if not v then return warn('no vault folder: set vim.g.pure_vaults') end
  if v.readonly then return warn(v.name .. ' is read-only') end
  return M.backend(v).newTitle(title)
end

function M.find()
  local root = M.path()
  if not root then return end
  require('pure.notecolors').apply()
  local lines = {}
  for _, e in ipairs(findEntries(root)) do lines[#lines + 1] = findLine(e) end
  require('pure.fuzzyUtils').pickList(lines, {
    title = ' Vault ',
    ratio = 0.8,
    -- Enter on a title that matches nothing returns the query itself (no tab in it): a new seed.
    fzf = "--ansi --delimiter '\\t' --with-nth 1 --tiebreak=index --bind enter:accept-or-print-query",
  }, function(selection)
    local file, lnum = selection:match('\t([^\t]+)\t(%d+)%s*$')
    if not file then
      local title = vim.trim(selection)
      if title ~= '' then newSeed(title) end
      return
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(file))
    pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(lnum), 0 })
    vim.cmd('normal! zvzz')
  end)
end

-- Exposed for tests (and pure/links.lua).
M._find = { entries = findEntries, line = findLine, newSeed = newSeed }

function M.findFile()
  local dir = M.path()
  if dir then require('pure.fuzzyUtils').fuzzySearch(dir) end
end

function M.grep()
  local dir = M.path()
  if dir then require('pure.fuzzyUtils').fuzzyGrep(dir) end
end

function M.explore()
  local oil = require('oil')
  if vim.w.is_oil_win then return oil.close() end
  local dir = M.path()
  if dir then oil.open_float(dir) end
end

-- -----------------------------------------------------------------------------
--  Delete
-- -----------------------------------------------------------------------------
--- Move this note to the vault's trash folder (archive/trash/; nothing is erased).
function M.delete()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local v = M.of(path)
  if not v or vim.bo[buf].buftype ~= '' then return warn('this buffer is not a note of the vault') end
  if v.readonly then return warn(v.name .. ' is read-only') end
  local rel = M.note('trash', v)
  local name = vim.fn.fnamemodify(path, ':t')
  if vim.fn.confirm('Move ' .. name .. ' to ' .. rel .. '?', '&Yes\n&No', 2) ~= 1 then return end
  local trash = v.dir .. '/' .. rel:gsub('/$', '')
  vim.fn.mkdir(trash, 'p')
  local dest = trash .. '/' .. name
  -- Do not overwrite an older note of the same name in the trash.
  if vim.uv.fs_stat(dest) then dest = trash .. '/' .. os.date('%Y%m%d%H%M%S') .. '-' .. name end
  vim.cmd('silent! write')
  local ok, err = vim.uv.fs_rename(path, dest)
  if not ok then return warn('could not move the note: ' .. tostring(err)) end
  vim.cmd('silent! bwipeout! ' .. buf)
  local b = M.backend(v)
  if b.afterMove then b.afterMove() end
  vim.notify('Moved to ' .. rel)
end

-- -----------------------------------------------------------------------------
--  Sync
-- -----------------------------------------------------------------------------
--- Save the notes of the vault and commit; with an upstream, pull and push too
--- (pure/vaultsync.lua). The vault may have no remote: then it stays a commit.
function M.sync()
  local v = M.current()
  local dir = M.path(v)
  if not dir then return end
  local up = vim.system({ 'git', '-C', dir, 'rev-parse', '--abbrev-ref', '@{u}' }, { text = true }):wait()
  if up.code == 0 then return require('pure.vaultsync').sync(dir) end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if vim.bo[b].modified and vim.bo[b].buftype == '' and M.contains(v, name) then
      vim.api.nvim_buf_call(b, function() vim.cmd('silent write') end)
    end
  end
  vim.system({ 'git', '-C', dir, 'add', '-A' }, { text = true }, function()
    vim.system({ 'git', '-C', dir, 'commit', '-m',
      ('Sync from %s, %s'):format(vim.uv.os_gethostname(), os.date('%Y-%m-%d %H:%M')) }, { text = true },
      function(res)
        vim.schedule(function()
          if res.code == 0 then vim.notify('Vault: committed (no upstream, nothing pushed)')
          elseif (res.stdout or ''):find('nothing %a* ?to commit') then vim.notify('Vault: nothing to commit')
          else warn('commit failed: ' .. vim.trim((res.stderr or '') .. (res.stdout or ''))) end
        end)
      end)
  end)
end

return M
