-- =============================================================================
--  Notes
-- =============================================================================
--  The part of obsidian.nvim this configuration used, in the vault of
--  pure/zettelkasten.lua, with links Obsidian reads the same way:
--
--    <CR>, K      on a link: follow it ([[Note]], [[Note#Heading]],
--                 [[Note#^block]], [[Note|alias]], ![[embed]],
--                 [text](Note.md), https://...). A note that does not exist
--                 yet is created (asked first), where Obsidian would put it.
--                 On a checkbox: toggle it. On a heading: fold it. Inside a
--                 ```todoist block: open its tasks.
--    [[           lists the vault's notes as you type; after [[Note# its
--                 headings.
--    <leader>nr   rename the note, and fix every link to it (wikilinks,
--                 markdown links, canvases).
--    <leader>fl   the notes that link to this one (backlinks).
--
--  Moving or renaming notes in oil fixes the links too.
--
--  Works in any markdown buffer (the Todoist list too); links resolve in the
--  vault. Obsidian's rules: case does not matter, [[Note]] is any Note.md
--  in the vault (the one in the same folder first, else the shortest path),
--  [[folder/Note]] a path, and a file that is not markdown keeps its
--  extension ([[photo.png]]). New notes go where Obsidian's own setting says
--  (Settings > Files and links > Default location for new notes, read from
--  .obsidian/app.json): the vault root, the current note's folder, or a
--  given folder.
-- =============================================================================

local M = {}

local function zet() return require('pure.zettelkasten') end

local function vault()
  local ok, root = pcall(function() return zet().vaultPath() end)
  if not ok or not root or vim.fn.isdirectory(root) == 0 then return nil end
  return (vim.fs.normalize(root):gsub('/$', ''))
end

--- Obsidian ignores case in links (and so do Windows and macOS file names).
local function lower(s) return vim.fn.tolower(s) end

--- `path` relative to `root`, or nil when it is not inside it.
local function relTo(root, path)
  path = vim.fs.normalize(path)
  local r, p = lower(root) .. '/', lower(path)
  if p:sub(1, #r) ~= r then return nil end
  return path:sub(#r + 1)
end

--- a/b/../c -> a/c, ./x -> x.
local function collapse(path)
  local out = {}
  for part in path:gmatch('[^/]+') do
    if part == '..' then
      if #out == 0 then return nil end
      table.remove(out)
    elseif part ~= '.' then
      table.insert(out, part)
    end
  end
  return table.concat(out, '/')
end

local function dirOf(rel)
  return rel:match('^(.*)/[^/]*$') or ''
end

local function stemOf(rel)
  local base = rel:match('[^/]*$')
  return (base:gsub('%.md$', ''))
end

-- -----------------------------------------------------------------------------
--  The vault's files
-- -----------------------------------------------------------------------------
--  Every file of the vault (not the hidden folders: .obsidian, .trash), as
--  paths relative to it. Listed again when older than a few seconds, or
--  after a note is written, created or renamed here.

local cache = { time = 0 }

--- An index of `files` (relative paths): by path and by link name.
local function indexOf(files)
  local idx = { files = files, by_path = {}, by_name = {} }
  for _, f in ipairs(files) do
    idx.by_path[lower(f)] = f
    -- Markdown notes are linked without ".md"; other files with their
    -- extension.
    local name = lower(f:match('[^/]*$'))
    for _, n in ipairs(f:match('%.md$') and { (name:gsub('%.md$', '')), name } or { name }) do
      idx.by_name[n] = idx.by_name[n] or {}
      table.insert(idx.by_name[n], f)
    end
  end
  return idx
end

local function listFiles(root)
  if vim.fn.executable('rg') == 1 then
    local res = vim.system({ 'rg', '--files', '--path-separator', '/' }, { cwd = root, text = true }):wait()
    if res.code == 0 or (res.stdout or '') ~= '' then
      return vim.split(vim.trim(res.stdout or ''), '\n', { trimempty = true })
    end
  end
  local files = {}
  for name, kind in vim.fs.dir(root, {
    depth = 20,
    skip = function(dir) return not dir:match('^%.') and not dir:match('/%.') end,
  }) do
    if kind == 'file' and not name:match('^%.') then table.insert(files, name) end
  end
  return files
end

--- The index of the vault's files now; nil without a vault.
function M.index(force)
  local root = vault()
  if not root then return nil end
  if force or cache.root ~= root or vim.uv.now() - cache.time > 5000 then
    cache = { root = root, time = vim.uv.now(), idx = indexOf(listFiles(root)) }
  end
  return cache.idx, root
end

local function invalidate() cache.time = 0 end

-- -----------------------------------------------------------------------------
--  Links
-- -----------------------------------------------------------------------------

--- Undo the %20 and friends of a markdown link's destination.
local function urldecode(s)
  return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

--- Split the inside of a link into its parts: "Note#Head|Alias" ->
--- target "Note", sub "Head" (or "^block"), alias "Alias".
local function splitInner(inner)
  local target, alias = inner:match('^(.-)|(.*)$')
  target = target or inner
  local path, sub = target:match('^(.-)#(.*)$')
  return { target = vim.trim(path or target), sub = sub, alias = alias }
end

--- Every link on `line`: { kind = 'wiki' | 'md' | 'url', s, e (1-based,
--- inclusive), inner (wiki: inside the brackets; md: the destination) }.
local function linksIn(line)
  local out = {}
  for s, bang, inner, e in line:gmatch('()(!?)%[%[([^%[%]]-)%]%]()') do
    table.insert(out, { kind = 'wiki', s = s, e = e - 1, inner = inner, embed = bang == '!' })
  end
  for s, dest, e in line:gmatch('()%[[^%]]*%]%(([^%)]*)%)()') do
    local inside = false
    for _, w in ipairs(out) do
      if s >= w.s and s <= w.e then inside = true end
    end
    if not inside then
      dest = vim.trim(dest)
      local angle = dest:match('^<(.*)>$')
      dest = angle or dest
      local kind = dest:match('^%a[%w+.-]*:') and 'url' or 'md'
      table.insert(out, { kind = kind, s = s, e = e - 1, inner = dest, angle = angle ~= nil })
    end
  end
  for s, url, e in line:gmatch('()(https?://[^%s%)%]>]+)()') do
    local inside = false
    for _, l in ipairs(out) do
      if s >= l.s and s <= l.e then inside = true end
    end
    if not inside then table.insert(out, { kind = 'url', s = s, e = e - 1, inner = url }) end
  end
  table.sort(out, function(a, b) return a.s < b.s end)
  return out
end
M._linksIn = linksIn

--- The link under the cursor, or nil.
local function linkAtCursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  for _, l in ipairs(linksIn(line)) do
    if col >= l.s and col <= l.e then return l end
  end
end

--- Resolve a link target (as written, decoded) found in the note `from`
--- (relative path, or nil outside the vault) to a relative path of `idx`.
local function resolve(idx, target, from)
  if not idx or target == '' then return nil end
  target = target:gsub('\\', '/'):gsub('^/+', '')
  local t = lower(target)
  local function exists(p)
    p = p and lower(p)
    return p and (idx.by_path[p] or idx.by_path[p .. '.md'])
  end
  -- A path from the vault's root, then from the note's own folder.
  local hit = exists(t)
  if hit then return hit end
  if from then
    local rel = collapse(dirOf(from) .. '/' .. target)
    hit = rel and exists(rel)
    if hit then return hit end
  end
  -- Any file with that name ([[Note]]), or ending in that path
  -- ([[folder/Note]]).
  local name = t:match('[^/]*$')
  local found = {}
  for _, f in ipairs(idx.by_name[name] or idx.by_name[name:gsub('%.md$', '')] or {}) do
    local lf = lower(f)
    if not t:find('/', 1, true) or lf:sub(-#t - 1) == '/' .. t or lf:sub(-#t - 4) == '/' .. t .. '.md' then
      table.insert(found, f)
    end
  end
  if #found <= 1 then return found[1] end
  local here = from and lower(dirOf(from))
  table.sort(found, function(a, b)
    local ah, bh = lower(dirOf(a)) == here, lower(dirOf(b)) == here
    if ah ~= bh then return ah end
    if #a ~= #b then return #a < #b end
    return a < b
  end)
  return found[1]
end
M._resolve = function(files, target, from) return resolve(indexOf(files), target, from) end

--- The note name a link should use for `rel`: the bare name when no other
--- file has it, else the path; without ".md".
local function linkName(idx, rel)
  local stem = stemOf(rel)
  local key = rel:match('%.md$') and lower(stem) or lower(rel:match('[^/]*$'))
  local same = idx.by_name[key] or {}
  local name = rel:match('%.md$') and stem or rel:match('[^/]*$')
  if #same <= 1 then return name end
  return (rel:gsub('%.md$', ''))
end

--- The link text for `rel` seen from the note `from`: the bare name when
--- that already leads to it (Obsidian's rules above), else the path.
local function shortest(idx, rel, from)
  local name = rel:match('%.md$') and stemOf(rel) or rel:match('[^/]*$')
  if resolve(idx, name, from) == rel then return name end
  return (rel:gsub('%.md$', ''))
end

-- -----------------------------------------------------------------------------
--  Following links
-- -----------------------------------------------------------------------------

--- Heading text as a link names it: case, spaces and punctuation aside.
local function slug(s)
  return lower(s):gsub('[%p%s]+', ' '):gsub('^ ', ''):gsub(' $', '')
end

--- Put the cursor on `sub` (a heading, or ^block) of the current buffer.
local function jumpTo(sub)
  if not sub or sub == '' then return end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local block = sub:match('^%^(.+)$')
  -- [[Note#A#B]]: the last heading is the one to go to.
  local want = not block and slug(sub:match('([^#]*)$'))
  for i, l in ipairs(lines) do
    local hit
    if block then
      hit = l:match('%^' .. vim.pesc(block) .. '%s*$')
    else
      local text = l:match('^#+%s+(.-)%s*#*%s*$')
      hit = text and slug(text) == want
    end
    if hit then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd('normal! zvzz')
      return
    end
  end
  vim.notify('No ' .. (block and ('block ^' .. block) or ('heading "' .. sub .. '"')) .. ' in this note',
    vim.log.levels.WARN)
end

--- Obsidian's setting for where new notes go: the folder, relative to the
--- vault ('' is the root). `from` is the note the link is in.
local function newNoteFolder(root, from)
  local ok, conf = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(root .. '/.obsidian/app.json'), '\n'))
  end)
  conf = ok and type(conf) == 'table' and conf or {}
  if conf.newFileLocation == 'current' and from then return dirOf(from) end
  if conf.newFileLocation == 'folder' and type(conf.newFileFolderPath) == 'string' then
    return (conf.newFileFolderPath:gsub('^/+', ''):gsub('/+$', ''))
  end
  return ''
end

local function openFile(path)
  if path:match('%.md$') or not path:match('[^/]%.%w+$') then
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  else
    -- Pictures, PDFs, canvases...: the system's own program.
    vim.ui.open(path)
  end
end

--- Folders of the vault under `arglead`, for the "In another folder" prompt.
--- Hidden ones (.obsidian, .trash, .git) are left out.
function M._folders(arglead)
  local root = vault()
  if not root then return {} end
  arglead = (arglead or ''):gsub('\\', '/'):lower()
  local out = {}
  for name, kind in vim.fs.dir(root, {
    depth = 8,
    skip = function(dir) return not vim.fs.basename(dir):match('^%.') end,
  }) do
    if kind == 'directory' and not vim.fs.basename(name):match('^%.')
        and name:lower():sub(1, #arglead) == arglead then
      table.insert(out, name .. '/')
    end
  end
  table.sort(out)
  return out
end

--- Ask for a folder of the vault, starting from the current note's own.
--- nil when cancelled, empty, or pointing outside the vault.
local function askFolder(from)
  local here = from and dirOf(from) or ''
  local ok, input = pcall(vim.fn.input, {
    prompt = 'Folder: ',
    default = here ~= '' and (here .. '/') or '',
    completion = "customlist,v:lua.require'pure.notes'._folders",
  })
  input = ok and vim.trim((input or ''):gsub('\\', '/')) or ''
  input = input:gsub('^/+', ''):gsub('/+$', '')
  if input == '' then return nil end
  for step in input:gmatch('[^/]+') do
    if step == '.' or step == '..' then
      vim.notify('Not a folder inside the vault: ' .. input, vim.log.levels.WARN)
      return nil
    end
  end
  return input
end

--- Create the note a link names, after asking; then open it.
---
---   Yes                in the folder for new notes (Obsidian's setting), or
---                      the one the link names ([[Projects/New]])
---   With a template    the same, then the template is applied as <leader>nt
---                      applies it, moves included: the Project template
---                      sends the note to 1-Projects/<title>/
---   In another folder  asks which (made if missing)
---   Cancel             nothing
---
--- With a template the note is made only once one is picked, so cancelling
--- the pick leaves no empty note behind.
local function create(root, link, from)
  local target = link.target
  local folder, title = target:match('^(.*)/([^/]*)$')
  if not folder then folder, title = newNoteFolder(root, from), target end
  title = title:gsub('%.md$', '')
  local choice = vim.fn.confirm(('Create the note "%s"?'):format(title),
    '&Yes\nWith a &template\nIn another &folder\n&Cancel', 1)

  local function make(rel)
    local dir = root .. (rel ~= '' and ('/' .. rel) or '')
    vim.fn.mkdir(dir, 'p')
    local path = dir .. '/' .. zet().noteId(title, dir) .. '.md'
    vim.fn.writefile({}, path)
    invalidate()
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  end

  if choice == 1 then
    make(folder)
  elseif choice == 2 then
    zet().pickTemplate(function(selected)
      if not selected then return end
      make(folder)
      zet().applyTemplate(selected)
      invalidate() -- the template may have moved it
    end)
  elseif choice == 3 then
    local chosen = askFolder(from)
    if chosen then make(chosen) end
  end
end

--- Follow the link under the cursor. False when there is none.
--- `urls_only`: only web links (for code, where [[x]] is not a note).
function M.follow(urls_only)
  local link = linkAtCursor()
  if not link or (urls_only and link.kind ~= 'url') then return false end
  if link.kind == 'url' then
    vim.ui.open(link.inner)
    return true
  end

  local parts = link.kind == 'wiki' and splitInner(link.inner) or splitInner(urldecode(link.inner))
  local idx, root = M.index()
  local here = vim.api.nvim_buf_get_name(0)
  local from = root and here ~= '' and relTo(root, here) or nil

  -- [[#Heading]]: in this same note.
  if parts.target == '' then
    jumpTo(parts.sub)
    return true
  end

  -- A markdown link relative to a file outside the vault.
  if link.kind == 'md' and not from and here ~= '' then
    local p = vim.fs.normalize(vim.fs.dirname(here) .. '/' .. parts.target)
    for _, c in ipairs({ p, p .. '.md' }) do
      if vim.uv.fs_stat(c) then
        openFile(c)
        jumpTo(parts.sub)
        return true
      end
    end
  end

  if not root then
    vim.notify('No vault set: run :ZettelVault', vim.log.levels.WARN)
    return true
  end
  local rel = resolve(idx, parts.target, from) or resolve(M.index(true), parts.target, from)
  if not rel then
    create(root, parts, from)
    return true
  end
  vim.cmd("normal! m'")
  openFile(root .. '/' .. rel)
  if rel:match('%.md$') then jumpTo(parts.sub) end
  return true
end

--- <CR> in markdown: follow a link, open a ```todoist block, toggle a
--- checkbox, fold a heading; else a plain <CR>.
function M.enter()
  local ok, todoist = pcall(require, 'pure.todoist')
  if ok and todoist.openBlock and todoist.openBlock() then return end
  if M.follow() then return end
  local line = vim.api.nvim_get_current_line()
  if line:match('^%s*[-*+]%s+%[.%]') then
    return require('configs.functions').toggleCheckbox()
  end
  if line:match('^#+%s') and vim.fn.foldlevel('.') > 0 then
    return vim.cmd('normal! za')
  end
  vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'n', false)
end

-- -----------------------------------------------------------------------------
--  Completion after [[
-- -----------------------------------------------------------------------------
--  An 'omnifunc', which the 'autocomplete' of this configuration already
--  asks as you type (the 'o' in 'complete'). Outside a [[link it hands the
--  question to the buffer's language server, when there is one.

local pending -- what findstart saw, for the second call

function M.omnifunc(findstart, base)
  if findstart == 1 then
    pending = nil
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local before, after = line:sub(1, col), line:sub(col + 1)
    local start, typed = before:match('.*()%[%[([^%[%]]*)$')
    if start and not typed:find('|', 1, true) then
      local closes = after:match('^%]%]') ~= nil
      local note, head = typed:match('^(.-)#([^#]*)$')
      if note then
        pending = { kind = 'heading', note = note, closes = closes }
        return col - #head
      end
      pending = { kind = 'note', closes = closes }
      return start + 1 -- 0-based column right after [[
    end
    if #vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/completion' }) > 0 then
      pending = { kind = 'lsp' }
      return vim.lsp.omnifunc(findstart, base)
    end
    return -3
  end

  local p = pending or {}
  if p.kind == 'lsp' then return vim.lsp.omnifunc(findstart, base) end
  local idx, root = M.index()
  if not idx then return {} end
  local close = p.closes and '' or ']]'
  local items = {}

  if p.kind == 'heading' then
    local here = vim.api.nvim_buf_get_name(0)
    local from = here ~= '' and relTo(root, here) or nil
    local rel = p.note == '' and from or resolve(idx, p.note, from)
    if not rel then return {} end
    local path = root .. '/' .. rel
    local bufnr = vim.fn.bufnr(path)
    local lines = bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
      and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or vim.fn.readfile(path)
    local heads = {}
    for _, l in ipairs(lines) do
      local text = l:match('^#+%s+(.-)%s*#*%s*$')
      if text and text ~= '' then table.insert(heads, text) end
    end
    if base ~= '' then heads = vim.fn.matchfuzzy(heads, base) end
    for _, h in ipairs(heads) do
      table.insert(items, { word = h .. close, abbr = h, menu = '#', equal = 1 })
    end
    return items
  end

  -- Improved for Improvment.md in the vault ("the [[links]] and folders
  -- completion"). It only offered notes by name, so:
  --   [[3-Zett/         a path: the folders and files inside that folder,
  --                     matched by what follows the last '/'
  --   [[zett            folders match too ("3-Zettelkasten/", no ]]: you
  --                     keep typing into it)
  --   ![[photo  [[doc   attachments (images, PDFs...) as well, after the
  --                     notes, with their extension, as Obsidian links them
  -- Each item says what it is in the menu's kind column: note, folder, file.
  local function isNote(f) return f:match('%.md$') or f:match('%.canvas$') end

  local folders, seen_dir = {}, {}
  for _, f in ipairs(idx.files) do
    local d = dirOf(f)
    while d ~= '' and not seen_dir[d] do
      seen_dir[d] = true
      table.insert(folders, d)
      d = dirOf(d)
    end
  end

  local dir_typed, rest = base:match('^(.*)/([^/]*)$')
  if dir_typed then
    -- By path: what sits directly in the typed folder (case-blind, as
    -- Obsidian resolves links).
    local want = lower(dir_typed)
    local cands, info = {}, {}
    for _, d in ipairs(folders) do
      if lower(dirOf(d)) == want then
        local label = d:match('[^/]*$') .. '/'
        table.insert(cands, label)
        info[label] = { word = d .. '/', kind = 'folder' }
      end
    end
    for _, f in ipairs(idx.files) do
      if lower(dirOf(f)) == want then
        local label = f:match('[^/]*$')
        local link = isNote(f) and f:match('%.md$') and (f:gsub('%.md$', '')) or f
        if isNote(f) then label = label:gsub('%.md$', '') end
        table.insert(cands, label)
        info[label] = { word = link .. close, kind = isNote(f) and 'note' or 'file' }
      end
    end
    cands = rest ~= '' and vim.fn.matchfuzzy(cands, rest) or cands
    if rest == '' then table.sort(cands) end
    for i, label in ipairs(cands) do
      if i > 200 then break end
      local it = info[label]
      table.insert(items, { word = it.word, abbr = label, kind = it.kind, menu = dir_typed, equal = 1 })
    end
    return items
  end

  -- By name: notes first, then folders, then other files.
  local groups = { note = {}, folder = {}, file = {} }
  local by = {}
  for _, f in ipairs(idx.files) do
    local kind = isNote(f) and 'note' or 'file'
    local name = linkName(idx, f)
    if not by[name] then
      by[name] = { word = name .. close, kind = kind, dir = dirOf(f) }
      table.insert(groups[kind], name)
    end
  end
  for _, d in ipairs(folders) do
    local name = d .. '/'
    if not by[name] then
      by[name] = { word = name, kind = 'folder', dir = dirOf(d) }
      table.insert(groups.folder, name)
    end
  end
  for _, kind in ipairs({ 'note', 'folder', 'file' }) do
    local names = groups[kind]
    if base ~= '' then
      names = vim.fn.matchfuzzy(names, base)
    else
      table.sort(names)
    end
    for _, name in ipairs(names) do
      if #items >= 200 then break end
      local it = by[name]
      table.insert(items, { word = it.word, abbr = name, kind = it.kind,
        menu = it.dir ~= '' and it.dir or '/', equal = 1 })
    end
  end
  return items
end

-- -----------------------------------------------------------------------------
--  Fixing links after notes move
-- -----------------------------------------------------------------------------
--  `moves`: { { old = rel, new = rel } }, files already moved. Every link
--  that pointed to an old path is rewritten to the new one, in the style it
--  was written in:
--    [[Note]]           the new name ([[folder/New]] if another file has it)
--    [[folder/Note]]    the new path
--    [x](folder/Note.md), [x](../Note.md)   the new path, from the vault's
--                       root or relative, as it was; spaces as %20 if so
--  plus the relative markdown links inside the moved notes themselves, and
--  the file cards of canvases ("file": "folder/Note.md").

local function urlencodeSpaces(s) return (s:gsub(' ', '%%20')) end

--- A relative path from folder `from_dir` to `to` (both vault-relative).
local function relative(from_dir, to)
  local a = from_dir == '' and {} or vim.split(from_dir, '/', { plain = true })
  local b = vim.split(to, '/', { plain = true })
  local i = 1
  while i <= #a and i < #b and lower(a[i]) == lower(b[i]) do i = i + 1 end
  local parts = {}
  for _ = i, #a do table.insert(parts, '..') end
  for k = i, #b do table.insert(parts, b[k]) end
  return table.concat(parts, '/')
end

--- The new text of one link, or nil to leave it.
--- `before`/`after`: indexes of the vault before and after the moves;
--- `src_old`/`src_new`: where the note holding the link was and is.
local function rewrite(link, before, after, moved, src_old, src_new)
  if link.kind == 'url' then return nil end
  local raw = link.kind == 'wiki' and link.inner or urldecode(link.inner)
  local parts = splitInner(raw)
  if parts.target == '' then return nil end
  local old_target = resolve(before, parts.target, src_old)
  if not old_target then return nil end
  local new_target = moved[old_target] or old_target
  local src_moved = src_old ~= src_new
  if new_target == old_target and not (src_moved and link.kind == 'md') then return nil end

  local tail = (parts.sub and ('#' .. parts.sub) or '')
  if link.kind == 'wiki' then
    if new_target == old_target then return nil end
    local keep_ext = parts.target:lower():match('%.md$')
    local text
    if parts.target:find('/', 1, true) then
      text = keep_ext and new_target or (new_target:gsub('%.md$', ''))
    else
      text = shortest(after, new_target, src_new)
      if keep_ext and not text:match('%.md$') then text = text .. '.md' end
    end
    return (link.embed and '!' or '') .. '[[' .. text .. tail .. (parts.alias and ('|' .. parts.alias) or '') .. ']]'
  end

  -- A markdown link: keep its form (from the root, relative, bare name).
  local dest = parts.target
  local had_ext = dest:lower():match('%.md$') or not new_target:match('%.md$')
  local target_text = had_ext and new_target or (new_target:gsub('%.md$', ''))
  local function known(p)
    p = p and lower(p)
    return p and (before.by_path[p] or before.by_path[p .. '.md'])
  end
  local new_dest
  if not dest:match('^%.') and known(dest) then
    new_dest = target_text                                  -- from the root
  elseif known(collapse(dirOf(src_old or '') .. '/' .. dest)) then
    new_dest = relative(dirOf(src_new or ''), target_text)  -- relative
    if dest:match('^%./') and not new_dest:match('^%.') then new_dest = './' .. new_dest end
  else
    new_dest = shortest(after, new_target, src_new)         -- a bare name
    if had_ext and new_target:match('%.md$') and not new_dest:match('%.md$') then new_dest = new_dest .. '.md' end
  end
  if new_dest == dest then return nil end
  if link.angle then
    new_dest = '<' .. new_dest .. '>'
  else
    -- Spaces break a markdown link unless written as %20.
    new_dest = urlencodeSpaces(new_dest)
  end
  -- Only the destination changes: [label](new).
  local line_link = link.text
  return (line_link:gsub('%((.*)%)$', function() return '(' .. new_dest .. ')' end))
end

--- The changed lines of `lines` (a note or a canvas) for these moves:
--- { [lnum] = new line }, count.
local function fixLines(lines, is_canvas, before, after, moved, src_old, src_new)
  local out, count = {}, 0
  local fence = false
  for i, line in ipairs(lines) do
    local new = line
    if is_canvas then
      new = line:gsub('("file"%s*:%s*")(.-)(")', function(a, path, c)
        local p = path:gsub('\\/', '/')
        if moved[p] then
          count = count + 1
          return a .. moved[p] .. c
        end
      end)
    else
      if line:match('^%s*```') or line:match('^%s*~~~') then fence = not fence end
      if not fence then
        local links = linksIn(line)
        -- Right to left, so the columns of the ones before stay valid.
        for k = #links, 1, -1 do
          local l = links[k]
          l.text = new:sub(l.s, l.e)
          local r = rewrite(l, before, after, moved, src_old, src_new)
          if r then
            new = new:sub(1, l.s - 1) .. r .. new:sub(l.e + 1)
            count = count + 1
          end
        end
      end
    end
    if new ~= line then out[i] = new end
  end
  return out, count
end

--- Read a file as lines, and whether it uses CRLF.
local function readLines(path)
  local ok, lines = pcall(vim.fn.readfile, path, 'b')
  if not ok then return nil end
  local crlf = lines[1] and lines[1]:sub(-1) == '\r'
  if crlf then
    for i, l in ipairs(lines) do lines[i] = l:gsub('\r$', '') end
  end
  return lines, crlf
end

--- Fix the links to `moves`. Asks first unless `quiet`.
function M.fixLinks(moves, quiet)
  local after, root = M.index(true)
  if not after or #moves == 0 then return end
  local moved, back = {}, {}
  for _, m in ipairs(moves) do
    moved[m.old] = m.new
    back[m.new] = m.old
  end
  -- The vault as it was: the moved files at their old paths.
  local old_files = {}
  for _, f in ipairs(after.files) do table.insert(old_files, back[f] or f) end
  local before = indexOf(old_files)

  -- The notes that may hold such a link: those that name one of the moved
  -- files (ripgrep), and the moved notes themselves.
  local args = { 'rg', '--files-with-matches', '--ignore-case', '--fixed-strings', '--path-separator', '/',
    '-g', '*.md', '-g', '*.canvas' }
  for _, m in ipairs(moves) do
    local stem = stemOf(m.old)
    vim.list_extend(args, { '-e', stem, '-e', urlencodeSpaces(stem) })
  end
  local candidates = {}
  local res = vim.fn.executable('rg') == 1 and vim.system(args, { cwd = root, text = true }):wait() or nil
  if res then
    for _, f in ipairs(vim.split(res.stdout or '', '\n', { trimempty = true })) do candidates[f] = true end
  else
    for _, f in ipairs(after.files) do
      if f:match('%.md$') or f:match('%.canvas$') then candidates[f] = true end
    end
  end
  for _, m in ipairs(moves) do
    if m.new:match('%.md$') then candidates[m.new] = true end
  end

  local edits, total = {}, 0
  for f in pairs(candidates) do
    local path = root .. '/' .. f
    local buf = vim.fn.bufnr(path)
    local loaded = buf > 0 and vim.api.nvim_buf_is_loaded(buf)
    local lines, crlf
    if loaded then
      lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    else
      lines, crlf = readLines(path)
    end
    if lines then
      local changed, count = fixLines(lines, f:match('%.canvas$') ~= nil, before, after, moved, back[f] or f, f)
      if count > 0 then
        table.insert(edits, { file = f, path = path, buf = loaded and buf or nil, lines = lines,
          changed = changed, count = count, crlf = crlf })
        total = total + count
      end
    end
  end
  if total == 0 then return 0 end

  if not quiet then
    local names = {}
    for i, e in ipairs(edits) do
      if i > 8 then
        table.insert(names, ('… and %d more'):format(#edits - 8))
        break
      end
      table.insert(names, '  ' .. e.file .. ' (' .. e.count .. ')')
    end
    local choice = vim.fn.confirm(('Fix %d link%s in %d file%s?\n%s'):format(total, total == 1 and '' or 's',
      #edits, #edits == 1 and '' or 's', table.concat(names, '\n')), '&Yes\n&No', 1)
    if choice ~= 1 then return 0 end
  end

  local unsaved = {}
  for _, e in ipairs(edits) do
    if e.buf then
      local was_modified = vim.bo[e.buf].modified
      for lnum, text in pairs(e.changed) do
        vim.api.nvim_buf_set_lines(e.buf, lnum - 1, lnum, false, { text })
      end
      if was_modified then
        table.insert(unsaved, e.file)
      else
        vim.api.nvim_buf_call(e.buf, function() vim.cmd('silent noautocmd write') end)
      end
    else
      for lnum, text in pairs(e.changed) do e.lines[lnum] = text end
      if e.crlf then
        for i, l in ipairs(e.lines) do e.lines[i] = l .. '\r' end
      end
      vim.fn.writefile(e.lines, e.path, 'b')
    end
  end
  local msg = ('Fixed %d link%s in %d file%s'):format(total, total == 1 and '' or 's', #edits, #edits == 1 and '' or 's')
  if #unsaved > 0 then msg = msg .. '\nNot saved (they had unsaved changes): ' .. table.concat(unsaved, ', ') end
  vim.notify(msg)
  return total
end

-- -----------------------------------------------------------------------------
--  Renaming
-- -----------------------------------------------------------------------------

--- Rename (or move, with a '/') the current note and fix the links to it.
function M.rename(new_name)
  local _, root = M.index()
  local here = vim.api.nvim_buf_get_name(0)
  local rel = root and here ~= '' and relTo(root, here)
  if not rel then return vim.notify('Not a note of the vault', vim.log.levels.WARN) end
  local ext = rel:match('%.[^./]+$') or ''

  local function go(input)
    input = input and vim.trim(input) or ''
    if input == '' then return end
    input = input:gsub('\\', '/'):gsub('^/+', '')
    if ext ~= '' and input:sub(-#ext):lower() ~= ext:lower() then input = input .. ext end
    -- A bare name stays in the same folder; a path is from the vault's root.
    local new = input:find('/', 1, true) and input or ((dirOf(rel) ~= '' and (dirOf(rel) .. '/') or '') .. input)
    new = collapse(new)
    if not new or new == rel then return end
    local new_path = root .. '/' .. new
    -- A different case only is the same file on Windows and macOS: allowed.
    if vim.uv.fs_stat(new_path) and lower(new) ~= lower(rel) then
      return vim.notify(new .. ' already exists', vim.log.levels.ERROR)
    end
    vim.fn.mkdir(vim.fs.dirname(new_path), 'p')
    if vim.bo.modified then vim.cmd('silent write') end
    local ok, err = vim.uv.fs_rename(here, new_path)
    if not ok then return vim.notify('Could not rename: ' .. tostring(err), vim.log.levels.ERROR) end
    -- The buffer follows the file; the old name is not left behind as a buffer.
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(buf, new_path)
    vim.cmd('silent! noautocmd write!')
    pcall(vim.cmd, 'bwipeout ' .. vim.fn.bufnr(here))
    invalidate()
    vim.notify(rel .. ' → ' .. new)
    M.fixLinks({ { old = rel, new = new } })
  end
  if new_name then return go(new_name) end
  vim.ui.input({ prompt = ' Rename note: ', default = rel:match('[^/]*$'):gsub('%.md$', '') }, go)
end

-- In oil, moving or renaming a note (or a folder of them) inside the vault
-- fixes the links to it, as Obsidian does.
local function oilPath(url)
  local path = url:match('^oil://(.*)$')
  if not path then return nil end
  local ok, fs = pcall(require, 'oil.fs')
  if ok and fs.posix_to_os_path then path = fs.posix_to_os_path(path) end
  return vim.fs.normalize(path)
end

vim.api.nvim_create_autocmd('User', {
  group = vim.api.nvim_create_augroup('PureNotesOil', { clear = true }),
  pattern = 'OilActionsPost',
  callback = function(args)
    local data = args.data or {}
    if data.err then return end
    local root = vault()
    if not root then return end
    invalidate()
    local idx = M.index(true)
    local moves = {}
    for _, a in ipairs(data.actions or {}) do
      if a.type == 'move' and a.src_url and a.dest_url then
        local src, dest = oilPath(a.src_url), oilPath(a.dest_url)
        local old, new = src and relTo(root, src), dest and relTo(root, dest)
        if old and new then
          if a.entry_type == 'directory' then
            for _, f in ipairs(idx.files) do
              if lower(f):sub(1, #new + 1) == lower(new) .. '/' then
                table.insert(moves, { old = old .. f:sub(#new + 1), new = f })
              end
            end
          else
            table.insert(moves, { old = old, new = new })
          end
        end
      end
    end
    if #moves > 0 then vim.schedule(function() M.fixLinks(moves) end) end
  end,
})

-- -----------------------------------------------------------------------------
--  Backlinks
-- -----------------------------------------------------------------------------

--- The lines of the vault that link to the current note, in a picker.
function M.backlinks()
  local idx, root = M.index()
  local here = vim.api.nvim_buf_get_name(0)
  local rel = root and here ~= '' and relTo(root, here)
  if not rel then return vim.notify('Not a note of the vault', vim.log.levels.WARN) end
  local stem = stemOf(rel)
  if vim.fn.executable('rg') == 0 then return vim.notify('Backlinks need ripgrep (rg)', vim.log.levels.WARN) end
  local res = vim.system({ 'rg', '--line-number', '--no-heading', '--ignore-case', '--fixed-strings',
    '--path-separator', '/', '-g', '*.md', '-e', stem, '-e', urlencodeSpaces(stem) }, { cwd = root, text = true }):wait()
  local hits = {}
  for _, l in ipairs(vim.split(res.stdout or '', '\n', { trimempty = true })) do
    local file, lnum, text = l:match('^(.-):(%d+):(.*)$')
    if file and file ~= rel then
      for _, link in ipairs(linksIn(text)) do
        if link.kind ~= 'url' then
          local parts = splitInner(link.kind == 'wiki' and link.inner or urldecode(link.inner))
          if parts.target ~= '' and resolve(idx, parts.target, file) == rel then
            table.insert(hits, ('%s:%s: %s'):format(file, lnum, vim.trim(text)))
            break
          end
        end
      end
    end
  end
  if #hits == 0 then return vim.notify('No note links to ' .. stem) end
  -- preview + cwd: the linking note is shown as you move, with the line of
  -- the link highlighted (asked for in Improvment.md, "like the grep").
  require('pure.fuzzyUtils').pickList(hits, { title = ' Links to ' .. stem .. ' ', fzf = "--nth=1,3..",
    preview = true, cwd = root },
    function(selection)
      local file, lnum = (selection or ''):match('^(.-):(%d+):')
      if not file then return end
      vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/' .. file))
      pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(lnum), 0 })
    end)
end

-- -----------------------------------------------------------------------------
--  Setup
-- -----------------------------------------------------------------------------

local group = vim.api.nvim_create_augroup('PureNotes', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'markdown',
  callback = function(args)
    local buf = args.buf
    vim.bo[buf].omnifunc = "v:lua.require'pure.notes'.omnifunc"
    -- The Todoist list maps <CR> to toggle a task; it asks M.follow first.
    if vim.bo[buf].buftype ~= '' then return end
    vim.keymap.set('n', '<CR>', M.enter, { buffer = buf, desc = 'Follow link / open block / toggle checkbox' })
  end,
})

-- A language server attaching later sets its own omnifunc: keep this one,
-- which hands it everything outside [[links.
vim.api.nvim_create_autocmd('LspAttach', {
  group = group,
  callback = function(args)
    if vim.bo[args.buf].filetype == 'markdown' then
      vim.bo[args.buf].omnifunc = "v:lua.require'pure.notes'.omnifunc"
    end
  end,
})

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufNewFile' }, {
  group = group,
  pattern = { '*.md', '*.canvas' },
  callback = invalidate,
})

vim.api.nvim_create_user_command('NoteRename', function(o) M.rename(o.args ~= '' and o.args or nil) end,
  { nargs = '?', desc = 'Rename the note and fix the links to it' })
vim.api.nvim_create_user_command('NoteBacklinks', M.backlinks, { desc = 'The notes that link to this one' })

return M
