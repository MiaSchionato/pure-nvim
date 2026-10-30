-- =============================================================================
--  Links between notes: [[ completes, <leader>vi picks  (org notes of the vault)
-- =============================================================================
--  A port of the Emacs side (C:\doom\config\link-complete.el and aliases.el):
--
--    [[foo           a menu of the notes, aliases and headings (levels 1-2) called like foo
--    [[*foo [[#foo   only headings               [[note*foo [[note#foo [[note:foo   headings of that note
--    [[foo||short    the link reads "short": the alias is saved in the note (:ROAM_ALIASES:)
--    + New note: foo the last item makes a SEED called foo in the inbox and links to it
--
--  Choosing an item replaces `[[foo` by `[[id:ID][Title]]` (the render hides the id) and the target gets
--  its :ID: now when it had none, in the file or in the heading, through org.nvim's own org.id. The cursor
--  stays INSIDE the link, at the end of its text: type `*`, `#` or `:` there and the headings of that note
--  open in the menu; choosing one makes the link a link to that heading. `]` goes out past the `]]`.
--
--  The menu is Neovim's own completion menu (completefunc, buffer-local in org notes): <C-n> / <C-p> or
--  Tab / S-Tab move, Enter takes the highlighted one (the first is highlighted at once), Esc closes it.
--
--  <leader>vi (normal mode) is the same list in the picker of <leader>vf, and inserts the link at the cursor.
--
--  Settings (configs.lua):
--    vim.g.pure_links_complete   false turns the [[ menu off (default on)
-- =============================================================================

local M = {}

local api = vim.api
local style = require('pure.pickerstyle')

-- The schemes of a typed link: `[[file:` or `[[https:` is not a search for a note.
local SCHEMES = {
  file = true, id = true, http = true, https = true, mailto = true, ftp = true, docview = true,
  shell = true, elisp = true, attachment = true, help = true, info = true, news = true, doi = true,
}

local MAX_ITEMS = 60

-- What the menu is working on: set by the findstart call, read by the accept.
-- mode: 'note' (after [[) or 'heading' (a # * : typed in the text of an id: link);
-- linkstart: 0-based column of the [[; input: the text last asked for; file: the note of 'heading'.
local state = { mode = nil, linkstart = 0, input = '', items = {}, file = nil }

-- The links this module has written (an extmark over each): only those are read for a ||alias, so a link that
-- was already in a note, whatever its text, is never rewritten.
local FRESH_NS = api.nvim_create_namespace('pure_links_fresh')

-- -----------------------------------------------------------------------------
--  Text helpers
-- -----------------------------------------------------------------------------
local ACCENTS = {
  ['á'] = 'a', ['à'] = 'a', ['â'] = 'a', ['ã'] = 'a', ['ä'] = 'a', ['é'] = 'e', ['è'] = 'e', ['ê'] = 'e', ['ë'] = 'e',
  ['í'] = 'i', ['ì'] = 'i', ['î'] = 'i', ['ï'] = 'i', ['ó'] = 'o', ['ò'] = 'o', ['ô'] = 'o', ['õ'] = 'o', ['ö'] = 'o',
  ['ú'] = 'u', ['ù'] = 'u', ['û'] = 'u', ['ü'] = 'u', ['ç'] = 'c', ['ñ'] = 'n',
}

for k, v in pairs(vim.deepcopy(ACCENTS)) do ACCENTS[vim.fn.toupper(k)] = v end

--- Lower case with the accents taken off: "Ação" -> "acao".
local function fold(text)
  local out = vim.fn.tolower(text):gsub('[\195][\128-\191]', function(c) return ACCENTS[c] end)
  return out
end

local function words(text)
  local out = {}
  for w in fold(text):gmatch('%S+') do out[#out + 1] = w end
  return out
end

local function hasAll(haystack, list)
  for _, w in ipairs(list) do
    if not haystack:find(w, 1, true) then return false end
  end
  return true
end

local function norm(path) return (vim.fs.normalize(path):gsub('/+$', '')) end

local function samePath(a, b)
  a, b = norm(a), norm(b)
  if vim.fn.has('win32') == 1 then a, b = a:lower(), b:lower() end
  return a == b
end

-- -----------------------------------------------------------------------------
--  The nodes (the same entries as <leader>vf)
-- -----------------------------------------------------------------------------
local function allEntries()
  local flora = require('pure.flora')
  local root = flora.path()
  if not root then return {} end
  return flora._find.entries(root)
end

--- `[[a*b`: the text after [[ split into (headings only, words of the note, query). Whatever follows `||` is
--- the new alias, not part of the search.
local function parse(input)
  local base = input:match('^(.-)||') or input
  if base:match('^[#*]') then return true, nil, base:sub(2) end
  local note, query = base:match('^([^#*:]+)[#*:](.*)$')
  if note and not (SCHEMES[note] and note:match('^%a+$')) then return true, note, query end
  return false, nil, base
end

local function aliasOf(input)
  local alias = input:match('||(.*)$')
  alias = alias and vim.trim(alias) or nil
  if alias == '' then alias = nil end
  return alias
end

--- The entries a query asks for, best first: the title equal to the query, then the ones that start with
--- it, notes before headings, shorter first, and (the entries come newest first) the newer.
local function search(input, mode, file, nosep)
  local headingsOnly, noteWords, query = parse(input)
  -- A # * : in the text may be part of a title ("Emacs log: to do"): then the whole text is the search.
  if nosep then headingsOnly, noteWords, query = false, nil, (nosep == 'whole' and input or (input:match('^(.-)||') or input)) end
  local qwords = words(query)
  local nwords = noteWords and words(noteWords) or nil
  local q = fold(vim.trim(query))
  local out = {}
  for i, e in ipairs(allEntries()) do
    local isHeading = e.kind == 'heading' or (e.kind == 'alias' and e.heading)
    local keep = true
    if mode == 'heading' then
      keep = isHeading and file and samePath(e.file, file)
    elseif headingsOnly then
      keep = isHeading
    else
      keep = not isHeading or (e.level or 1) <= 2
    end
    if keep and nwords then
      keep = hasAll(fold(vim.fn.fnamemodify(e.file, ':t:r') .. ' ' .. (e.note or '')), nwords)
    end
    if keep then
      local title = fold(e.title)
      local hay = (e.kind == 'note') and (title .. ' ' .. fold(e.path)) or (e.kind == 'alias' and (title .. ' ' .. fold(e.target or '')) or title)
      if hasAll(hay, qwords) then
        local score = (title == q) and 0 or (title:sub(1, #q) == q and 1 or 2)
        out[#out + 1] = { e = e, i = i, score = score, len = #title, head = isHeading and 1 or 0 }
      end
    end
  end
  if mode == 'heading' then
    -- The headings of a note in the order of the file.
    table.sort(out, function(a, b) return a.e.lnum < b.e.lnum end)
  else
    table.sort(out, function(a, b)
      if a.score ~= b.score then return a.score < b.score end
      if a.head ~= b.head then return a.head < b.head end
      if a.len ~= b.len then return a.len < b.len end
      return a.i < b.i
    end)
  end
  local list = {}
  for _, c in ipairs(out) do
    list[#list + 1] = c.e
    if #list >= MAX_ITEMS then break end
  end
  return list, vim.trim(query), headingsOnly
end

--- The entries for the text typed after [[. `note:head`, `note*head` and `note#head` ask for headings of a
--- note, unless the whole text is the name of a note (a title with a colon): then it is a plain search.
local function candidates(input, mode, file)
  -- A title with || in it: the whole text is searched first (the note "A || B" typed as [[A || B).
  if mode ~= 'heading' and input:find('||', 1, true) then
    local whole, q = search(input, mode, file, 'whole')
    for _, e in ipairs(whole) do
      if e.kind == 'note' and fold(e.title):find(fold(vim.trim(input)), 1, true) then return whole, q, false end
    end
  end
  if mode ~= 'heading' then
    local headingsOnly, noteWords = parse(input)
    if headingsOnly and noteWords then
      local plain, q = search(input, mode, file, true)
      for _, e in ipairs(plain) do
        if e.kind == 'note' or (e.kind == 'alias' and not e.heading) then return plain, q, false end
      end
    end
  end
  return search(input, mode, file, false)
end

-- -----------------------------------------------------------------------------
--  IDs and aliases (org.nvim's org.id, org.edit)
-- -----------------------------------------------------------------------------
local function joinQuoted(names)
  local out = {}
  for _, n in ipairs(names) do
    out[#out + 1] = n:find('[%s"]') and ('"' .. n:gsub('"', '\\"') .. '"') or n
  end
  return table.concat(out, ' ')
end

local function splitQuoted(text)
  local ok, db = pcall(require, 'org.extensions.roam.db')
  if ok and db.split_quoted then return db.split_quoted(text or '') end
  return vim.split(text or '', '%s+', { trimempty = true })
end

--- The :ID: of the note (lnum 1, no heading) or of the heading at `lnum` of `file`, made now when missing,
--- with `alias` added to its :ROAM_ALIASES:. A file that was not open is written; the current buffer (or one
--- with unsaved changes) is left modified for you to save.
--- @return string|nil id, string|nil err
local function ensureId(file, lnum, alias)
  local ok, ids = pcall(require, 'org.id')
  if not ok then return nil, 'org.nvim is not loaded' end
  local edit = require('org.edit')
  local buf = vim.fn.bufadd(file)
  local wasLoaded = api.nvim_buf_is_loaded(buf)
  local wasModified = wasLoaded and vim.bo[buf].modified
  if not wasLoaded then
    vim.fn.bufload(buf)
    vim.bo[buf].buflisted = false
  end
  local id = ids.get_create({ bufnr = buf, lnum = lnum })
  local added = false
  if id and alias then
    local _, f, hl = edit.resolve({ bufnr = buf, lnum = lnum })
    local names = splitQuoted((hl and hl.properties or f.properties).ROAM_ALIASES)
    if not vim.tbl_contains(names, alias) then
      names[#names + 1] = alias
      edit.set_property(buf, hl and hl.line or 1, 'ROAM_ALIASES', joinQuoted(names))
      added = true
    end
  end
  if buf ~= api.nvim_get_current_buf() and not wasModified and vim.bo[buf].modified then
    api.nvim_buf_call(buf, function() vim.cmd('silent! write') end)
  end
  return id, nil, added
end

--- The line of the heading `title` in the buffer of `file` when it is open and its text moved since the
--- list was made (unsaved edits above it); `lnum` when it is still where it was, nil when it is gone.
local function headingLine(file, lnum, title)
  local buf = vim.fn.bufnr(file)
  if buf == -1 or not api.nvim_buf_is_loaded(buf) then return lnum end
  local function isIt(n)
    local l = api.nvim_buf_get_lines(buf, n - 1, n, false)[1]
    return l and l:match('^%*+%s') and l:find(title, 1, true) ~= nil
  end
  if isIt(lnum) then return lnum end
  for n, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:match('^%*+%s') and l:find(title, 1, true) then return n end
  end
  return nil
end

--- A SEED called `title` at the end of the inbox, without opening it: (file, lnum).
local function createSeed(title)
  local root = require('pure.flora').path()
  if not root then return nil end
  local inbox = root .. '/inbox.org'
  local buf = vim.fn.bufnr(inbox)
  local lines
  if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
    lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  else
    lines = vim.fn.filereadable(inbox) == 1 and vim.fn.readfile(inbox) or {}
  end
  if #lines > 0 and lines[#lines] ~= '' then lines[#lines + 1] = '' end
  local first = #lines + 1
  vim.list_extend(lines, { '* SEED ' .. title, ':PROPERTIES:', ':CREATED:  [' .. os.date('%Y-%m-%d %a %H:%M') .. ']', ':END:' })
  if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    api.nvim_buf_call(buf, function() vim.cmd('silent! write') end)
  else
    vim.fn.writefile(lines, inbox)
  end
  return inbox, first
end

local function syncIndexSoon()
  vim.defer_fn(function()
    if vim.fn.exists(':Org') == 2 then pcall(vim.cmd, 'Org roam_db_sync') end
  end, 1500)
end

--- The target of an entry: (file, lnum); a note and the alias of a note are the file (lnum 1).
local function targetOf(e)
  if e.kind == 'note' or (e.kind == 'alias' and not e.heading) then return e.file, 1 end
  return e.file, e.lnum
end

--- The text of the link for an entry: a note, a heading, or the alias that was picked.
local function textOf(e)
  return e.title
end

-- -----------------------------------------------------------------------------
--  Writing the link
-- -----------------------------------------------------------------------------
--- Replace columns [from, to) of the current line by the link to `entry` (or to a new note named `new`).
--- The cursor goes inside the link, at the end of its text, or after it when `after`.
local function writeLink(buf, win, row, from, to, entry, opts)
  opts = opts or {}
  local file, lnum, text
  if opts.new then
    file, lnum = createSeed(opts.new)
    text = opts.new
  else
    file, lnum = targetOf(entry)
    text = textOf(entry)
    if lnum > 1 then
      -- The list was read from the disk: a heading may have moved in an open, unsaved buffer.
      lnum = headingLine(file, lnum, entry.kind == 'alias' and entry.target or entry.title)
      if not lnum then return vim.notify('Link: that heading is gone', vim.log.levels.WARN) end
    end
  end
  if not file then return end
  if opts.alias then text = opts.alias end

  -- Making the id may add lines above (the drawer of a note, in this very buffer): follow the line.
  local ns = api.nvim_create_namespace('pure_links')
  local mark = api.nvim_buf_set_extmark(buf, ns, row, 0, {})
  local id, err = ensureId(file, lnum, opts.alias)
  if not id then
    vim.notify('Link: ' .. tostring(err or 'no id'), vim.log.levels.WARN)
    api.nvim_buf_del_extmark(buf, ns, mark)
    return
  end
  local pos = api.nvim_buf_get_extmark_by_id(buf, ns, mark, {})
  api.nvim_buf_del_extmark(buf, ns, mark)
  row = pos[1] or row

  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  -- The ]] that the pairs added with the [[ are part of the link now.
  if line:sub(to + 1, to + 2) == ']]' then to = to + 2 end
  local link = string.format('[[id:%s][%s]]', id, text .. (opts.tail or ''))
  api.nvim_buf_set_text(buf, row, from, row, to, { link })
  api.nvim_buf_set_extmark(buf, FRESH_NS, row, from, { end_row = row, end_col = from + #link })
  if win and api.nvim_win_is_valid(win) then
    local col = from + #link - (opts.after and 0 or 2)
    pcall(api.nvim_win_set_cursor, win, { row + 1, col })
  end
  syncIndexSoon()
end

-- -----------------------------------------------------------------------------
--  The [[ menu (completefunc)
-- -----------------------------------------------------------------------------
local IDLINK = '%[%[id:([^%]]+)%]%[([^%]]-)([#*:])([^%]#*:]*)$'

--- completefunc: findstart 1 -> the column where the typed text starts (or -3: not a link to search);
--- findstart 0 -> the items for `base`.
function M.complete(findstart, base)
  if findstart == 1 then
    local col = api.nvim_win_get_cursor(0)[2]
    local before = api.nvim_get_current_line():sub(1, col)
    local a, b, id, _, _, q = before:find(IDLINK)
    if a then
      local ok, ids = pcall(require, 'org.id')
      local loc = ok and ids.find(id) or nil
      if not (loc and loc.filename) then return -3 end
      state.mode, state.linkstart, state.file = 'heading', a - 1, loc.filename
      return b - #q
    end
    local s, _, query = before:find('%[%[([^%]]*)$')
    if not s then return -3 end
    local scheme = query:match('^(%a+):')
    if scheme and SCHEMES[scheme] then return -3 end
    state.mode, state.linkstart, state.file = 'note', s - 1, nil
    return s + 1
  end

  state.input = base
  local list, query, headingsOnly = candidates(base, state.mode, state.file)
  state.items = list
  style.colors()
  local out = {}
  for i, e in ipairs(list) do
    local abbr, hl, kind
    if e.kind == 'note' then
      abbr, hl, kind = e.title, 'PureNoteFile', 'note'
    elseif e.kind == 'heading' then
      abbr, hl, kind = e.note .. ' › ' .. e.title, '@markup.heading.' .. math.min(e.level or 1, 6) .. '.markdown', 'head'
    elseif e.heading then
      abbr, hl, kind = e.title .. ' → ' .. e.note .. ' › ' .. e.target, 'PureNoteAlias', 'alias'
    else
      abbr, hl, kind = e.title .. ' → ' .. e.target, 'PureNoteAlias', 'alias'
    end
    out[#out + 1] = {
      word = e.title, abbr = abbr, kind = kind, menu = style.truncLeft(e.path, 28),
      abbr_hlgroup = hl, kind_hlgroup = 'PureNoteSep', menu_hlgroup = 'PureNoteSep',
      user_data = { pure_link = i },
      icase = 1, equal = 1,
    }
  end
  -- An alias (||) is for the note chosen, never for a new one.
  if state.mode == 'note' and query ~= '' and not headingsOnly and not aliasOf(base) then
    out[#out + 1] = {
      word = query, abbr = '+ New note: ' .. query, kind = 'new', menu = 'inbox',
      abbr_hlgroup = 'PureNoteAlias', kind_hlgroup = 'PureNoteSep', menu_hlgroup = 'PureNoteSep',
      user_data = { pure_link = 0, new = query },
      icase = 1, equal = 1,
    }
  end
  return { words = out, refresh = 'always' }
end

--- An item of the menu was taken: replace `[[...` by the link.
--- `snap`: what the menu was working on when the item was taken (the state moves on once the text changes).
local function accept(item, snap)
  local ud = item.user_data
  if type(ud) ~= 'table' or ud.pure_link == nil then return end
  snap = snap or state
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local cursor = api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local from = snap.linkstart
  local alias = snap.mode == 'note' and aliasOf(snap.input) or nil
  local entry = ud.pure_link > 0 and snap.items[ud.pure_link] or nil
  -- The note was picked (Tab, <C-n>) and then a | was typed, which ended the completion: that | is the
  -- start of a ||alias for the link, so it stays, in the text of the link.
  local seg = api.nvim_get_current_line():sub(from + 1, col)
  local tail = (not alias and snap.mode == 'note') and seg:match('|+$') or nil
  if ud.new then
    writeLink(buf, win, row, from, col, nil, { new = ud.new, alias = alias, tail = tail })
  elseif entry then
    writeLink(buf, win, row, from, col, entry, {
      alias = alias, tail = tail,
      after = snap.mode == 'heading' or entry.kind == 'heading' or entry.heading == true,
    })
  end
end

-- -----------------------------------------------------------------------------
--  Following a link that has a ||alias: the note gets the alias if it has none
-- -----------------------------------------------------------------------------
--  `[[id:ID][Title||alias]]` under the cursor, followed (<CR>, gx): before org.nvim jumps, the alias is looked for
--  in the :ROAM_ALIASES: of the note (or heading) the id names, and added when it is not there. The link is left
--  as it is written.
local function ensureAliasAtPoint()
  local line = api.nvim_get_current_line()
  local col = api.nvim_win_get_cursor(0)[2]
  local pos = 1
  while true do
    local s, e, id, text = line:find('%[%[id:([^%]]+)%]%[([^%]]*)%]%]', pos)
    if not s then return end
    if col >= s - 1 and col < e then
      local alias = text:match('||(.*)$')
      alias = alias and vim.trim(alias) or ''
      if alias == '' then return end
      local ok, ids = pcall(require, 'org.id')
      local loc = ok and ids.find(id) or nil
      if not (loc and loc.filename) then return end
      local _, _, added = ensureId(loc.filename, loc.lnum or 1, alias)
      if added then vim.notify(('Alias "%s" added to the note'):format(alias)) end
      return
    end
    pos = e + 1
  end
end

local followPatched = false
--- org.nvim's open_at_point is called by name for <CR>, gx and the rest: the check goes in front of it.
local function patchFollow()
  if followPatched then return end
  local ok, ctx = pcall(require, 'org.context')
  if not (ok and type(ctx.open_at_point) == 'function') then return end
  followPatched = true
  local orig = ctx.open_at_point
  ctx.open_at_point = function(...)
    if vim.g.pure_links_complete ~= false then pcall(ensureAliasAtPoint) end
    return orig(...)
  end
end

-- -----------------------------------------------------------------------------
--  [[id:ID][Title||alias]]: the alias of a link that is already there
-- -----------------------------------------------------------------------------
--  The note is usually picked from the menu first, and the alias typed after, inside the link: its text is
--  `Title||alias`. When the cursor leaves it (Enter, Esc, a move) it becomes `[[id:ID][alias]]` and the alias
--  is added to the :ROAM_ALIASES: of the note (or heading) the id names.
local ALIASLINK = '%[%[id:([^%]]+)%]%[([^%]]-)||([^%]]*)%]%]'

--- Resolve the `||alias` links of the current line. `force`: also the one the cursor is in (Enter).
--- @return boolean changed
local function resolveAliasLinks(buf, force)
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= buf then return false end
  local row, col = unpack(api.nvim_win_get_cursor(win))
  row = row - 1
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  if not line:find('||', 1, true) then return false end
  local ok, ids = pcall(require, 'org.id')
  if not ok then return false end

  local ns = api.nvim_create_namespace('pure_links_alias')
  local mark = api.nvim_buf_set_extmark(buf, ns, row, 0, {})
  local marks = api.nvim_buf_get_extmarks(buf, FRESH_NS, { row, 0 }, { row, -1 }, { details = true })
  local function isFresh(s0, e0)
    for _, m in ipairs(marks) do
      local c0, c1 = m[3], m[4].end_col
      if m[4].end_row == row and s0 < c1 and e0 > c0 then return true end
    end
    return false
  end
  local jobs, pos = {}, 1
  while true do
    local s, e, id, _, alias = line:find(ALIASLINK, pos)
    if not s then break end
    alias = vim.trim(alias)
    local inside = col >= s - 1 and col <= e
    if alias ~= '' and isFresh(s - 1, e) and (force or not inside) then jobs[#jobs + 1] = { s = s, e = e, id = id, alias = alias, inside = inside } end
    pos = e + 1
  end
  if #jobs == 0 then
    api.nvim_buf_del_extmark(buf, ns, mark)
    return false
  end

  local result, shift, newcol, changed = {}, 0, col, false
  local last = 1
  for _, j in ipairs(jobs) do
    local loc = ids.find(j.id)
    local done = loc and loc.filename and ensureId(loc.filename, loc.lnum or 1, j.alias)
    if done then
      local link = string.format('[[id:%s][%s]]', j.id, j.alias)
      result[#result + 1] = line:sub(last, j.s - 1)
      result[#result + 1] = link
      last = j.e + 1
      local delta = #link - (j.e - j.s + 1)
      if j.inside then newcol = j.s - 1 + #link elseif col > j.e then newcol = newcol + delta end
      changed = true
    end
  end
  result[#result + 1] = line:sub(last)
  -- Making the alias may have added lines above in this very buffer (a drawer): follow the line.
  local pos2 = api.nvim_buf_get_extmark_by_id(buf, ns, mark, {})
  api.nvim_buf_del_extmark(buf, ns, mark)
  row = pos2[1] or row
  if changed then
    api.nvim_buf_set_lines(buf, row, row + 1, false, { table.concat(result) })
    pcall(api.nvim_win_set_cursor, win, { row + 1, newcol })
    syncIndexSoon()
  end
  return changed
end

-- -----------------------------------------------------------------------------
--  Opening the menu
-- -----------------------------------------------------------------------------

local function feed()
  api.nvim_feedkeys(api.nvim_replace_termcodes('<C-x><C-u>', true, false, true), 'n', false)
end

--- A separator # * : typed at this place (not one that was already in a title).
local function freshSeparator(sepcol)
  local row = api.nvim_win_get_cursor(0)[1]
  return state.sepAt ~= nil and state.sepAt[1] == row and state.sepAt[2] == sepcol
end

--- The 'omnifunc' of org notes. org.nvim sets its own (links, files, tags, properties...) and the
--- 'autocomplete' of this configuration asks it as you type, so its menu came up on every [[ and ours never did.
--- This one answers for the [[ links (and the headings of a link) and hands every other question to org.nvim's.
function M.omnifunc(findstart, base)
  local function org()
    local ok, comp = pcall(require, 'org.completion')
    return ok and comp or nil
  end
  if findstart == 1 then
    state.via = nil
    if vim.g.pure_links_complete ~= false then
      local col = api.nvim_win_get_cursor(0)[2]
      local before = api.nvim_get_current_line():sub(1, col)
      local a, b, _, _, _, q = before:find(IDLINK)
      if not (a and not freshSeparator(b - #q - 1)) then
        local start = M.complete(1, base)
        if start ~= -3 then
          state.via = 'links'
          return start
        end
      end
    end
    state.via = 'org'
    local comp = org()
    return comp and comp.omnifunc(1, base) or -3
  end
  if state.via == 'links' then return M.complete(0, base) end
  local comp = org()
  return comp and comp.omnifunc(0, base) or {}
end

local function trigger(buf)
  if vim.g.pure_links_complete == false or vim.fn.pumvisible() == 1 then return end
  -- With 'autocomplete' the omnifunc above is asked as you type: no need to open the menu by hand.
  if vim.o.autocomplete and vim.o.complete:find('o', 1, true) then return end
  -- Not while an item was just taken: the text is about to be replaced by the link.
  if vim.uv.hrtime() < (state.quietUntil or 0) then return end
  if api.nvim_get_current_buf() ~= buf or not api.nvim_get_mode().mode:match('^i') then return end
  local col = api.nvim_win_get_cursor(0)[2]
  local before = api.nvim_get_current_line():sub(1, col)
  -- A # * : typed in the text of an id: link opens the headings of that note; one that was already
  -- there (a colon in a title) does not: only the separator typed at this place counts.
  local a, b, _, _, _, q = before:find(IDLINK)
  if a then
    local row = api.nvim_win_get_cursor(0)[1]
    if state.sepAt and state.sepAt[1] == row and state.sepAt[2] == b - #q - 1 then return feed() end
    return
  end
  local _, _, query = before:find('%[%[([^%]]*)$')
  if query then
    local scheme = query:match('^(%a+):')
    if not (scheme and SCHEMES[scheme]) then feed() end
  end
end

local function keys(text, mode)
  api.nvim_feedkeys(api.nvim_replace_termcodes(text, true, false, true), mode or 'ni', false)
end

--- Enter in insert mode: with our menu open it takes the highlighted item, or the first when none is
--- highlighted ('noselect' of this configuration leaves none: Enter would only have made a new line, and
--- a [[foo||short could never be written). Anything else is what Enter was (org.nvim's table row, ...).
local PREV_DESC = 'pure-links-enter'

--- Enter right after a typed `[[note||alias`, with no menu on screen (typed faster than the menu follows):
--- the link is written for the best match, or for a new note when nothing matches.
local function takeTyped()
  if vim.g.pure_links_complete == false then return false end
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(win))
  local before = api.nvim_get_current_line():sub(1, col)
  local _, _, typed = before:find('%[%[([^%]]*)$')
  if not typed or not typed:find('||', 1, true) then return false end
  local start = M.complete(1, '')
  if start == -3 or state.mode ~= 'note' then return false end
  local base = before:sub(start + 1)
  local list, query, headingsOnly = candidates(base, 'note', nil)
  state.input, state.items = base, list
  local alias = aliasOf(base)
  if list[1] then
    writeLink(buf, win, row - 1, state.linkstart, col, list[1], { alias = alias })
  else
    return false
  end
  return true
end

local function installEnter(buf)
  local cur = vim.fn.maparg('<CR>', 'i', false, true)
  if cur.desc == PREV_DESC and cur.buffer == 1 then return end
  -- What <CR> was: this buffer's (org.nvim's table row) or the global one (list item, Copilot, menu).
  local prev = (type(cur) == 'table' and cur.lhs) and cur or nil
  vim.keymap.set('i', '<CR>', function()
    -- Enter in the text of a link, after ||alias: the alias is written, no new line.
    if vim.g.pure_links_complete ~= false and api.nvim_get_current_line():find('||', 1, true) then
      local c = api.nvim_win_get_cursor(0)[2]
      if api.nvim_get_current_line():sub(1, c):find('%[%[id:[^%]]+%]%[[^%]]-||[^%]]*$') then
        if vim.fn.pumvisible() == 1 then keys('<C-e>') end
        if resolveAliasLinks(api.nvim_get_current_buf(), true) then return end
      end
    end
    if vim.fn.pumvisible() == 1 then
      local info = vim.fn.complete_info({ 'items', 'selected' })
      local function ours(it) return it and type(it.user_data) == 'table' and it.user_data.pure_link ~= nil end
      if info.selected >= 0 and ours(info.items[info.selected + 1]) then return keys('<C-y>') end
      if info.selected < 0 and ours(info.items[1]) then return keys('<C-n><C-y>') end
    elseif takeTyped() then
      return
    end
    if prev and prev.callback then
      local out = prev.callback()
      if prev.expr == 1 and type(out) == 'string' and out ~= '' then
        api.nvim_feedkeys(prev.replace_keycodes == 1 and api.nvim_replace_termcodes(out, true, false, true) or out, 'ni', false)
      end
      return
    end
    if prev and prev.rhs and prev.rhs ~= '' then return keys(prev.rhs, prev.noremap == 1 and 'ni' or 'mi') end
    keys('<CR>')
  end, { buffer = buf, desc = PREV_DESC })
end

local function attach(buf)
  patchFollow()
  if vim.b[buf].pure_links then return end
  vim.b[buf].pure_links = true
  vim.bo[buf].completefunc = "v:lua.require'pure.links'.complete"
  local OMNI = "v:lua.require'pure.links'.omnifunc"
  vim.bo[buf].omnifunc = OMNI
  vim.opt_local.completeopt = { 'menu', 'menuone', 'noinsert' }
  local group = api.nvim_create_augroup('PureLinks' .. buf, { clear = true })
  -- org.nvim sets its omnifunc when it attaches to the buffer, which can be after this: take it back.
  api.nvim_create_autocmd({ 'InsertLeavePre', 'CursorMovedI' }, {
    group = group,
    buffer = buf,
    callback = function(args)
      if vim.g.pure_links_complete == false then return end
      if args.event == 'InsertLeavePre' then return resolveAliasLinks(buf, true) end
      vim.schedule(function() resolveAliasLinks(buf, false) end)
    end,
  })
  api.nvim_create_autocmd({ 'BufEnter', 'InsertEnter' }, {
    group = group,
    buffer = buf,
    callback = function()
      if vim.bo[buf].omnifunc ~= OMNI then vim.bo[buf].omnifunc = OMNI end
      installEnter(buf)
    end,
  })
  installEnter(buf)
  api.nvim_create_autocmd('InsertCharPre', {
    group = group,
    buffer = buf,
    callback = function()
      if vim.v.char == '#' or vim.v.char == '*' or vim.v.char == ':' then
        local c = api.nvim_win_get_cursor(0)
        state.sepAt = { c[1], c[2] }
      end
    end,
  })
  api.nvim_create_autocmd('TextChangedI', { group = group, buffer = buf, callback = function() vim.schedule(function() trigger(buf) end) end })
  -- Tab / S-Tab move through the menu (otherwise they are what they were).
  vim.keymap.set('i', '<Tab>', function() return vim.fn.pumvisible() == 1 and '<C-n>' or '<Tab>' end, { buffer = buf, expr = true })
  vim.keymap.set('i', '<S-Tab>', function() return vim.fn.pumvisible() == 1 and '<C-p>' or '<S-Tab>' end, { buffer = buf, expr = true })
end

api.nvim_create_autocmd('CompleteDone', {
  group = api.nvim_create_augroup('PureLinksDone', { clear = true }),
  callback = function()
    local item = vim.v.completed_item
    if type(item) ~= 'table' or type(item.user_data) ~= 'table' or item.user_data.pure_link == nil then return end
    -- The text the completion wrote (the title of the item) must not open the menu again, and the
    -- state is kept now: the next menu would overwrite it.
    state.quietUntil = vim.uv.hrtime() + 600e6
    local snap = { mode = state.mode, linkstart = state.linkstart, input = state.input, items = state.items }
    -- After the completion has finished writing its own text.
    vim.schedule(function() accept(item, snap) end)
  end,
})

api.nvim_create_autocmd('FileType', {
  group = api.nvim_create_augroup('PureLinksAttach', { clear = true }),
  pattern = 'org',
  callback = function(args) attach(args.buf) end,
})
for _, b in ipairs(api.nvim_list_bufs()) do
  if api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'org' then attach(b) end
end

-- -----------------------------------------------------------------------------
--  <leader>vi: the picker of <leader>vf, inserting a link at the cursor
-- -----------------------------------------------------------------------------
function M.pick()
  local flora = require('pure.flora')
  local root = flora.path()
  if not root then return end
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local cursor = api.nvim_win_get_cursor(win)
  require('pure.notecolors').apply()
  local entries = flora._find.entries(root)
  local lines = {}
  for i, e in ipairs(entries) do
    lines[#lines + 1] = flora._find.line(e):match('^([^\t]*)') .. '\t' .. i
  end
  require('pure.fuzzyUtils').pickList(lines, {
    title = ' Link to ',
    ratio = 0.8,
    -- Enter on a title that matches nothing returns the query itself: a new note in the inbox.
    fzf = style.FZF .. ' --bind enter:accept-or-print-query',
  }, function(selection)
    if not (api.nvim_buf_is_valid(buf) and api.nvim_win_is_valid(win)) then return end
    local idx = tonumber(selection:match('\t(%d+)%s*$'))
    local row, col = cursor[1] - 1, cursor[2]
    local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
    -- After the character under the cursor, as `a` does (the start of an empty line).
    local at = line == '' and 0 or math.min(col + 1, #line)
    if idx and entries[idx] then
      writeLink(buf, win, row, at, at, entries[idx], { after = true })
    else
      local title = vim.trim(selection)
      if title ~= '' then writeLink(buf, win, row, at, at, nil, { new = title, after = true }) end
    end
  end)
end

-- Exposed for tests.
M._candidates, M._parse, M._ensureId, M._writeLink, M._accept = candidates, parse, ensureId, writeLink, accept
M._state = state

return M
