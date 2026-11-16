-- =============================================================================
--  The vault: the org notes (<leader>v)
-- =============================================================================
--  The vault is a folder of org notes (it was Markdown once). This module holds what the
--  <leader>v group does with it, the way Doom's `SPC v` does (the Emacs side is
--  C:\doom\config\config.el and .config\emacs\lisp\org-vault.el):
--
--    f  find a node (a file, a headline with an :ID:, an alias); a new title makes a note
--    F  find a file of the vault
--    g  grep the vault
--    q  quick capture (the template menu: node, task, link, journal; a node goes where its :TYPE: says)
--    n  grow the idea (SEED > SPROUT > PLANT > TREE; a seed of the inbox moves to the nursery, a sprout to a note of its own)
--    c  compost the idea (COMPOST, moved to archive/compost.org; nothing is erased)
--    m  move this heading to another note (the sources/ note of its :TYPE:, or one picked in the fzf list)
--    t  TODO state menu (the states of this note)   a  the agenda (its menu)
--    N  new note in its own file       i  insert a link to a node
--    b  backlinks                      r  rename this note (title and file)
--    d  delete this note (to archive/trash/, nothing is erased)
--    j  journal line (today)           J  today in the journal
--    e  explore the vault              s  save the notes and commit (sync when there is an upstream)
--    p  preview the linked note
--
--  Changed 2026-11-08 (Mia): the capture menu was <leader>vt and is now
--  <leader>vq; n (grow) and c (compost) are Doom's `SPC v n` / `SPC v c`; a new
--  seed is the quick capture's `n` (n was "new seed" before). The quick edit of
--  the linked note (it was <leader>vq) was removed.
--
--  Notes link to each other by :ID: (org-roam), so renaming or moving a file
--  breaks no link. The nodes come from org.nvim's roam extension
--  (lua/plugins/org.lua); this module only asks it. The folder is the one
--  setting vim.g.pure_vault (configs.lua), else the answer the Markdown note
--  engine remembered (pure/zettelkasten.lua).
-- =============================================================================

local M = {}

local function warn(msg) vim.notify('Vault: ' .. msg, vim.log.levels.WARN) end

--- The inbox: the note where new things land (seeds, links, sources with no type), from the vault's root.
--- The setting vim.g.orgls_inbox (configs.lua); it was seedbed.org from 2026-11-08 to 2026-11-09.
function M.inbox() return vim.g.orgls_inbox or 'inbox.org' end
--- The notes one opens often, by name, from the vault's root: the setting vim.g.pure_vault_notes (configs.lua);
--- a name it leaves out keeps the default here.
local NOTE_DEFAULTS = {
  -- Where the sprouts grow (garden/<year>.org until 2026-11-08). Plants, trees and fruits have a note of
  -- their own in garden/.
  nursery  = 'garden/nursery.org',
  tasks    = 'tasks.org',
  books    = 'sources/books.org',
  quotes   = 'sources/quotes.org',
  concepts = 'sources/concepts.org',
}

--- The path of the note `name` from the vault's root ('inbox' is M.inbox()), or nil for an unknown name.
function M.note(name)
  if name == 'inbox' then return M.inbox() end
  local notes = vim.g.pure_vault_notes
  return (type(notes) == 'table' and notes[name]) or NOTE_DEFAULTS[name]
end

--- The nursery, where grow moves a sprout.
function M.nursery() return M.note('nursery') end

--- The vault folder (normalized), or nil when no setting names one. No check, no warning.
function M.dir()
  local dir = vim.g.pure_vault
  if not dir or dir == '' then
    local ok, zet = pcall(require, 'pure.zettelkasten')
    dir = ok and zet.vaultPath() or nil
  end
  if not dir or dir == '' then return nil end
  return vim.fs.normalize(vim.fn.expand(dir))
end

--- The vault folder, or nil (with a warning) when it is not there.
function M.path()
  local dir = M.dir()
  if not dir then
    warn('no vault folder: set vim.g.pure_vault')
    return nil
  end
  if vim.fn.isdirectory(dir) == 0 then
    warn('folder not found: ' .. dir)
    return nil
  end
  return dir
