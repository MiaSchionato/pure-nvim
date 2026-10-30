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
local function candidates(input, mode, file)
  local headingsOnly, noteWords, query = parse(input)
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
  if id and alias then
    local _, f, hl = edit.resolve({ bufnr = buf, lnum = lnum })
    local names = splitQuoted((hl and hl.properties or f.properties).ROAM_ALIASES)
    if not vim.tbl_contains(names, alias) then
      names[#names + 1] = alias
      edit.set_property(buf, hl and hl.line or 1, 'ROAM_ALIASES', joinQuoted(names))
    end
  end
  if buf ~= api.nvim_get_current_buf() and not wasModified and vim.bo[buf].modified then
    api.nvim_buf_call(buf, function() vim.cmd('silent! write') end)
  end
  return id
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
  local link = string.format('[[id:%s][%s]]', id, text)
  api.nvim_buf_set_text(buf, row, from, row, to, { link })
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
  if state.mode == 'note' and query ~= '' and not headingsOnly then
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
  if ud.new then
    writeLink(buf, win, row, from, col, nil, { new = ud.new, alias = alias })
  elseif entry then
    writeLink(buf, win, row, from, col, entry, { alias = alias, after = snap.mode == 'heading' or entry.kind == 'heading' or entry.heading == true })
  end
end

-- -----------------------------------------------------------------------------
--  Opening the menu
-- -----------------------------------------------------------------------------

local function feed()
  api.nvim_feedkeys(api.nvim_replace_termcodes('<C-x><C-u>', true, false, true), 'n', false)
end

local function trigger(buf)
  if vim.g.pure_links_complete == false or vim.fn.pumvisible() == 1 then return end
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

local function attach(buf)
  if vim.b[buf].pure_links then return end
  vim.b[buf].pure_links = true
  vim.bo[buf].completefunc = "v:lua.require'pure.links'.complete"
  vim.opt_local.completeopt = { 'menu', 'menuone', 'noinsert' }
  local group = api.nvim_create_augroup('PureLinks' .. buf, { clear = true })
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
