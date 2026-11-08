-- =============================================================================
--  orgls: what the org notes of a vault know about each other
-- =============================================================================
--  One file for the part of the setup that answers "what is in the vault, where does this link go, is it
--  right". It was spread over pure/vault.lua (reading the vault) and pure/links.lua (finding, linking,
--  checking); it is merged here, the code as it was, so a language server can be built from one place.
--
--  Order:
--    1. The vault    path, parsing a note, the entries (notes, headings, aliases)   (from pure/vault.lua)
--    2. The rest     pure/links.lua in its own order: text helpers, search, IDs and aliases, writing the
--                    link, the [[ menu, resolving a spec, reconcile (diagnostics), the alias of a link,
--                    omnifunc, <CR>/<Tab>, attach
--    3. M.setup()    the autocmds that used to run when pure/links.lua was loaded (not called yet)
--    4. The server   an in-process language server (textDocument/hover); the file returns its config,
--                    which configs/lspConfigs.lua loads ('orgls' is in its list)
--
--  NOT moved: the fzf picker (vault.find, links.pick: <leader>vf and <leader>vi) and the other vault
--  commands (rename, delete, sync, backlinks, preview). They are the picker's, not the vault's.
--  The original modules are untouched and still the ones in use for the [[ menu and the checks. Do not call
--  M.setup() while pure.links is loaded: both use the same buffer variable, autocmd groups and namespaces.
--
--  Changes from the originals: completefunc/omnifunc point to this module; `pure.vault.path()` and
--  `_find.entries` became the local M.path / findEntries; the load-time autocmds went into M.setup(); the
--  entries carry the :ID: of the note or heading (`id`); the duplicate M and header were dropped; the exports
--  for tests lost `pick`.
--
--  Settings (configs.lua):
--    vim.g.pure_links_complete   false turns the [[ menu off (default on)
--    vim.g.pure_links_reconcile  false turns the check of hand-written links off
--    vim.g.orgls_vault           the vault folder (default: vim.g.pure_vault, the setting of this config)
--    vim.g.orgls_inbox           the file new notes are made in, relative to the vault (default inbox.org)
--    vim.g.orgls_new_keyword     the todo keyword of a new note (default SEED)
-- =============================================================================

local M = {}

local api = vim.api
local style = require('pure.pickerstyle')

-- =============================================================================
--  1. The vault (from pure/vault.lua)
-- =============================================================================
local function warn(msg) vim.notify('orgls: ' .. msg, vim.log.levels.WARN) end

--- The vault folder, normalized: vim.g.orgls_vault, else the setting this config already has (vim.g.pure_vault).
--- A separate project drops the second one.
local function vaultDir()
  return vim.fs.normalize(vim.fn.expand(vim.g.orgls_vault or vim.g.pure_vault or ''))
end

--- The vault folder, or nil (with a warning) when it is not there.
function M.path()
  local dir = vaultDir()
  if vim.fn.isdirectory(dir) == 0 then
    warn('folder not found: ' .. dir)
    return nil
  end
  return dir
end

local function roamDb()
  local ok, db = pcall(require, 'org.extensions.roam.db')
  if not ok then warn('the roam extension is not loaded') return nil end
  return db
end

local FIND_MAX_LEVEL = 4

local parsed = {} -- file -> { mtime, title, aliases, headings = { { level, text, lnum, aliases } } }

local function parseFile(path)
  local stat = vim.uv.fs_stat(path)
  local hit = parsed[path]
  if hit and stat and hit.mtime == stat.mtime.sec then return hit end
  local ok, lines = pcall(vim.fn.readfile, path)
  local info = { mtime = stat and stat.mtime.sec or 0, title = nil, aliases = {}, headings = {} }
  if not ok then return info end
  local current, block
  local owner = 'note' -- who a following :ID: belongs to: 'note', a heading (table) or 'deep' (below FIND_MAX_LEVEL: not indexed)
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
      local id = line:match('^%s*:ID:%s+(%S+)')
      if title and not info.title and title ~= '' then
        info.title = title
      elseif id then
        if owner == 'note' then info.id = info.id or id elseif owner ~= 'deep' then owner.id = owner.id or id end
      elseif stars then
        current = nil
        owner = 'deep'
        local text = rest:gsub('^%u%u+%s+', ''):gsub('^%[#%u%]%s+', ''):gsub('%s+:[%w_@#%%:]+:%s*$', '')
        text = vim.trim(text)
        if #stars <= FIND_MAX_LEVEL and text ~= '' then
          current = { level = #stars, text = text, lnum = i, aliases = {} }
          info.headings[#info.headings + 1] = current
          owner = current
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
    local top = { vim.tbl_extend('force', base, { kind = 'note', title = note, lnum = 1, id = info.id }) }
    for _, a in ipairs(info.aliases) do
      top[#top + 1] = vim.tbl_extend('force', base, { kind = 'alias', title = a, target = note, lnum = 1 })
    end
    local inside = {}
    for _, h in ipairs(info.headings) do
      inside[#inside + 1] = vim.tbl_extend('force', base, { kind = 'heading', title = h.text, level = h.level, lnum = h.lnum, id = h.id })
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

-- =============================================================================
--  2. Links between notes (from pure/links.lua)
-- =============================================================================
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
  local root = M.path()
  if not root then return {} end
  return findEntries(root)
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

--- A new note (a headline with the new-note keyword) called `title` at the end of the inbox, without opening it: (file, lnum).
local function createSeed(title)
  local root = M.path()
  if not root then return nil end
  local inbox = root .. '/' .. (vim.g.orgls_inbox or 'inbox.org')
  local buf = vim.fn.bufnr(inbox)
  local lines
  if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
    lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  else
    lines = vim.fn.filereadable(inbox) == 1 and vim.fn.readfile(inbox) or {}
  end
  if #lines > 0 and lines[#lines] ~= '' then lines[#lines + 1] = '' end
  local first = #lines + 1
  vim.list_extend(lines, { '* ' .. (vim.g.orgls_new_keyword or 'SEED') .. ' ' .. title, ':PROPERTIES:', ':CREATED:  [' .. os.date('%Y-%m-%d %a %H:%M') .. ']', ':END:' })
  if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    api.nvim_buf_call(buf, function() vim.cmd('silent! write') end)
  else
    vim.fn.writefile(lines, inbox)
  end
  return inbox, first
end

local syncPending = false
--- The roam index learns of the new id or alias a moment later, once however many were made. The index's own
--- sync is called (silent), not `:Org roam_db_sync`, which says "org-roam: N nodes ..." every time.
local function syncIndexSoon()
  if syncPending then return end
  syncPending = true
  vim.defer_fn(function()
    syncPending = false
    local ok, db = pcall(require, 'org.extensions.roam.db')
    if ok and type(db.sync) == 'function' then pcall(db.sync, false) end
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
  if opts.alias then
    -- The text keeps what the link is to, and the alias after ||: the render shows only the alias.
    local display
    if opts.new then
      display = opts.new
    elseif entry.kind == 'heading' then
      display = entry.note .. '#' .. entry.title
    elseif entry.kind == 'alias' then
      display = entry.heading and (entry.note .. '#' .. entry.target) or entry.target
    else
      display = entry.title
    end
    text = display .. '||' .. opts.alias
  end

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
      -- Columns (0-based) of the id, of the # * : typed, for the accept: only these change.
      state.idfrom = a - 1 + #'[[id:'
      state.idto = state.idfrom + #id
      state.sepcol = b - #q - 1
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
      -- In a link that is already there the menu must not write: the accept changes only the id and completes
      -- the typed text (see accept).
      word = state.mode == 'heading' and base or e.title, dup = 1,
      abbr = abbr, kind = kind, menu = style.truncLeft(e.path, 28),
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
--- A heading taken in a link that is already there (`[[id:ID][Note#he|]]`): only the id changes, to the heading's,
--- and the typed text is completed (`Note#Heading`, the # whichever of # * : was typed); the brackets, the text
--- before and what follows are left as they are.
local function changeTarget(buf, win, row, col, snap, entry)
  local file, lnum = targetOf(entry)
  if lnum > 1 then
    lnum = headingLine(file, lnum, entry.kind == 'alias' and entry.target or entry.title)
    if not lnum then return vim.notify('Link: that heading is gone', vim.log.levels.WARN) end
  end
  -- Making the id may add lines above (a drawer, in this very buffer): follow the line.
  local ns = api.nvim_create_namespace('pure_links')
  local mark = api.nvim_buf_set_extmark(buf, ns, row, 0, {})
  local id = ensureId(file, lnum)
  local pos = api.nvim_buf_get_extmark_by_id(buf, ns, mark, {})
  api.nvim_buf_del_extmark(buf, ns, mark)
  if not id then return end
  row = pos[1] or row
  local title = entry.kind == 'alias' and entry.target or entry.title
  -- From the right: the text first, so the columns of the id do not move.
  api.nvim_buf_set_text(buf, row, snap.sepcol, row, col, { '#' .. title })
  api.nvim_buf_set_text(buf, row, snap.idfrom, row, snap.idto, { id })
  pcall(api.nvim_win_set_cursor, win, { row + 1, snap.sepcol + 1 + #title + (#id - (snap.idto - snap.idfrom)) })
  syncIndexSoon()
end

local function accept(item, snap)
  local ud = item.user_data
  if type(ud) ~= 'table' or ud.pure_link == nil then return end
  snap = snap or state
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local cursor = api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  if snap.mode == 'heading' and snap.sepcol and ud.pure_link > 0 and snap.items[ud.pure_link] then
    return changeTarget(buf, win, row, col, snap, snap.items[ud.pure_link])
  end
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

-- -----------------------------------------------------------------------------
--  Links written by hand: the text decides where they go
-- -----------------------------------------------------------------------------
--  Writing is the workflow, the menu only tells what exists. So the TEXT of a link is what it is to:
--    [[Note#Heading||alias]]              typed whole, no id: becomes [[id:ID][Note#Heading||alias]]
--    [[id:ID][Note#Heading||alias]]       the text edited: the id is changed to the one of that heading
--  Words are enough (`[[nota li#bud||x]]`) as long as they name ONE note (and ONE heading of it); the text is
--  then made canonical (`Nota linkada#Budget||x`), the target gets its :ID: now if it had none, and the alias goes
--  into its :ROAM_ALIASES:. A link whose text names nothing is left alone and flagged as a diagnostic.
--  When: on :w (every link of the buffer that was not already checked) and when a link is followed (<CR>, gx),
--  so that it goes where its text says. A link with no || is just text with an id and is never reinterpreted.
local verified = {} -- buf -> { [text of the link] = true }: already consistent, not looked at again
local DIAG_NS = api.nvim_create_namespace('pure_links_diag')
local RECON_NS = api.nvim_create_namespace('pure_links_recon')

--- The one entry of `list` (several entries of a file count once; of a note and its archive copy, the live one), or nil.
local function unique(list)
  local byTarget, n, live = {}, 0, {}
  for _, e in ipairs(list) do
    local file, lnum = targetOf(e)
    local k = file .. '\0' .. lnum
    if not byTarget[k] then
      byTarget[k] = e
      n = n + 1
      if not e.archive then live[#live + 1] = e end
    end
  end
  if n == 1 then return select(2, next(byTarget)) end
  if #live == 1 then return live[1] end
  return nil
end

local function findNote(entries, name)
  local q = fold(vim.trim(name))
  if q == '' then return nil end
  local ws = words(name)
  local exact, loose = {}, {}
  for _, e in ipairs(entries) do
    if e.kind == 'note' or (e.kind == 'alias' and not e.heading) then
      local t = fold(e.title)
      if t == q then exact[#exact + 1] = e elseif hasAll(t, ws) then loose[#loose + 1] = e end
    end
  end
  return unique(exact) or unique(loose)
end

local function findHeading(entries, file, text)
  local q = fold(vim.trim(text))
  if q == '' then return nil end
  local ws = words(text)
  local exact, loose = {}, {}
  for _, e in ipairs(entries) do
    if samePath(e.file, file) and (e.kind == 'heading' or (e.kind == 'alias' and e.heading)) then
      local t = fold(e.title)
      if t == q then exact[#exact + 1] = e elseif hasAll(t, ws) then loose[#loose + 1] = e end
    end
  end
  return unique(exact) or unique(loose)
end

--- Where the text `spec` ("Note", "Note#Heading", "Note*Heading", "Note:Heading") points to:
--- { file, lnum, text = canonical text } or nil. The whole text is tried as a note first (a title with a colon).
local function resolveSpec(entries, spec)
  spec = vim.trim(spec)
  local function noteTitle(e) return (e.kind == 'alias') and e.target or e.title end
  local note = findNote(entries, spec)
  if note then return { file = note.file, lnum = 1, text = noteTitle(note) } end
  for i = 1, #spec do
    local c = spec:sub(i, i)
    if c == '#' or c == '*' or c == ':' then
      local left, right = vim.trim(spec:sub(1, i - 1)), vim.trim(spec:sub(i + 1))
      local n = left ~= '' and right ~= '' and findNote(entries, left) or nil
      local h = n and findHeading(entries, n.file, right) or nil
      if h then
        return { file = n.file, lnum = h.lnum, text = noteTitle(n) .. '#' .. (h.kind == 'alias' and h.target or h.title) }
      end
    end
  end
  return nil
end

--- The links of a line that are about where they go: { s, e (1-based, inclusive), kind, id, spec, alias, inner }.
local function scanLinks(line)
  local out, pos = {}, 1
  while true do
    local s, e, inner = line:find('%[%[(.-)%]%]', pos)
    if not s then break end
    pos = e + 1
    local id, desc = inner:match('^id:([^%]]+)%]%[(.*)$')
    if id then
      local spec, alias = desc:match('^(.-)||(.*)$')
      if spec then
        out[#out + 1] = { s = s, e = e, kind = 'id', id = id, spec = vim.trim(spec), alias = vim.trim(alias), inner = inner }
      end
    elseif inner ~= '' and not inner:find('%]%[') and not inner:find('[/\\]') and not inner:match('^[*#.~]') then
      local scheme = inner:match('^(%a[%w+.-]*):')
      if not (scheme and SCHEMES[scheme:lower()]) then
        local spec, alias = inner:match('^(.-)||(.*)$')
        out[#out + 1] = {
          s = s, e = e, kind = 'raw', spec = vim.trim(spec or inner), alias = alias and vim.trim(alias) or nil, inner = inner,
        }
      end
    end
  end
  return out
end

--- Make the links of the buffer say where they go. `at`: { row (0-based), col } = only the link there (a follow).
--- @return integer changed
local function reconcile(buf, at)
  if vim.g.pure_links_reconcile == false then return 0 end
  local okId, ids = pcall(require, 'org.id')
  if not okId then return 0 end
  local entries = allEntries()
  if #entries == 0 then return 0 end
  verified[buf] = verified[buf] or {}
  local seen = verified[buf]
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local jobs, diags = {}, {}

  for row0, line in ipairs(lines) do
    local row = row0 - 1
    if line:find('[[', 1, true) and (not at or at.row == row) then
      for _, L in ipairs(scanLinks(line)) do
        local here = not at or (at.col >= L.s - 1 and at.col < L.e)
        if here and not seen[L.inner] then
          local r = resolveSpec(entries, L.spec)
          if not r then
            -- Said to be a link (an id, or an alias) but names nothing: tell. A plain [[text]] may be an org link.
            if at == nil and (L.kind == 'id' or L.alias) then
              diags[#diags + 1] = {
                lnum = row, col = L.s - 1, end_lnum = row, end_col = L.e, severity = vim.diagnostic.severity.WARN,
                source = 'links', message = 'No single note or heading named "' .. L.spec .. '"',
              }
            end
          else
            local alias = (L.alias and L.alias ~= '') and L.alias or nil
            local text = r.text .. (alias and ('||' .. alias) or '')
            local same = false
            if L.kind == 'id' then
              local loc = ids.find(L.id)
              same = loc ~= nil and loc.filename ~= nil and samePath(loc.filename, r.file) and (loc.lnum or 1) == r.lnum
            end
            if same and L.inner:match('^id:[^%]]+%]%[(.*)$') == text then
              -- Already says where it goes: only its alias is made sure of.
              seen[L.inner] = true
              if alias then jobs[#jobs + 1] = { row = row, L = L, r = r, text = text, alias = alias, keep = true } end
            else
              jobs[#jobs + 1] = { row = row, L = L, r = r, text = text, alias = alias }
            end
          end
        end
      end
    end
  end
  if not at then vim.diagnostic.set(DIAG_NS, buf, diags) end
  if #jobs == 0 then return 0 end

  -- The links follow the lines that making an id may add above (a drawer, in this very buffer).
  for _, j in ipairs(jobs) do
    j.mark = api.nvim_buf_set_extmark(buf, RECON_NS, j.row, j.L.s - 1, { end_row = j.row, end_col = j.L.e })
  end
  -- Ids from the bottom of each file up: making one adds lines (its drawer), and the heading below it would
  -- otherwise be looked for where it no longer is.
  local order = {}
  for _, j in ipairs(jobs) do order[#order + 1] = j end
  table.sort(order, function(a, b)
    if a.r.file ~= b.r.file then return a.r.file < b.r.file end
    return a.r.lnum > b.r.lnum
  end)
  for _, j in ipairs(order) do
    j.id = ensureId(j.r.file, j.r.lnum, j.alias)
  end
  local function where(j) return api.nvim_buf_get_extmark_by_id(buf, RECON_NS, j.mark, { details = true }) end
  table.sort(jobs, function(a, b)
    local pa, pb = where(a), where(b)
    if pa[1] ~= pb[1] then return pa[1] > pb[1] end
    return pa[2] > pb[2]
  end)
  local changed = 0
  for _, j in ipairs(jobs) do
    local pos = where(j)
    api.nvim_buf_del_extmark(buf, RECON_NS, j.mark)
    if j.id then
      local inner = ('id:%s][%s'):format(j.id, j.text)
      seen[inner] = true
      if not j.keep and pos[1] then
        local link = '[[' .. inner .. ']]'
        local ok = pcall(api.nvim_buf_set_text, buf, pos[1], pos[2], pos[1], pos[3].end_col, { link })
        if ok then changed = changed + 1 end
      end
    end
  end
  if changed > 0 then syncIndexSoon() end
  return changed
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
    if vim.g.pure_links_complete ~= false then
      local buf = api.nvim_get_current_buf()
      local cur = api.nvim_win_get_cursor(0)
      pcall(reconcile, buf, { row = cur[1] - 1, col = cur[2] })
      pcall(ensureAliasAtPoint)
    end
    return orig(...)
  end
end

-- -----------------------------------------------------------------------------
--  [[id:ID][Title||alias]]: the alias of a link that is already there
-- -----------------------------------------------------------------------------
--  The note is usually picked from the menu first, and the alias typed after, inside the link: its text is
--  `Title||alias`. When the cursor leaves it (Enter, Esc, a move) it becomes `[[id:ID][alias]]` and the alias
--  is added to the :ROAM_ALIASES: of the note (or heading) the id names.
local aliasDone = {} -- id .. NUL .. alias, already saved in this session
local ALIASLINK = '%[%[id:([^%]]+)%]%[([^%]]-)||([^%]]*)%]%]'

--- Save the `||alias` of the links of the current line. `force`: also the one the cursor is in. `move`: the cursor
--- then goes after the link it was in (only Enter: any other event must leave the cursor where it is).
--- @return boolean changed
local function resolveAliasLinks(buf, force, move)
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

  -- The alias goes into the :ROAM_ALIASES: of the note (or heading) the id names; the text of the link is
  -- left as it is (`Note#Heading||alias`: the render shows the alias only). Each alias once per session.
  local newcol, changed, wrote = col, false, false
  for _, j in ipairs(jobs) do
    local key = j.id .. '\0' .. j.alias
    if not aliasDone[key] then
      local loc = ids.find(j.id)
      local done, _, added
      if loc and loc.filename then done, _, added = ensureId(loc.filename, loc.lnum or 1, j.alias) end
      if done then aliasDone[key] = true end
      if added then wrote = true end
    end
    -- Enter inside the link: the cursor goes after it.
    if j.inside and move then newcol = j.e; changed = true end
  end
  -- Making the alias may have added lines above in this very buffer (a drawer): follow the line.
  local pos2 = api.nvim_buf_get_extmark_by_id(buf, ns, mark, {})
  api.nvim_buf_del_extmark(buf, ns, mark)
  row = pos2[1] or row
  if changed then pcall(api.nvim_win_set_cursor, win, { row + 1, newcol }) end
  if wrote then syncIndexSoon() end
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
        if resolveAliasLinks(api.nvim_get_current_buf(), true, true) then return end
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
  -- On :w: the links typed by hand (or edited) are made to say where they go, before the file is written.
  api.nvim_create_autocmd('BufWritePre', {
    group = api.nvim_create_augroup('PureLinksSave' .. buf, { clear = true }),
    buffer = buf,
    callback = function()
      local ok, err = pcall(reconcile, buf)
      if not ok then vim.notify('Links: ' .. tostring(err), vim.log.levels.WARN) end
    end,
  })
  vim.bo[buf].completefunc = "v:lua.require'lsp.orgls'.complete"
  local OMNI = "v:lua.require'lsp.orgls'.omnifunc"
  vim.bo[buf].omnifunc = OMNI
  vim.opt_local.completeopt = { 'menu', 'menuone', 'noinsert' }
  local group = api.nvim_create_augroup('PureLinks' .. buf, { clear = true })
  -- org.nvim sets its omnifunc when it attaches to the buffer, which can be after this: take it back.
  api.nvim_create_autocmd({ 'InsertLeavePre', 'CursorMovedI' }, {
    group = group,
    buffer = buf,
    callback = function(args)
      if vim.g.pure_links_complete == false then return end
      -- A failure must not be silent: the alias would just not be saved.
      local function run(force)
        local ok, err = pcall(resolveAliasLinks, buf, force)
        if not ok then
          vim.g.pure_links_last_error = tostring(err)
          vim.notify('Link alias: ' .. tostring(err), vim.log.levels.WARN)
        end
      end
      if args.event == 'InsertLeavePre' then return run(true) end
      vim.schedule(function() run(false) end)
    end,
  })
  -- Out of insert mode too (Esc with a menu open, a move, an idle moment): the alias of a link left behind is
  -- saved all the same. Each alias once per session, so this costs nothing when there is nothing to do.
  api.nvim_create_autocmd({ 'InsertLeave', 'CursorMoved', 'CursorHold' }, {
    group = group,
    buffer = buf,
    callback = function()
      if vim.g.pure_links_complete == false then return end
      local ok, err = pcall(resolveAliasLinks, buf, true)
      if not ok then vim.g.pure_links_last_error = tostring(err) end
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


-- =============================================================================
--  3. The editor side, started by M.setup()
-- =============================================================================
--  What ran when pure/links.lua was loaded: the autocmds that attach the [[ menu, the alias saving and the
--  rest to org buffers. Nothing calls setup() yet (pure.links is the one in use); loading this module does not
--  start any of it, so the language server below can be loaded alone.
local setupDone = false

function M.setup()
  if setupDone then return end
  setupDone = true
  api.nvim_create_autocmd('CompleteDone', {
    group = api.nvim_create_augroup('PureLinksDone', { clear = true }),
    callback = function()
      local item = vim.v.completed_item
      if type(item) ~= 'table' or type(item.user_data) ~= 'table' or item.user_data.pure_link == nil then return end
      -- The text the completion wrote (the title of the item) must not open the menu again, and the
      -- state is kept now: the next menu would overwrite it.
      state.quietUntil = vim.uv.hrtime() + 600e6
      local snap = {
        mode = state.mode, linkstart = state.linkstart, input = state.input, items = state.items,
        idfrom = state.idfrom, idto = state.idto, sepcol = state.sepcol,
      }
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
end

-- =============================================================================
--  4. The language server (in-process): textDocument/hover
-- =============================================================================
--  No executable: `cmd` is a function that returns the server object the client talks to. The server runs
--  in this Neovim, so it reads the buffers themselves (what is not saved yet shows) and needs no didChange.
--  Hover is on the link under the cursor: the note (or the section) it points to, as an org block; a link
--  that names nothing says so. K (lsp.hover) and the automatic hover (configs/lspConfigs.lua) show it.
local HOVER_MAX_LINES = 40

--- The link of `line` that covers the 0-based byte column `col`: { s, e (1-based, inclusive), inner } or nil.
local function linkAt(line, col)
  local pos = 1
  while true do
    local s, e, inner = line:find('%[%[(.-)%]%]', pos)
    if not s then return nil end
    if col >= s - 1 and col < e then return { s = s, e = e, inner = inner } end
    pos = e + 1
  end
end

--- Where a link points: { file, lnum, label }, or nil and a message when it names nothing, or nil alone when it
--- is not a link to a note (a web link).
local function linkTarget(bufnr, inner)
  local id = inner:match('^id:([^%]]+)')
  if id then
    for _, e in ipairs(allEntries()) do
      if e.id == id and (e.kind == 'note' or e.kind == 'heading') then
        return { file = e.file, lnum = e.lnum, label = e.note .. (e.kind == 'heading' and (' › ' .. e.title) or '') }
      end
    end
    -- A heading below the indexed levels: org.nvim's roam knows every level.
    local ok, ids = pcall(require, 'org.id')
    local loc = ok and ids.find(id) or nil
    if loc and loc.filename then
      return { file = vim.fs.normalize(loc.filename), lnum = loc.lnum or 1, label = vim.fn.fnamemodify(loc.filename, ':t:r') }
    end
    return nil, 'No note or heading with the id ' .. id
  end
  local scheme = inner:match('^(%a[%w+.-]*):')
  if scheme and scheme:lower() == 'file' then
    local file = inner:sub(#scheme + 2):gsub('::.*$', ''):gsub('%]%[.*$', '')
    if vim.fn.isabsolutepath(file) == 0 then file = vim.fs.dirname(api.nvim_buf_get_name(bufnr)) .. '/' .. file end
    file = vim.fs.normalize(file)
    if vim.uv.fs_stat(file) then return { file = file, lnum = 1, label = vim.fn.fnamemodify(file, ':t:r') } end
    return nil, 'File not found: ' .. file
  end
  if scheme and SCHEMES[scheme:lower()] then return nil end
  local spec = vim.trim((inner:match('^([^%]]*)') or ''):gsub('||.*$', ''))
  if spec == '' then return nil end
  local r = resolveSpec(allEntries(), spec)
  if r then return { file = r.file, lnum = r.lnum, label = (r.text:gsub('#', ' › ')) } end
  return nil, 'No single note or heading named "' .. spec .. '"'
end

--- The lines of a node: its subtree when `row` is a headline, else the whole file; the properties drawer at the
--- top is left out.
local function nodeLines(path, row)
  local nr = vim.fn.bufnr(path)
  local lines
  if nr ~= -1 and api.nvim_buf_is_loaded(nr) then
    lines = api.nvim_buf_get_lines(nr, 0, -1, false)
  else
    local ok, read = pcall(vim.fn.readfile, path)
    lines = ok and read or {}
  end
  local stars = (lines[row] or ''):match('^(%*+)%s')
  if stars then
    local last = #lines
    for i = row + 1, #lines do
      local s = lines[i]:match('^(%*+)%s')
      if s and #s <= #stars then last = i - 1 break end
    end
    lines = vim.list_slice(lines, row, last)
  end
  for i = 1, math.min(2, #lines) do
    if lines[i]:match('^%s*:PROPERTIES:%s*$') then
      for j = i + 1, #lines do
        if lines[j]:match('^%s*:END:%s*$') then
          lines = vim.list_extend(vim.list_slice(lines, 1, i - 1), vim.list_slice(lines, j + 1))
          break
        end
      end
      break
    end
  end
  if #lines > HOVER_MAX_LINES then
    lines = vim.list_slice(lines, 1, HOVER_MAX_LINES)
    lines[#lines + 1] = '…'
  end
  return lines
end

--- textDocument/hover: nil when the cursor is not on a link to a note.
local function hover(params)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local line = api.nvim_buf_get_lines(bufnr, params.position.line, params.position.line + 1, false)[1]
  if not line then return nil end
  local okCol, col = pcall(vim.str_byteindex, line, 'utf-16', params.position.character, false)
  local L = linkAt(line, okCol and col or params.position.character)
  if not L then return nil end
  local target, missing = linkTarget(bufnr, L.inner)
  if not target then
    if not missing then return nil end
    return { contents = { kind = 'markdown', value = missing } }
  end
  -- Four backticks: a note may hold three.
  local body = table.concat(nodeLines(target.file, target.lnum), '\n')
  return { contents = { kind = 'markdown', value = '**' .. target.label .. '**\n\n````org\n' .. body .. '\n````' } }
end

local function inVault(path)
  local dir = vaultDir()
  if path == '' or vim.fn.isdirectory(dir) == 0 then return nil end
  local p = vim.fs.normalize(vim.uv.fs_realpath(path) or path)
  local d = vim.fs.normalize(vim.uv.fs_realpath(dir) or dir)
  if vim.fn.has('win32') == 1 then p, d = p:lower(), d:lower() end
  return p:sub(1, #d + 1) == d .. '/' and dir or nil
end

--- The server object for vim.lsp: request, notify, is_closing, terminate.
local function server()
  local closing, nextId = false, 0
  local srv = {}
  function srv.request(method, params, callback)
    nextId = nextId + 1
    local err, result
    if method == 'initialize' then
      result = {
        capabilities = { hoverProvider = true, textDocumentSync = { openClose = true, change = 0 } },
        serverInfo = { name = 'orgls' },
      }
    elseif method == 'textDocument/hover' then
      local ok, res = pcall(hover, params)
      if ok then result = res else err = { code = -32603, message = 'orgls: ' .. tostring(res) } end
    elseif method ~= 'shutdown' then
      err = { code = -32601, message = 'orgls: method not supported: ' .. method }
    end
    vim.schedule(function() callback(err, result) end)
    return true, nextId
  end
  function srv.notify() return true end
  function srv.is_closing() return closing end
  function srv.terminate() closing = true end
  return srv
end

-- Exposed for tests.
M._candidates, M._parse, M._ensureId, M._writeLink, M._accept = candidates, parse, ensureId, writeLink, accept
M._resolve = resolveAliasLinks
M._reconcile, M._resolveSpec = reconcile, resolveSpec
M._state = state
M._entries = findEntries
M._hover, M._linkAt, M._linkTarget, M._nodeLines = hover, linkAt, linkTarget, nodeLines

--- What configs/lspConfigs.lua loads: the config of the server (the module itself is `_module`, for tests).
return {
  cmd = server,
  filetypes = { 'org' },
  -- Only the notes of the vault (other .org files have no server).
  root_dir = function(bufnr, on_dir)
    local root = inVault(api.nvim_buf_get_name(bufnr))
    if root then on_dir(root) end
  end,
  _module = M,
}