end

--- Run an `:Org ...` command, saying so when org.nvim is not there.
local function org(cmd)
  return function()
    if vim.fn.exists(':Org') == 0 then return warn('org.nvim is not loaded') end
    vim.cmd('Org ' .. cmd)
  end
end

local function roamDb()
  local ok, db = pcall(require, 'org.extensions.roam.db')
  if not ok then warn('the roam extension is not loaded') return nil end
  return db
end

local function inVault(path)
  local dir = M.path()
  if not dir or path == '' then return false end
  -- Real paths: the same folder can be spelled with a short (8.3) or a long name.
  local p = vim.fs.normalize(vim.uv.fs_realpath(path) or path)
  local d = vim.fs.normalize(vim.uv.fs_realpath(dir) or dir)
  if vim.fn.has('win32') == 1 then p, d = p:lower(), d:lower() end
  return p:sub(1, #d + 1) == d .. '/'
end

local function syncIndex()
  if vim.fn.exists(':Org') == 2 then pcall(vim.cmd, 'Org roam_db_sync') end
end

-- -----------------------------------------------------------------------------
--  Finding, making
-- -----------------------------------------------------------------------------
-- -----------------------------------------------------------------------------
--  Find (<leader>vf): notes, headings and aliases in one picker
-- -----------------------------------------------------------------------------
--  A port of Doom's `SPC v f` (C:\doom\config\vault-open.el), with its colours:
--    a note reads     Note name                      (a file, or its #+title)
--    a heading reads  Note name › Heading            (the note dimmer, the heading in the colour of its level)
--    an alias reads   Alias → Note name › Heading    (the alias in its own colour, italic)
--  and on the right, dim, the path from the root of the vault and how long ago the note was written.
--  Order: every note (and its aliases) first, the notes written last first, then the headings (and their aliases) in the same order, `archive/` always last: the name of a note weighs more than a word inside it.
--  Enter opens the note (at the heading); a title that matches nothing makes a seed in the inbox.
--  The colours are pure/notecolors.lua's (PureNoteFile, PureNoteAlias, PureNoteSep, the heading colours).

local FIND_MAX_LEVEL = 4
local ESC = string.char(27)

local parsed = {} -- file -> { mtime, title, aliases, headings = { { level, text, lnum, aliases } } }

local function parseFile(path)
  local stat = vim.uv.fs_stat(path)
  local hit = parsed[path]
  if hit and stat and hit.mtime == stat.mtime.sec then return hit end
  local ok, lines = pcall(vim.fn.readfile, path)
  local info = { mtime = stat and stat.mtime.sec or 0, title = nil, aliases = {}, headings = {} }
  if not ok then return info end
  local current, block
  local db = roamDb()
  for i, line in ipairs(lines) do
    local name = line:match('^%s*#%+[Bb][Ee][Gg][Ii][Nn]_(%w+)')
    if block then
      local ending = line:match('^%s*#%+[Ee][Nn][Dd]_(%w+)')
      if ending and ending:lower() == block then block = nil end
    elseif name then
      block = name:lower()
    else
      local title = line:match('^#%+[Tt][Ii][Tt][Ll][Ee]:%s*(.-)%s*$')
      local stars, rest = line:match('^(%*+)%s+(.*)$')
      local aliases = line:match('^%s*:ROAM_ALIASES:%s+(.-)%s*$')
      if title and not info.title and title ~= '' then
        info.title = title
      elseif stars then
        current = nil
        local text = rest:gsub('^%u%u+%s+', ''):gsub('^%[#%u%]%s+', ''):gsub('%s+:[%w_@#%%:]+:%s*$', '')
        text = vim.trim(text)
        if #stars <= FIND_MAX_LEVEL and text ~= '' then
          current = { level = #stars, text = text, lnum = i, aliases = {} }
          info.headings[#info.headings + 1] = current
        end
      elseif aliases then
        local names = db and db.split_quoted(aliases) or vim.split(aliases, '%s+', { trimempty = true })
        local into = current and current.aliases or info.aliases
        for _, a in ipairs(names) do into[#into + 1] = a end
      end
    end
  end
  parsed[path] = info
  return info
end

--- The .org files of the vault as { path, rel }, leaving out the editor's backup files and files/.
local function vaultFiles(root)
  local out = {}
  for _, path in ipairs(vim.fn.globpath(root, '**/*.org', false, true)) do
    path = vim.fs.normalize(path)
    local rel = path:sub(#root + 2)
    if not (rel:match('^files/') or rel:match('/[.#]') or rel:match('^[.#]')) then
      out[#out + 1] = { path = path, rel = rel }
    end
  end
  return out
end

--- Every entry of the vault in the default order.
local function findEntries(root)
  local groups = {}
  for _, f in ipairs(vaultFiles(root)) do
    local info = parseFile(f.path)
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

--- A new seed in the inbox, then open it.
local function newSeed(title)
  local root = M.path()
  if not root then return end
  local inbox = root .. '/' .. M.inbox()
  local lines = vim.fn.filereadable(inbox) == 1 and vim.fn.readfile(inbox) or {}
  if #lines > 0 and lines[#lines] ~= '' then lines[#lines + 1] = '' end
  local first = #lines + 1
  vim.list_extend(lines, { '* SEED ' .. title, ':PROPERTIES:', ':CREATED:  [' .. os.date('%Y-%m-%d %a %H:%M') .. ']', ':END:' })
  vim.fn.writefile(lines, inbox)
  vim.cmd('edit ' .. vim.fn.fnameescape(inbox))
  vim.cmd('silent! checktime')
  pcall(vim.api.nvim_win_set_cursor, 0, { first, 0 })
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

-- Exposed for tests.
M._find = { entries = findEntries, line = findLine, newSeed = newSeed }

M.newNote = org('roam_capture')
M.insertLink = function() require('pure.links').pick() end
M.backlinks = org('roam_buffer_toggle')
M.capture = org('capture')
-- A new seed: the node capture (`n`), which stores an entry with no :TYPE: in the inbox as a SEED.
M.newSeed = org('capture n')
M.journalLine = org('capture j')
M.journalToday = org('roam_dailies_goto_today')
-- The TODO state menu of the heading (org.nvim's todo_select, <leader>mS): it lists the states of the heading's
-- note, so the garden stages in the inbox and garden/, the task states in tasks.org (their #+TODO: lines).
M.todoState = org('todo_select')
M.agenda = org('agenda')

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
--  Rename, delete
-- -----------------------------------------------------------------------------
--- The file-level #+title line of the buffer: its row (0-based) and text.
local function titleLine(buf)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 30, false)) do
    local title = line:match('^#%+[Tt][Ii][Tt][Ll][Ee]:%s*(.-)%s*$')
    if title then return row - 1, title end
  end
end

--- "My title" -> "my_title" (the slug org-roam gives a file).
local function slug(title)
  return (title:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''))
end

--- A new title and file name for this note. Links are by :ID:, so none breaks.
function M.rename()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if not inVault(path) or vim.bo[buf].filetype ~= 'org' then return warn('this buffer is not a note of the vault') end
  local row, old = titleLine(buf)
  old = old or vim.fn.fnamemodify(path, ':t:r')
  vim.ui.input({ prompt = 'New title: ', default = old }, function(title)
    title = title and vim.trim(title) or ''
    if title == '' then return end
    local name = slug(title)
    if name == '' then return warn('no title') end
    local new = vim.fn.fnamemodify(path, ':h') .. '/' .. name .. '.org'
    if vim.fs.normalize(new) ~= vim.fs.normalize(path) and vim.uv.fs_stat(new) then
      return warn(name .. '.org exists')
    end
    if row then
      vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { '#+title: ' .. title })
    else
      -- No title yet: after the :PROPERTIES: drawer of a file node, else first.
      local at = 0
      local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ''
      if first:match('^:PROPERTIES:') then
        for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 30, false)) do
          if l:match('^:END:') then at = i break end
        end
      end
      vim.api.nvim_buf_set_lines(buf, at, at, false, { '#+title: ' .. title })
    end
    vim.cmd('silent write')
    if vim.fs.normalize(new) ~= vim.fs.normalize(path) then
      vim.cmd('silent saveas! ' .. vim.fn.fnameescape(new))
      os.remove(path)
      vim.cmd('silent! bwipeout ' .. vim.fn.bufnr(path))
    end
    syncIndex()
    vim.notify('Renamed to ' .. name .. '.org')
  end)
end

--- Move this note to archive/trash/ (nothing is erased).
function M.delete()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if not inVault(path) or vim.bo[buf].buftype ~= '' then return warn('this buffer is not a note of the vault') end
  local name = vim.fn.fnamemodify(path, ':t')
  if vim.fn.confirm('Move ' .. name .. ' to archive/trash/?', '&Yes\n&No', 2) ~= 1 then return end
  local trash = M.path() .. '/archive/trash'
  vim.fn.mkdir(trash, 'p')
  local dest = trash .. '/' .. name
  -- Do not overwrite an older note of the same name in the trash.
  if vim.uv.fs_stat(dest) then dest = trash .. '/' .. os.date('%Y%m%d%H%M%S') .. '-' .. name end
  vim.cmd('silent! write')
  local ok, err = vim.uv.fs_rename(path, dest)
  if not ok then return warn('could not move the note: ' .. tostring(err)) end
  vim.cmd('silent! bwipeout! ' .. buf)
  syncIndex()
  vim.notify('Moved to archive/trash/')
end

-- -----------------------------------------------------------------------------
--  Sync
-- -----------------------------------------------------------------------------
--- Save the notes of the vault and commit; with an upstream, pull and push too
--- (pure/vaultsync.lua). The vault may have no remote: then it stays a commit.
function M.sync()
  local dir = M.path()
  if not dir then return end
  local up = vim.system({ 'git', '-C', dir, 'rev-parse', '--abbrev-ref', '@{u}' }, { text = true }):wait()
  if up.code == 0 then return require('pure.vaultsync').sync(dir) end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if vim.bo[b].modified and vim.bo[b].buftype == '' and inVault(name) then
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

-- -----------------------------------------------------------------------------
--  The linked note: preview (p). The quick edit (it was q) was removed on
--  2026-11-08: <leader>vq is the quick capture now.
-- -----------------------------------------------------------------------------
--- Where the link under the cursor points: path, row (1-based) or nil.
local function target()
  local line, col = vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2]
  local link
  -- [[target]] or [[target][description]]: the match covers the whole link.
  for s, inner, e in line:gmatch('()%[%[(.-)%]%]()') do
    if col + 1 >= s and col + 1 < e then link = inner:match('^([^%]]*)') break end
  end
  if not link then return nil end
  local kind, ref = link:match('^(%a+):(.*)$')
  local db = roamDb()
  if kind == 'id' and db then
    local node = db.node(ref)
    if node then return node.file, node.lnum or 1 end
  elseif kind == 'roam' and db then
    local node = (db.by_title(ref) or {})[1]
    if node then return node.file, node.lnum or 1 end
  elseif kind == 'file' then
    local file = ref:gsub('::.*$', '')
    if vim.fn.isabsolutepath(file) == 0 then file = vim.fn.expand('%:p:h') .. '/' .. file end
    if vim.uv.fs_stat(file) then return file, 1 end
  end
  return nil
end

--- The lines of a node: its subtree (a headline) or the whole file.
local function nodeLines(path, row)
  local nr = vim.fn.bufnr(path)
  local lines = (nr ~= -1 and vim.api.nvim_buf_is_loaded(nr)) and vim.api.nvim_buf_get_lines(nr, 0, -1, false)
    or vim.fn.readfile(path)
  local stars = (lines[row] or ''):match('^(%*+)%s')
  if not stars then return lines end
  local last = #lines
  for i = row + 1, #lines do
    local s = lines[i]:match('^(%*+)%s')
    if s and #s <= #stars then last = i - 1 break end
  end
  return vim.list_slice(lines, row, last)
end

local preview = { win = nil }

function M.closePreview()
  local win = preview.win
  preview.win = nil
  if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
end

--- A small read-only window with the note the link under the cursor points to (toggles).
function M.preview()
  local was = preview.win and vim.api.nvim_win_is_valid(preview.win)
  M.closePreview()
  if was then return end
  local path, row = target()
  if not path then return vim.notify('Vault: no link to a note under the cursor') end
  local lines = nodeLines(path, row)
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines, 16)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'org'
  vim.bo[buf].modifiable = false
  preview.win = vim.api.nvim_open_win(buf, false, {
    relative = 'cursor', row = 1, col = 0, width = width, height = math.max(height, 1),
    style = 'minimal', border = 'rounded', title = ' ' .. vim.fn.fnamemodify(path, ':t:r') .. ' ',
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufLeave' }, {
    once = true, callback = function() M.closePreview() end,
  })
end

-- -----------------------------------------------------------------------------
--  The garden: grow (n) and compost (c), as Doom's `SPC v n` / `SPC v c`
-- -----------------------------------------------------------------------------
--  Ports of my/garden-grow and my/garden-compost (.config\emacs\lisp\org-garden.el).
--  The stages are the second keyword set of lua/plugins/org.lua.

local LADDER = { 'SEED', 'SPROUT', 'PLANT', 'TREE' }
-- The garden's states as a #+TODO: line: the inbox carries only it, so its headings offer only these (tasks.org
-- carries only the task states). The same words as the second set of lua/plugins/org.lua. FRUIT was FLOWER until
-- 2026-11-08: a tree bears fruit (Mia).
local GARDEN_TODO = '#+TODO: SEED(s) SPROUT(p) PLANT(l) TREE(r) FRUIT(f) | COMPOST(c)'
-- The nursery and the notes of garden/ carry both sets, the garden's first (Mia, 2026-11-09: only the inbox and
-- tasks.org keep one set; every other note has both).
local TASKS_TODO = '#+TODO: TODO(t) NEXT(n) DOING(d) WAITING(w@) | DONE(x!) CANCELLED(c@)'
local NOTE_TODO = { GARDEN_TODO, TASKS_TODO }

