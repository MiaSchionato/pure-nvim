-- =============================================================================
--  Flora: the org vault (<leader>v)
-- =============================================================================
--  Flora is the org port of the Atlas vault. This module holds what the
--  <leader>v group does with it, the way Doom's `SPC v` does (the Emacs side is
--  C:\doom\config\config.el and .config\emacs\lisp\org-vault.el):
--
--    f  find a node (a file, a headline with an :ID:, an alias); a new title makes a note
--    F  find a file of the vault
--    g  grep the vault
--    n  new seed (inbox)               N  new note in its own file
--    t  capture template menu          i  insert a link to a node
--    b  backlinks                      r  rename this note (title and file)
--    d  delete this note (to archive/trash/, nothing is erased)
--    j  journal line (today)           J  today in the journal
--    e  explore the vault              s  save the notes and commit (sync when there is an upstream)
--    p  preview the linked note        q  quick edit the linked note
--
--  Notes link to each other by :ID: (org-roam), so renaming or moving a file
--  breaks no link. The nodes come from org.nvim's roam extension
--  (lua/plugins/org.lua); this module only asks it. vim.g.flora_dir changes
--  the folder (default ~/Flora).
-- =============================================================================

local M = {}

local function warn(msg) vim.notify('Flora: ' .. msg, vim.log.levels.WARN) end

--- The vault folder, or nil (with a warning) when it is not there.
function M.path()
  local dir = vim.fs.normalize(vim.fn.expand(vim.g.flora_dir or '~/Flora'))
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
--  Order: the notes written last first, `archive/` always last; for each note the note, its aliases, then its headings.
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
    local list = { vim.tbl_extend('force', base, { kind = 'note', title = note, lnum = 1 }) }
    for _, a in ipairs(info.aliases) do
      list[#list + 1] = vim.tbl_extend('force', base, { kind = 'alias', title = a, target = note, lnum = 1 })
    end
    for _, h in ipairs(info.headings) do
      list[#list + 1] = vim.tbl_extend('force', base, { kind = 'heading', title = h.text, level = h.level, lnum = h.lnum })
      for _, a in ipairs(h.aliases) do
        list[#list + 1] = vim.tbl_extend('force', base,
          { kind = 'alias', title = a, target = h.text, level = h.level, lnum = h.lnum, heading = true })
      end
    end
    groups[#groups + 1] = { archive = archive, mtime = info.mtime, list = list }
  end
  table.sort(groups, function(a, b)
    if a.archive ~= b.archive then return not a.archive end
    return a.mtime > b.mtime
  end)
  local out = {}
  for _, g in ipairs(groups) do vim.list_extend(out, g.list) end
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
  local inbox = root .. '/inbox.org'
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
    title = ' Flora ',
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
M.template = org('capture')
M.newSeed = org('capture s')
M.journalLine = org('capture j')
M.journalToday = org('roam_dailies_goto_today')

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
--- (pure/vaultsync.lua). Flora may have no remote: then it stays a commit.
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
          if res.code == 0 then vim.notify('Flora: committed (no upstream, nothing pushed)')
          elseif (res.stdout or ''):find('nothing %a* ?to commit') then vim.notify('Flora: nothing to commit')
          else warn('commit failed: ' .. vim.trim((res.stderr or '') .. (res.stdout or ''))) end
        end)
      end)
  end)
end

-- -----------------------------------------------------------------------------
--  The linked note: preview (p) and quick edit (q)
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
  if not path then return vim.notify('Flora: no link to a note under the cursor') end
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

--- The linked note itself (the real buffer) in a floating window; q closes it.
function M.quickEdit()
  M.closePreview()
  local path, row = target()
  if not path then return vim.notify('Flora: no link to a note under the cursor') end
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  local width, height = math.floor(vim.o.columns * 0.7), math.floor(vim.o.lines * 0.6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2), col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal', border = 'rounded', title = ' ' .. vim.fn.fnamemodify(path, ':t:r') .. ' ',
  })
  pcall(vim.api.nvim_win_set_cursor, win, { row, 0 })
  vim.keymap.set('n', 'q', function()
    if vim.bo[buf].modified then
      if vim.fn.confirm('Save ' .. vim.fn.fnamemodify(path, ':t') .. '?', '&Yes\n&No\n&Cancel', 1) == 1 then
        vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
      elseif vim.fn.confirm('Discard the changes?', '&Yes\n&No', 2) ~= 1 then
        return
      end
    end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, { buffer = buf, desc = 'Close the quick edit' })
end

return M
