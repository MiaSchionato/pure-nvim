-- =============================================================================
--  The vault, Markdown side: what <leader>v does in a vault of Markdown notes
-- =============================================================================
--  The same garden as the org vault (pure/vault/org.lua), in the Markdown the
--  vault's Obsidian reads (files/config/scripts/garden.js and capture.js there
--  are the same commands):
--
--    # The idea                  the atom is a heading
--    #seed #Devaneios            its state: a tag on the line right under it
--    created:: 2026-11-18 14:05  its properties: key:: value lines
--    id:: 3f9a2c                 the id a linked heading carries (never changed,
--                                never copied: it moves with its heading)
--    The body.
--
--  Garden states: #seed > #sprout > #plant > #tree, #fruit; #compost (let go).
--  Tasks are checkboxes of the Tasks plugin: [ ] [~] [!] [>] [-] [x], with its
--  dates (⏳ scheduled, 📅 due, ✅ done, ❌ cancelled, ➕ created).
--  Links are by name, [[note#Heading|text]]; a heading moved by grow, compost or
--  move takes its links along (every [[from#Heading]] of the vault is rewritten),
--  as garden.js does. A heading renamed by hand is Obsidian's headlinks.js's.
--
--  The notes and folders come from the vault's `notes` (pure/vault.lua).
-- =============================================================================

local B = {}

local function V() return require('pure.vault') end
local function notes() return require('pure.notes') end

local function warn(msg) vim.notify('Vault: ' .. msg, vim.log.levels.WARN) end

local LADDER = { 'seed', 'sprout', 'plant', 'tree' }
local GARDEN_STATES = { 'seed', 'sprout', 'plant', 'tree', 'fruit', 'compost' }
local OWN_NOTE_STATES = { plant = true, tree = true, fruit = true }
-- The checkbox states, in the order of <leader>x: { symbol, label }.
local TASK_STATES = { { ' ', 'TODO' }, { '~', 'IN PROGRESS' }, { '!', 'IMPORTANT' }, { '>', 'DEFERRED' },
  { '-', 'CANCELLED' }, { 'x', 'DONE' } }
B.GARDEN_STATES, B.TASK_STATES = GARDEN_STATES, TASK_STATES

local function isGardenState(s) return vim.tbl_contains(GARDEN_STATES, (s or ''):lower()) end

local function stamp() return os.date('%Y-%m-%d %H:%M') end

local function slug(title)
  return (title:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''))
end

-- -----------------------------------------------------------------------------
--  Reading a note: headings, the section at a row, its tag line and state
-- -----------------------------------------------------------------------------
local FENCE = '^%s*[`~][`~][`~]'

--- The headings of `lines` (not inside the front matter or a code fence): { line, level, title }, 1-based.
function B.headings(lines)
  local out, fence, i = {}, false, 1
  if lines[1] == '---' then
    i = 2
    while i <= #lines and lines[i] ~= '---' do i = i + 1 end
    i = i + 1
  end
  for n = i, #lines do
    local l = lines[n]
    if l:match(FENCE) then fence = not fence
    elseif not fence then
      local hashes, title = l:match('^(#+)%s+(.-)%s*$')
      if hashes and #hashes <= 6 then out[#out + 1] = { line = n, level = #hashes, title = title } end
    end
  end
  return out
end

--- The section of the heading at or above `row`: { line, level, title, last } (last: its last line), or nil.
function B.section(lines, row)
  local hs = B.headings(lines)
  local k
  for j, h in ipairs(hs) do if h.line <= row then k = j end end
  if not k then return nil end
  local h = vim.deepcopy(hs[k])
  h.last = #lines
  for j = k + 1, #hs do
    if hs[j].level <= h.level then h.last = hs[j].line - 1 break end
  end
  return h
end

local function isTagLine(l)
  if not l or not l:match('^#[^%s#]') then return false end
  for t in l:gmatch('%S+') do if not t:match('^#[^%s#]') then return false end end
  return true
end

--- The row of the tag line right under the section's heading, or nil.
local function tagRow(lines, sec)
  local n = sec.line + 1
  if n <= sec.last and isTagLine(lines[n]) then return n end
end

--- The garden state of the section (seed, sprout...), or nil.
function B.stateOf(lines, sec)
  local n = tagRow(lines, sec)
  if not n then return nil end
  for t in lines[n]:gmatch('%S+') do
    if isGardenState(t:sub(2)) then return t:sub(2):lower() end
  end
end

--- The lines of the section with its state set to `state` (nil: no state): the old state tag replaced, the
--- other tags kept, a tag line made when there was none (and dropped when it is left empty). Only the heading's
--- tag line changes: the properties (id:: among them) and the body stay as they are.
function B.withState(lines, sec, state)
  local out = vim.list_slice(lines, sec.line, sec.last)
  local n = tagRow(lines, sec)
  local others = {}
  if n then
    for t in lines[n]:gmatch('%S+') do
      if not isGardenState(t:sub(2)) then others[#others + 1] = t end
    end
  end
  local tags = state and vim.list_extend({ '#' .. state }, others) or others
  local at = n and (n - sec.line + 1) or nil
  if at then
    if #tags > 0 then out[at] = table.concat(tags, ' ') else table.remove(out, at) end
  elseif state then
    table.insert(out, 2, '#' .. state)
  end
  return out
end

--- The section's lines with its headings shifted so that the first one is level 1 (it lands at the top level).
local function toTopLevel(block, level)
  local shift = level - 1
  if shift == 0 then return block end
  local out, fence = {}, false
  for _, l in ipairs(block) do
    if l:match(FENCE) then fence = not fence end
    local hashes = not fence and l:match('^(#+)%s')
    out[#out + 1] = hashes and (string.rep('#', math.max(1, #hashes - shift)) .. l:sub(#hashes + 1)) or l
  end
  return out
end

-- -----------------------------------------------------------------------------
--  Notes as files or buffers
-- -----------------------------------------------------------------------------
local function root() return V().dir('md') end

local function relOf(path)
  local r = root()
  local p = vim.fs.normalize(path)
  if r and p:sub(1, #r + 1) == r .. '/' then return p:sub(#r + 2) end
end

local function loadedBuf(path)
  local nr = vim.fn.bufnr(vim.fs.normalize(path))
  if nr ~= -1 and vim.api.nvim_buf_is_loaded(nr) then return nr end
end

--- The lines of the note at `path` (its buffer when it is open).
local function readNote(path)
  local buf = loadedBuf(path)
  if buf then return vim.api.nvim_buf_get_lines(buf, 0, -1, false), buf end
  if vim.uv.fs_stat(path) then return vim.fn.readfile(path), nil end
  return {}, nil
end

--- Write `lines` as the note at `path`: into its buffer (then saved) when it is open, else to the file.
local function writeNote(path, lines)
  local buf = loadedBuf(path)
  if buf then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
  else
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile(lines, path)
  end
end

--- Append `block` at the end of the note `rel` (made when missing), one empty line before it.
local function appendTo(rel, block)
  local path = root() .. '/' .. rel
  local lines = readNote(path)
  while #lines > 0 and vim.trim(lines[#lines]) == '' do table.remove(lines) end
  if #lines > 0 then lines[#lines + 1] = '' end
  while #block > 0 and vim.trim(block[#block]) == '' do table.remove(block) end
  vim.list_extend(lines, block)
  writeNote(path, lines)
end

--- A new note of the garden folder for the idea `title`: named after it, _2, _3... when the name is taken.
local function ownNote(title)
  local base = slug(title)
  if base == '' then base = os.date('%Y%m%d%H%M%S') end
  local garden = V().note('garden', 'md')
  local rel, n = garden .. base .. '.md', 1
  while vim.uv.fs_stat(root() .. '/' .. rel) do
    n = n + 1
    rel = ('%s%s_%d.md'):format(garden, base, n)
  end
  return rel
end

-- -----------------------------------------------------------------------------
--  Links follow a moved heading
-- -----------------------------------------------------------------------------
--- A heading as Obsidian compares it in a link: punctuation is a space, spaces collapse, case does not matter.
function B.compareKey(s)
  return vim.trim((s:gsub('[!"#$%%&()*+,.:;<=>?@^`{|}~/%[%]\\\r\n]', ' '):gsub('%s+', ' '))):lower()
end

--- The .md notes of the vault at `r` as { path, rel }, leaving out files/ and hidden folders.
function B.files(r)
  local out = {}
  for _, path in ipairs(vim.fn.globpath(r, '**/*.md', false, true)) do
    path = vim.fs.normalize(path)
    local rel = path:sub(#r + 2)
    if not (rel:match('^files/') or rel:match('/%.') or rel:match('^%.')) then
      out[#out + 1] = { path = path, rel = rel }
    end
  end
  return out
end

--- Every [[fromRel#title...]] of the vault becomes [[toRel#title...]]; the number of links rewritten.
local function relink(fromRel, toRel, title)
  local want = B.compareKey(title)
  local total = 0
  local fresh = true
  for _, f in ipairs(B.files(root())) do
    local lines = readNote(f.path)
    local changed = false
    for i, l in ipairs(lines) do
      if l:find('[[', 1, true) then
        local new = l:gsub('(!?)%[%[([^%[%]]-)%]%]', function(bang, inner)
          local target, alias = inner:match('^(.-)|(.*)$')
          target = target or inner
          local path, sub = target:match('^(.-)#(.*)$')
          if not sub then return nil end
          local heading = sub:match('^[^#]*')
          if B.compareKey(heading) ~= want then return nil end
          local dest = path == '' and f.rel or notes().resolveLink(vim.trim(path), f.rel, fresh)
          fresh = false
          if dest ~= fromRel then return nil end
          total = total + 1
          local text = f.rel == toRel and '' or notes().linkText(toRel, f.rel)
          return bang .. '[[' .. text .. '#' .. sub .. (alias and ('|' .. alias) or '') .. ']]'
        end)
        if new ~= l then lines[i], changed = new, true end
      end
    end
    if changed then writeNote(f.path, lines) end
  end
  return total
end

-- -----------------------------------------------------------------------------
--  The section at the cursor, moved out
-- -----------------------------------------------------------------------------
--- The note and the section at the cursor, or nil (with a warning).
local function here()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' or not V().contains('md', path) then
    return warn('this buffer is not a note of the vault')
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local sec = B.section(lines, vim.api.nvim_win_get_cursor(0)[1])
  if not sec then return warn('not under a heading') end
  return { buf = buf, path = vim.fs.normalize(path), rel = relOf(path), lines = lines, sec = sec }
end

--- Move the section of `h` (its lines `block`) to the end of `rel`, keeping the links to it.
local function moveOut(h, rel, block)
  vim.api.nvim_buf_set_lines(h.buf, h.sec.line - 1, h.sec.last, false, {})
  vim.api.nvim_buf_call(h.buf, function() vim.cmd('silent write') end)
  appendTo(rel, toTopLevel(block, h.sec.level))
  return relink(h.rel, rel, h.sec.title)
end

--- Only the heading's tag line is rewritten (the rest of the section, the cursor too, stays as it is).
local function setStateInPlace(h, state)
  local n = tagRow(h.lines, h.sec)
  local tags = state and { '#' .. state } or {}
  if n then
    for t in h.lines[n]:gmatch('%S+') do
      if not isGardenState(t:sub(2)) then tags[#tags + 1] = t end
    end
    vim.api.nvim_buf_set_lines(h.buf, n - 1, n, false, #tags > 0 and { table.concat(tags, ' ') } or {})
  elseif state then
    vim.api.nvim_buf_set_lines(h.buf, h.sec.line, h.sec.line, false, { '#' .. state })
  end
  vim.api.nvim_buf_call(h.buf, function() vim.cmd('silent write') end)
end

local function plural(n) return n == 1 and '' or 's' end

-- -----------------------------------------------------------------------------
--  Grow, compost, the state menu, move
-- -----------------------------------------------------------------------------
--- One stage up: seed > sprout > plant > tree. A seed of the inbox becomes a sprout and moves to the nursery;
--- a sprout becomes a plant and moves to a note of its own in the garden folder; a tree is a plant grown big,
--- in the same note. A fruit is not a next step.
function B.grow()
  local h = here()
  if not h then return end
  local state = B.stateOf(h.lines, h.sec)
  if not state then return warn('not an idea heading (no #seed, #sprout... under it)') end
  local at = vim.fn.index(LADDER, state) + 1
  if at == 0 then return warn('a ' .. state .. ' is not on the ladder of the garden') end
  local nextStage = LADDER[at + 1]
  if not nextStage then return vim.notify('Already a ' .. state) end
  local dest
  if state == 'seed' and h.rel == V().inbox('md') then dest = V().nursery('md')
  elseif state == 'sprout' then dest = ownNote(h.sec.title) end
  if dest then
    local n = moveOut(h, dest, B.withState(h.lines, h.sec, nextStage))
    vim.notify(nextStage:upper() .. ': moved to ' .. dest .. (n > 0 and (' (%d link%s updated)'):format(n, plural(n)) or ''))
  else
    setStateInPlace(h, nextStage)
    vim.notify(nextStage:upper())
  end
end

--- An idea let go of: #compost. A seed or sprout moves to the compost note (nothing is erased); a plant, tree or
--- fruit has a note of its own and stays there, only marked #compost (Mia, 2026-11-17). Asks first, No by default.
function B.compost()
  local h = here()
  if not h then return end
  local compost = V().note('compost', 'md')
  local own = OWN_NOTE_STATES[B.stateOf(h.lines, h.sec) or '']
  local question = ('Compost "%s" (%s)?'):format(h.sec.title, own and 'it stays in its note' or ('move it to ' .. compost))
  if vim.fn.confirm(question, '&Yes\n&No', 2) ~= 1 then return end
  if own then
    setStateInPlace(h, 'compost')
    return vim.notify('COMPOST: kept in ' .. h.rel)
  end
  moveOut(h, compost, B.withState(h.lines, h.sec, 'compost'))
  vim.notify('COMPOST: moved to ' .. compost)
end

-- The checkbox right after the bullet (or the number) of a list item.
local CHECKBOX = '^(%s*[-*+]%s+)%[(.)%](.*)$'
local CHECKBOX_NUM = '^(%s*%d+[.)]%s+)%[(.)%](.*)$'

--- `line` with the checkbox state `state`, the way the Tasks plugin writes it: done adds " ✅ <today>",
--- cancelled " ❌ <today>", and leaving done or cancelled takes that date away. The date goes at the end, before a
--- " ^block" id. The other fields (⏳ 📅 ➕ 🔁) are left alone. nil when the line has no checkbox.
function B.taskLine(line, state, today)
  local prefix, old, rest = line:match(CHECKBOX)
  if not prefix then prefix, old, rest = line:match(CHECKBOX_NUM) end
  if not prefix then return nil end
  today = today or os.date('%Y-%m-%d')
  local body, block = rest:match('^(.-)(%s+%^[%w-]+)%s*$')
  if body then rest = body end
  rest = rest:gsub('%s+✅%s*%d%d%d%d%-%d%d%-%d%d', ''):gsub('%s+❌%s*%d%d%d%d%-%d%d%-%d%d', '')
  rest = rest:gsub('%s+$', '')
  if state == 'x' or state == 'X' then rest = rest .. ' ✅ ' .. today
  elseif state == '-' then rest = rest .. ' ❌ ' .. today end
  return prefix .. '[' .. state .. ']' .. rest .. (block or '')
end

--- Whether the dates of the Tasks plugin are written in buffer `buf`: a note of a Markdown vault.
function B.writesTaskDates(buf)
  buf = buf or 0
  return vim.bo[buf].buftype == '' and V().contains('md', vim.api.nvim_buf_get_name(buf))
end

--- The state menu (<leader>vt): on a checkbox, the six task states; on a heading, the garden's and "no state".
function B.todoState()
  local line = vim.api.nvim_get_current_line()
  local _, cur = line:match(CHECKBOX)
  if not cur then _, cur = line:match(CHECKBOX_NUM) end
  if cur then
    local labels = {}
    for _, s in ipairs(TASK_STATES) do labels[#labels + 1] = (s[1] == cur:lower() and '• ' or '') .. s[2] end
    vim.ui.select(labels, { prompt = 'Status of the task' }, function(_, i)
      if not i or TASK_STATES[i][1] == cur then return end
      vim.api.nvim_set_current_line(B.taskLine(vim.api.nvim_get_current_line(), TASK_STATES[i][1]))
    end)
    return
  end
  local h = here()
  if not h then return end
  local current = B.stateOf(h.lines, h.sec)
  local labels = {}
  for _, s in ipairs(GARDEN_STATES) do labels[#labels + 1] = (s == current and '• ' or '') .. s:upper() end
  labels[#labels + 1] = 'no state'
  vim.ui.select(labels, { prompt = 'State of "' .. h.sec.title .. '"' }, function(_, i)
    if not i then return end
    local pick = GARDEN_STATES[i]
    if pick == current then return end
    setStateInPlace(h, pick)
  end)
end

--- The note of the sources folder named `type` (any case), as a path from the vault's folder, or nil.
function B.sourceFile(type)
  local r = root()
  if not r or type == nil or vim.trim(type) == '' then return nil end
  local want = vim.fn.tolower(vim.trim(type)) .. '.md'
  local sources = V().note('sources', 'md')
  for name, kind in vim.fs.dir(r .. '/' .. sources) do
    if kind == 'file' and vim.fn.tolower(name) == want then return sources .. name end
  end
end

--- Move the heading at the cursor, with everything under it, to another note: the note of its type:: when the
--- sources folder has one, else a note picked in the list. It lands at the top level; its links follow it.
function B.move()
  local h = here()
  if not h then return end
  local block = vim.list_slice(h.lines, h.sec.line, h.sec.last)
  local type
  for _, l in ipairs(block) do
    type = l:match('^[Tt][Yy][Pp][Ee]::%s*(.-)%s*$')
    if type then break end
  end
  local function go(dest)
    local n = moveOut(h, dest, block)
    vim.notify('Moved to ' .. dest .. (n > 0 and (' (%d link%s updated)'):format(n, plural(n)) or ''))
  end
  local dest = B.sourceFile(type)
  if dest and dest ~= h.rel then return go(dest) end
  local items = {}
  for _, f in ipairs(B.files(root())) do
    if f.rel ~= h.rel then items[#items + 1] = f.rel end
  end
  table.sort(items)
  vim.ui.select(items, { prompt = 'Move "' .. h.sec.title .. '" to' }, function(choice)
    if choice then go(choice) end
  end)
end

-- -----------------------------------------------------------------------------
--  Find (pure/vault.lua's list): how a Markdown note is read
-- -----------------------------------------------------------------------------
local FIND_MAX_LEVEL = 4
local parsed = {}

--- { mtime, title (the file name: a note's title is its name), aliases (front matter), headings }.
function B.parse(path)
  local stat = vim.uv.fs_stat(path)
  local hit = parsed[path]
  if hit and stat and hit.mtime == stat.mtime.sec then return hit end
  local ok, lines = pcall(vim.fn.readfile, path)
  local info = { mtime = stat and stat.mtime.sec or 0, title = nil, aliases = {}, headings = {} }
  if not ok then return info end
  if lines[1] == '---' then
    local inAliases = false
    for i = 2, #lines do
      local l = lines[i]
      if l == '---' then break end
      local key, value = l:match('^([%w_-]+):%s*(.-)%s*$')
      if key then
        inAliases = key:lower() == 'aliases'
        if inAliases and value ~= '' then
          for a in value:gsub('^%[', ''):gsub('%]$', ''):gmatch('[^,]+') do
            a = vim.trim(a):gsub('^["\']', ''):gsub('["\']$', '')
            if a ~= '' then info.aliases[#info.aliases + 1] = a end
          end
        end
      elseif inAliases then
        local a = l:match('^%s*%-%s*(.-)%s*$')
        if a then
          a = a:gsub('^["\']', ''):gsub('["\']$', '')
          if a ~= '' then info.aliases[#info.aliases + 1] = a end
        end
      end
    end
  end
  for _, h in ipairs(B.headings(lines)) do
    if h.level <= FIND_MAX_LEVEL and h.title ~= '' then
      info.headings[#info.headings + 1] = { level = h.level, text = h.title, lnum = h.line, aliases = {} }
    end
  end
  parsed[path] = info
  return info
end

--- A new seed called `title` at the end of the inbox, then open it at the seed.
function B.newTitle(title)
  local r = V().path('md')
  if not r then return end
  local inbox = V().inbox('md')
  appendTo(inbox, { '# ' .. title, '#seed', 'created:: ' .. stamp() })
  vim.cmd('edit ' .. vim.fn.fnameescape(r .. '/' .. inbox))
  vim.cmd('silent! checktime')
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i = #lines, 1, -1 do
    if lines[i] == '# ' .. title then pcall(vim.api.nvim_win_set_cursor, 0, { i, 0 }) break end
  end
end
B.ext = 'md'
B.afterMove = function() pcall(function() notes().index(true) end) end

-- -----------------------------------------------------------------------------
--  Notes and links: pure/notes.lua
-- -----------------------------------------------------------------------------
B.rename = function() notes().rename() end
B.backlinks = function() notes().backlinks() end

--- A new note in its own file at the root of the vault, named by its title.
function B.newNote()
  local r = V().path('md')
  if not r then return end
  vim.ui.input({ prompt = 'New note: ' }, function(title)
    title = title and vim.trim(title) or ''
    if title == '' then return end
    local path = r .. '/' .. title:gsub('[\\/:*?"<>|]', ' ') .. '.md'
    if vim.uv.fs_stat(path) then return warn(vim.fs.basename(path) .. ' exists') end
    vim.fn.writefile({ '# ' .. title, '' }, path)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    B.afterMove()
  end)
end

--- Insert a link to a note or a heading at the cursor: the list of <leader>vf.
function B.insertLink()
  local r = V().path('md')
  if not r then return end
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local from = relOf(vim.api.nvim_buf_get_name(buf))
  local entries = V()._find.entries(r)
  local lines = {}
  for i, e in ipairs(entries) do lines[#lines + 1] = V()._find.line(e):match('^([^\t]*)') .. '\t' .. i end
  require('pure.notecolors').apply()
  require('pure.fuzzyUtils').pickList(lines, { title = ' Link to ', ratio = 0.8,
    fzf = "--ansi --delimiter '\\t' --with-nth 1 --tiebreak=index" }, function(selection)
    local e = entries[tonumber((selection or ''):match('\t(%d+)%s*$') or '')]
    if not e then return end
    local name = notes().linkText(e.path, from)
    local link = e.kind == 'heading' and ('[[%s#%s]]'):format(name, e.title)
      or (e.kind == 'alias' and not e.heading) and ('[[%s|%s]]'):format(name, e.title)
      or ('[[%s]]'):format(name)
    if not vim.api.nvim_win_is_valid(win) then return end
    vim.api.nvim_set_current_win(win)
    local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ''
    vim.api.nvim_buf_set_lines(buf, cursor[1] - 1, cursor[1], false,
      { line:sub(1, cursor[2] + 1) .. link .. line:sub(cursor[2] + 2) })
  end)
end

-- -----------------------------------------------------------------------------
--  Captures (<leader>vq): node, task, task + deadline, link, journal
-- -----------------------------------------------------------------------------
--  The same captures as the vault's Obsidian (capture.js) and the org vault: a draft opens in a floating
--  window with the template; :w (or <C-c><C-c>) stores it where it belongs and closes it, <C-c><C-k> or :q
--  drops it. A draft with nothing written is dropped.

local SOURCE_PROPERTIES = { 'type', 'author', 'status', 'genre', 'language', 'by', 'where', 'rating', 'notes' }
local GARDEN_TYPES = {
  seed = { 'seed', 'inbox' }, sprout = { 'sprout', 'nursery' }, plant = { 'plant', 'own' },
  tree = { 'tree', 'own' }, fruit = { 'fruit', 'own' }, compost = { 'compost', 'compost' },
}
local DATE_WORDS = { hoje = 'today', ['amanhã'] = 'tomorrow', amanha = 'tomorrow', ontem = 'yesterday',
  agora = 'today', oggi = 'today', domani = 'tomorrow', ieri = 'yesterday', ora = 'today', now = 'today' }
local WEEKDAYS = { 'sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat' }

--- A date in words or numbers as YYYY-MM-DD, and the time when one follows ("tomorrow 10:00"), or nil.
--- today, tomorrow, yesterday (and hoje, amanhã, oggi, domani...), +3d / +2w / +1m / +1y, a weekday (the
--- next one, today included), 2026-11-20.
function B.readDate(text, now)
  now = now or os.time()
  local t = vim.trim(text or ''):lower()
  local time = t:match('%s(%d%d?:%d%d)$')
  if time then t = vim.trim(t:sub(1, #t - #time)) end
  t = DATE_WORDS[t] or t
  local d = os.date('*t', now)
  local function day(offset, unit)
    local x = { year = d.year, month = d.month, day = d.day, hour = 12 }
    if unit == 'm' then x.month = x.month + offset elseif unit == 'y' then x.year = x.year + offset
    else x.day = x.day + offset * (unit == 'w' and 7 or 1) end
    return os.date('%Y-%m-%d', os.time(x))
  end
  local out
  if t == 'today' then out = day(0)
  elseif t == 'tomorrow' then out = day(1)
  elseif t == 'yesterday' then out = day(-1)
  else
    local n, unit = t:match('^%+(%d+)([dwmy])$')
    if n then out = day(tonumber(n), unit) end
    for i, w in ipairs(WEEKDAYS) do
      if not out and #t >= 3 and t:sub(1, 3) == w then out = day((i - d.wday + 7) % 7) end
    end
    local y, m, dd = t:match('^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$')
    if not out and y then out = ('%04d-%02d-%02d'):format(y, m, dd) end
  end
  if not out then return nil end
  if time and #time == 4 then time = '0' .. time end
  return out, time
end

--- A draft read back: its title (the first heading), its key:: value lines right under it, and the rest.
local function parseDraft(lines)
  local i = 1
  while i <= #lines and vim.trim(lines[i]) == '' do i = i + 1 end
  local title = vim.trim((lines[i] or ''):gsub('^#+%s*', ''))
  i = i + 1
  local props = {}
  while i <= #lines do
    local k, v = lines[i]:match('^([%a_-]+)::%s?(.*)$')
    if not k then break end
    props[#props + 1] = { k:lower(), vim.trim(v) }
    i = i + 1
  end
  local body = {}
  for n = i, #lines do body[#body + 1] = lines[n] end
  while #body > 0 and vim.trim(body[1]) == '' do table.remove(body, 1) end
  while #body > 0 and vim.trim(body[#body]) == '' do table.remove(body) end
  return title, props, body
end

local function prop(props, key)
  for _, p in ipairs(props) do if p[1] == key then return p[2] end end
end

--- An entry: the heading, its state tag, the properties that are not empty, the body after an empty line.
local function entry(title, tag, props, body)
  local out = { '# ' .. title }
  if tag then out[#out + 1] = '#' .. tag end
  for _, p in ipairs(props) do
    if p[2] and vim.trim(p[2]) ~= '' then out[#out + 1] = p[1] .. ':: ' .. vim.trim(p[2]) end
  end
  if #body > 0 then out[#out + 1] = '' vim.list_extend(out, body) end
  return out
end

local function storeNode(lines)
  local title, props, body = parseDraft(lines)
  local type = prop(props, 'type') or ''
  local key = type:lower()
  local function list(withType)
    local out = {}
    if withType then out[1] = { 'type', type } end
    for _, p in ipairs(props) do if p[1] ~= 'type' then out[#out + 1] = p end end
    out[#out + 1] = { 'created', stamp() }
    return out
  end
  local garden = GARDEN_TYPES[key]
  if garden then
    local state, place = garden[1], garden[2]
    local block = entry(title, state, list(false), body)
    if place == 'inbox' then return appendTo(V().inbox('md'), block) end
    if place == 'nursery' then return appendTo(V().nursery('md'), block) end
    if place == 'compost' then return appendTo(V().note('compost', 'md'), block) end
    local rel = ownNote(title)
    appendTo(rel, block)
    return vim.notify(state .. ': a note of its own, ' .. rel)
  end
  local source = key ~= '' and B.sourceFile(type) or nil
  if source then return appendTo(source, entry(title, nil, list(true), body)) end
  if key ~= '' then
    warn(('no note %s%s.md: the entry goes to the inbox as a seed'):format(V().note('sources', 'md'), key))
  end
  appendTo(V().inbox('md'), entry(title, 'seed', list(key ~= ''), body))
end

--- A task: a checkbox of the Tasks plugin in the tasks note, "- [ ] title ➕ created ⏳ scheduled 📅 due"; a
--- time goes in an indented scheduled:: line under it, the body indented under it too. false when the capture
--- must stay open (a deadline left empty, or a date that could not be read).
local function storeTask(lines, withDeadline)
  local title, props, body = parseDraft(lines)
  local fields, extra = { '➕ ' .. os.date('%Y-%m-%d') }, {}
  for _, p in ipairs(props) do
    local k, v = p[1], p[2]
    if (k == 'scheduled' or k == 'deadline') and v ~= '' then
      local date, time = B.readDate(v)
      if not date then
        warn(('could not read the date "%s"'):format(v))
        return false
      end
      fields[#fields + 1] = (k == 'scheduled' and '⏳ ' or '📅 ') .. date
      if time then extra[#extra + 1] = '  ' .. k .. ':: ' .. date .. ' ' .. time end
    elseif k ~= 'scheduled' and k ~= 'deadline' and v ~= '' then
      extra[#extra + 1] = '  ' .. k .. ':: ' .. v
    end
  end
  if withDeadline and (prop(props, 'deadline') or '') == '' then
    warn('the deadline is empty: fill deadline:: (today, fri, 2026-11-20...)')
    return false
  end
  local out = { '- [ ] ' .. title .. ' ' .. table.concat(fields, ' ') }
  vim.list_extend(out, extra)
  for _, l in ipairs(body) do out[#out + 1] = '  ' .. l end
  appendTo(V().note('tasks', 'md'), out)
  return true
end

local function storeLink(lines)
  local title, _, body = parseDraft(lines)
  -- An address with spaces works only inside < >.
  title = title:gsub('%]%(([^<)][^)]*%s[^)]*)%)', '](<%1>)')
  appendTo(V().inbox('md'), entry(title, nil, { { 'created', stamp() } }, body))
end

--- The journal: # YYYY / ## YYYY-MM Month / ### YYYY-MM-DD Weekday / the entry (#### HH:mm text and its lines),
--- each level made when missing, in date order; the entry at the end of its day.
-- In English whatever the locale, as the journal is written (os.date's %B and %A follow the locale).
local MONTHS = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December' }
local DAYS = { 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday' }

function B.journalInsert(lines, item, now)
  now = now or os.time()
  local t = os.date('*t', now)
  local levels = {
    { key = os.date('%Y', now), line = '# ' .. os.date('%Y', now) },
    { key = os.date('%Y-%m', now), line = '## ' .. os.date('%Y-%m ', now) .. MONTHS[t.month] },
    { key = os.date('%Y-%m-%d', now), line = '### ' .. os.date('%Y-%m-%d ', now) .. DAYS[t.wday] },
  }
  lines = vim.deepcopy(lines)
  while #lines > 0 and vim.trim(lines[#lines]) == '' do table.remove(lines) end
  local function depth(l) local h = l:match('^(#+) ') return h and #h or 0 end
  local from, to = 1, #lines + 1 -- the range [from, to) the next level lives in
  for d, lv in ipairs(levels) do
    local at, insertAt = nil, to
    for i = from, to - 1 do
      if depth(lines[i]) == d then
        local k = lines[i]:sub(d + 2):match('^(%S+)')
        if k == lv.key then at = i break end
        if k and k > lv.key and insertAt == to then insertAt = i end
      end
    end
    if not at then
      local prev = lines[insertAt - 1]
      local add = (prev and vim.trim(prev) ~= '' and (depth(prev) == 0 or depth(prev) >= d)) and { '', lv.line } or { lv.line }
      for k = #add, 1, -1 do table.insert(lines, insertAt, add[k]) end
      at = insertAt + #add - 1
      to = to + #add
    end
    local e = at + 1
    while e < to and not (depth(lines[e]) > 0 and depth(lines[e]) <= d) do e = e + 1 end
    from, to = at + 1, e
  end
  local pos = to
  while pos > from and vim.trim(lines[pos - 1]) == '' do pos = pos - 1 end
  local add = vim.deepcopy(item)
  if pos > from then table.insert(add, 1, '') end
  for k = #add, 1, -1 do table.insert(lines, pos, add[k]) end
  return lines
end

local function storeJournal(lines)
  local item = vim.deepcopy(lines)
  while #item > 0 and vim.trim(item[#item]) == '' do table.remove(item) end
  local path = root() .. '/' .. V().note('journal', 'md')
  writeNote(path, B.journalInsert((readNote(path)), item))
end

local CURSOR = '\1'
local TEMPLATES = {
  node = function()
    local l = { '# ' .. CURSOR }
    for _, k in ipairs(SOURCE_PROPERTIES) do l[#l + 1] = k .. ':: ' end
    return l
  end,
  task = function() return { '# ' .. CURSOR, 'scheduled:: ' } end,
  deadline = function() return { '# ' .. CURSOR, 'deadline:: ' } end,
  link = function()
    local clip = vim.trim(((vim.fn.getreg('+') or ''):match('[^\r\n]*')) or '')
    return { '# [' .. CURSOR .. '](' .. clip .. ')' }
  end,
  journal = function() return { '#### ' .. os.date('%H:%M') .. ' ' .. CURSOR } end,
}

--- Whether nothing was written in the draft: no title (a link without one, a journal line with only its time),
--- every property empty, no body.
local function isEmpty(lines)
  local title, props, body = parseDraft(lines)
  local bare = vim.trim(title:gsub('^%[%]%(.*%)$', ''):gsub('^%d%d:%d%d$', ''))
  for _, p in ipairs(props) do if p[2] ~= '' then return false end end
  return bare == '' and #body == 0
end

--- Store the draft of `kind` (its lines). false when it must stay open.
function B.store(kind, lines)
  if isEmpty(lines) then return true end
  if kind == 'node' then storeNode(lines)
  elseif kind == 'task' or kind == 'deadline' then
    if not storeTask(lines, kind == 'deadline') then return false end
  elseif kind == 'link' then storeLink(lines)
  elseif kind == 'journal' then storeJournal(lines) end
  vim.notify('Captured (' .. kind .. ')')
  return true
end

--- Open the draft of `kind` in a floating window.
function B.openCapture(kind)
  local template = TEMPLATES[kind]()
  local row, col = 1, 0
  for i, l in ipairs(template) do
    local c = l:find(CURSOR, 1, true)
    if c then row, col, template[i] = i, c - 1, l:gsub(CURSOR, '') end
  end
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, 'capture://' .. kind .. '/' .. buf)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, template)
  vim.bo[buf].modified = false
  local win = require('configs.functions').createWindow(' Capture: ' .. kind .. ' ', 0.8, { buf = buf })
  local function close()
    if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  end
  local function store()
    if B.store(kind, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then
      vim.bo[buf].modified = false
      vim.cmd('stopinsert')
      close()
    end
  end
  vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = store })
  vim.keymap.set({ 'n', 'i' }, '<C-c><C-c>', store, { buffer = buf, desc = 'Store the capture' })
  vim.keymap.set({ 'n', 'i' }, '<C-c><C-k>', function() vim.cmd('stopinsert') close() end,
    { buffer = buf, desc = 'Drop the capture' })
  pcall(vim.api.nvim_win_set_cursor, win, { row, col })
  vim.cmd('startinsert!')
  return buf, win
end

local CAPTURE_MENU = { { 'n', 'node', 'Node (by its type::)' }, { 't', 'task', 'Task' },
  { 'T', 'deadline', 'Task + deadline' }, { 'l', 'link', 'Link' }, { 'j', 'journal', 'Journal' } }

--- The capture menu (<leader>vq): n node, t task, T task + deadline, l link, j journal.
function B.capture(kind)
  if kind then return B.openCapture(kind) end
  local labels = {}
  for _, c in ipairs(CAPTURE_MENU) do labels[#labels + 1] = c[1] .. '  ' .. c[3] end
  vim.ui.select(labels, { prompt = 'Capture' }, function(_, i)
    if i then B.openCapture(CAPTURE_MENU[i][2]) end
  end)
end
B.newSeed = function() B.openCapture('node') end
B.journalLine = function() B.openCapture('journal') end

--- Today in the journal: its heading (made when missing), the cursor under it.
function B.journalToday()
  local r = V().path('md')
  if not r then return end
  local rel = V().note('journal', 'md')
  local path = r .. '/' .. rel
  local lines = readNote(path)
  local day = '### ' .. os.date('%Y-%m-%d')
  local at
  for i, l in ipairs(lines) do if l:sub(1, #day) == day then at = i end end
  if not at then
    lines = B.journalInsert(lines, {})
    writeNote(path, lines)
    for i, l in ipairs(lines) do if l:sub(1, #day) == day then at = i end end
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  pcall(vim.api.nvim_win_set_cursor, 0, { at or 1, 0 })
end

return B