--- A new note of garden/ for the idea `title` (a path from the vault's root): named after the title, _2, _3...
--- when the name is taken. Plants, trees and fruits live in notes of their own.
local function ownNote(title)
  local base = slug(title)
  if base == '' then base = os.date('%Y%m%d%H%M%S') end
  local rel, n = 'garden/' .. base .. '.org', 1
  while vim.uv.fs_stat(M.dir() .. '/' .. rel) do
    n = n + 1
    rel = ('garden/%s_%d.org'):format(base, n)
  end
  return rel
end

--- The headline at the cursor of an org note of the vault, or nil (with a warning).
local function ideaHere()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= 'org' or not inVault(vim.api.nvim_buf_get_name(buf)) then
    return warn('this buffer is not a note of the vault')
  end
  local ok, hl = pcall(function()
    return require('org.files').get_buffer(buf):headline_at(vim.api.nvim_win_get_cursor(0)[1])
  end)
  if not ok or not hl then return warn('not under a heading') end
  return hl
end

local function sameFile(a, b)
  a = vim.fs.normalize(vim.uv.fs_realpath(a) or a)
  b = vim.fs.normalize(vim.uv.fs_realpath(b) or b)
  if vim.fn.has('win32') == 1 then a, b = a:lower(), b:lower() end
  return a == b
end

--- Move the subtree at the cursor (or at `target`, { bufnr, lnum }) to the top level of `rel` (a file of the
--- vault, made when missing, titled `title`), then save.
local function refileTo(rel, title, target, header)
  local path = M.path() .. '/' .. rel
  if not vim.uv.fs_stat(path) then
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    local head = { '#+title: ' .. (title or vim.fn.fnamemodify(rel, ':t:r')) }
    vim.list_extend(head, header or {})
    head[#head + 1] = ''
    vim.fn.writefile(head, path)
  end
  local ok = pcall(require('org.refile').refile, target,
    { dest = { filename = path, path = rel }, save = true, note = false })
  -- Like org-save-all-org-buffers: the destination may be open in a window (refile saves only hidden ones).
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].modified and sameFile(vim.api.nvim_buf_get_name(b), path) then
      vim.api.nvim_buf_call(b, function() vim.cmd('silent write') end)
    end
  end
  return ok
end

--- One stage up: SEED > SPROUT > PLANT > TREE. A SEED of the inbox becomes a SPROUT and moves to the
--- nursery; a SPROUT becomes a PLANT and moves to a note of its own in garden/ (a plant is an idea of its own;
--- a tree is a plant grown big, in the same note). A FRUIT is not a next step.
function M.grow()
  local hl = ideaHere()
  if not hl then return end
  local state = hl.todo
  if not state then return warn('not an idea heading') end
  local at = vim.tbl_contains(LADDER, state) and vim.fn.index(LADDER, state) + 1
  if not at then return warn('a ' .. state .. ' is not on the ladder of the garden') end
  local nextStage = LADDER[at + 1]
  if not nextStage then return vim.notify('Already a ' .. state) end
  local ok, plain = pcall(function() return hl:plain_title() end)
  local title = vim.trim(ok and plain or '')
  require('org.todo').change_state(nil, nextStage)
  if state == 'SEED' and sameFile(vim.api.nvim_buf_get_name(0), M.path() .. '/' .. M.inbox()) then
    if refileTo(M.nursery(), 'Nursery', nil, NOTE_TODO) then vim.notify(nextStage .. ': moved to the nursery') end
  elseif state == 'SPROUT' then
    local rel = ownNote(title)
    if refileTo(rel, title, nil, NOTE_TODO) then vim.notify(nextStage .. ': a note of its own, ' .. rel) end
  else
    vim.cmd('silent write')
    vim.notify(nextStage)
  end
end

--- An idea let go of: COMPOST, then moved to archive/compost.org (nothing is erased).
--- Asks first, No by default, like <leader>vd (Mia, 2026-11-08).
function M.compost()
  local hl = ideaHere()
  if not hl then return end
  local ok, title = pcall(function() return hl:plain_title() end)
  title = ok and title or vim.trim(hl.title or '')
  if vim.fn.confirm('Compost "' .. title .. '" (move it to archive/compost.org)?', '&Yes\n&No', 2) ~= 1 then return end
  require('org.todo').change_state(nil, 'COMPOST')
  if refileTo('archive/compost.org', 'Compost') then vim.notify('COMPOST: moved to archive/compost.org') end
end

-- -----------------------------------------------------------------------------
--  Sources, the node capture and moving a heading (m)
-- -----------------------------------------------------------------------------

--- Make the note at `rel` (a path from the root of the vault) with `lines` when it does not exist yet.
local function ensureNote(rel, lines)
  local path = M.dir() .. '/' .. rel
  if vim.uv.fs_stat(path) then return end
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(vim.list_extend(vim.deepcopy(lines), { '' }), path)
end

--- Where each garden :TYPE: of the node capture goes: the state its heading gets and the note.
---   'inbox' / 'nursery' / 'own' (a note of its own in garden/, named after the title) / 'compost'
local GARDEN_TYPES = {
  seed = { 'SEED', 'inbox' },
  sprout = { 'SPROUT', 'nursery' },
  plant = { 'PLANT', 'own' },
  tree = { 'TREE', 'own' },
  fruit = { 'FRUIT', 'own' },
  compost = { 'COMPOST', 'compost' },
}
local GARDEN_KEYWORDS = { 'SEED', 'SPROUT', 'PLANT', 'TREE', 'FRUIT', 'COMPOST' }

--- The lines of a node capture, rewritten for where they go, and that place (a path from the root of the vault;
--- nil keeps the template's target, the inbox). Used by the store filter of lua/plugins/org.lua (Mia, 2026-11-08):
---   :TYPE: seed / sprout / plant / tree / fruit / compost (any case): the heading gets that state and goes to the
---     inbox, the nursery, a note of its own in garden/ (plant, tree, fruit), or archive/compost.org;
---     the TYPE line is dropped (the state says it, and changes later).
---   :TYPE: <the name of a note of sources/>: that note; TYPE stays (<leader>vm reads it).
---   no TYPE, or a type with no note: the inbox as a SEED; an unknown TYPE stays, for <leader>vm once its note exists.
--- Every empty property is dropped (:AUTHOR: with nothing after it), in every case.
function M.routeNode(lines)
  local out, type, typeAt, heading = {}, nil, nil, nil
  local inDrawer = false
  for _, l in ipairs(lines) do
    if not heading and l:match('^%*+%s') then
      out[#out + 1] = l
      heading = #out
    elseif l:match('^%s*:PROPERTIES:%s*$') then
      inDrawer = true
      out[#out + 1] = l
    elseif inDrawer and l:match('^%s*:END:%s*$') then
      inDrawer = false
      out[#out + 1] = l
    elseif inDrawer and l:match('^%s*:[^:%s]+:%s*$') then
      -- an empty property: left out
    else
      out[#out + 1] = l
      local value = inDrawer and l:match('^%s*:[Tt][Yy][Pp][Ee]:%s*(.-)%s*$')
      if value then type, typeAt = value, #out end
    end
  end
  --- The heading with `state` in place of a garden state it may already have.
  local function setState(state)
    if not heading then return end
    local stars, rest = out[heading]:match('^(%*+)%s+(.*)$')
    local first = rest:match('^(%u+)%s') or rest:match('^(%u+)$')
    if first and vim.tbl_contains(GARDEN_KEYWORDS, first) then rest = vim.trim(rest:sub(#first + 1)) end
    out[heading] = stars .. ' ' .. state .. (rest ~= '' and ' ' .. rest or '')
  end
  local function dropType()
    if typeAt then table.remove(out, typeAt) end
  end
  local key = vim.fn.tolower(vim.trim(type or ''))
  local garden = GARDEN_TYPES[key]
  if garden then
    local state, place = garden[1], garden[2]
    dropType()
    setState(state)
    if place == 'inbox' then return out, nil end
    if place == 'compost' then
      ensureNote('archive/compost.org', { '#+TITLE: Compost' })
      return out, 'archive/compost.org'
    end
    if place == 'nursery' then
      ensureNote(M.nursery(), { '#+TITLE: Nursery', unpack(NOTE_TODO) })
      return out, M.nursery()
    end
    -- A note of its own, named after the title (a new name when one is taken: _2, _3...).
    local title = heading and vim.trim(out[heading]:gsub('^%*+%s+', ''):gsub('^%u+%s+', '', 1)) or ''
    local rel = ownNote(title)
    ensureNote(rel, { '#+title: ' .. title, unpack(NOTE_TODO) })
    return out, rel
  end
  local source = key ~= '' and M.sourceFile(type) or nil
  if source then return out, source end
  if key ~= '' then
    vim.notify(('No note sources/%s.org: the entry goes to the inbox as a SEED'):format(key), vim.log.levels.WARN)
  end
  setState('SEED')
  return out, nil
end

--- The note of sources/ named `type` (any case: books, Books, BOOKS -> sources/books.org), as a path from the
--- root of the vault, or nil when there is none. Used by the source capture (lua/plugins/org.lua) and by move.
function M.sourceFile(type)
  local root = M.dir()
  if not root or type == nil or vim.trim(type) == '' then return nil end
  local want = vim.fn.tolower(vim.trim(type)) .. '.org'
  for name, kind in vim.fs.dir(root .. '/sources') do
    if kind == 'file' and vim.fn.tolower(name) == want then return 'sources/' .. name end
  end
end

--- Move the heading at the cursor, with everything under it, to another note of the vault (<leader>vm): the note
--- of its :TYPE: when sources/ has one (a source left in the inbox), else a note picked in the fzf list. It lands
--- at the top level of that note, both notes are saved, and a table made from headings there follows (the write
--- hook of lua/plugins/org.lua). Links are by :ID:, so none breaks.
function M.move()
  local buf = vim.api.nvim_get_current_buf()
  local here = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].filetype ~= 'org' or not inVault(here) then return warn('this buffer is not a note of the vault') end
  local ok, hl = pcall(function()
    return require('org.files').get_buffer(buf):headline_at(vim.api.nvim_win_get_cursor(0)[1])
  end)
  if not ok or not hl then return warn('not under a heading') end
  local target = { bufnr = buf, lnum = hl.line }
  local rel = M.sourceFile(hl:get_property('TYPE'))
  if rel and not sameFile(M.path() .. '/' .. rel, here) then
    if refileTo(rel, nil, target) then vim.notify('Moved to ' .. rel) end
    return
  end
  local items = {}
  for _, f in ipairs(vaultFiles(M.path())) do
    if not sameFile(f.path, here) then items[#items + 1] = f.rel end
  end
  table.sort(items)
  vim.ui.select(items, { prompt = 'Move to', sort = true }, function(choice)
    if choice and refileTo(choice, nil, target) then vim.notify('Moved to ' .. choice) end
  end)
end

-- -----------------------------------------------------------------------------
--  The linked note, editable (the second K)
-- -----------------------------------------------------------------------------
--- The note a link of an org note points to, itself: its real buffer (editable, :w saves it, drawn as org by
--- pure/render-org.lua like any note) in a floating window where the hover `hoverWin` was (made bigger when it is
--- small), at the heading the link names. q closes it (asking to save when it was changed). The second K of
--- configs/functions.lua followOrHover calls it; the link is read by lsp/orgls.lua. false when the cursor is not on
--- a link to a note (K then does what it did). (Mia, 2026-11-08.)
function M.editLinkedNote(hoverWin)
  local ok, mod = pcall(function() return require('lsp.orgls')._module end)
  if not ok or not mod then return false end
  local line, col = vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2]
  local link = mod._linkAt(line, col)
  local target = link and mod._linkTarget(vim.api.nvim_get_current_buf(), link.inner)
  if not target or not target.file then return false end
  local W, H = vim.o.columns, vim.o.lines
  local row, column, width, height = 1, 1, 0, 0
  if hoverWin and vim.api.nvim_win_is_valid(hoverWin) then
    local pos = vim.api.nvim_win_get_position(hoverWin)
    row, column = pos[1], pos[2]
    width, height = vim.api.nvim_win_get_width(hoverWin), vim.api.nvim_win_get_height(hoverWin)
    pcall(vim.api.nvim_win_close, hoverWin, true)
  end
  width = math.min(math.max(width, math.min(80, W - 4)), W - 2)
  height = math.min(math.max(height, math.min(20, H - 6)), H - 4)
  row = math.max(0, math.min(row, H - height - 3))
  column = math.max(0, math.min(column, W - width - 2))
  local buf = vim.fn.bufadd(target.file)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', row = row, col = column, width = width, height = height,
    border = 'rounded', title = ' ' .. (target.label or vim.fn.fnamemodify(target.file, ':t:r')) .. ' ', title_pos = 'center',
  })
  -- A link to a heading lands on it. A link to the whole note names its first line, inside the properties drawer:
  -- the cursor goes to the #+title line instead, else to the first heading (Mia, 2026-11-08).
  local lnum = target.lnum or 1
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if not (lines[lnum] or ''):match('^%*+%s') then
    local titleAt, headingAt
    for i, l in ipairs(lines) do
      if not titleAt and l:match('^#%+[Tt][Ii][Tt][Ll][Ee]:') then titleAt = i end
      if l:match('^%*+%s') then headingAt = i break end
    end
    lnum = titleAt or headingAt or lnum
  end
  pcall(vim.api.nvim_win_set_cursor, win, { lnum, 0 })
  pcall(vim.cmd, 'normal! zvzt')
  -- q closes this window only (the buffer is the note itself: the key is taken back when the window closes).
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_get_current_win() ~= win then return vim.api.nvim_feedkeys('q', 'n', false) end
    if vim.bo[buf].modified then
      local c = vim.fn.confirm('Save ' .. vim.fn.fnamemodify(target.file, ':t') .. '?', '&Yes\n&No\n&Cancel', 1)
      if c == 1 then vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
      elseif c ~= 2 then return end
    end
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, desc = 'Close the linked note' })
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win), once = true,
    callback = function() pcall(vim.keymap.del, 'n', 'q', { buffer = buf }) end,
  })
  return true
end

return M
