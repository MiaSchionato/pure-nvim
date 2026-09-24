-- =============================================================================
--  Todoist
-- =============================================================================
--  Todoist tasks in an editable buffer, like oil.nvim does for files: edit
--  the list as text and :w applies the difference to Todoist. Talks to the
--  Todoist API v1 through curl.
--
--    :Todoist                 all active tasks
--    :Todoist today | overdue any Todoist filter query (as in the app)
--
--  The buffer is a markdown task list, one section per project:
--
--    ## Work
--    - [ ] Write the README due:today p1
--      - [ ] Sub step due:tomorrow
--    - [ ] Review PR
--
--    - text first, then due:<any Todoist date phrase, in English> and a
--      priority p1..p3 as the last word (no pN = normal priority)
--    - indenting a line makes it a subtask of the line above it
--    - the ## heading is the project: move a line under another to move it
--    - new line = new task, deleted line = deleted task, [x] = complete
--    - each task ends in a hidden id (concealed); a copied line becomes a
--      new task
--
--  :w shows what will change and asks before sending it. How often it asks is
--  set with vim.g.pure_todoist_confirm:
--    'all'     every save (default)
--    'delete'  only when the save would delete tasks
--    'never'   never
--  Also:
--    <CR> / x   toggle the checkbox on the cursor line (x does not delete here)
--    <leader>x  cycle [ ] [~] [!] [>] [-] [x]; only [x] (done) reaches Todoist,
--               the other states are kept locally and drawn back on reload
--    r          reload (asks first if there are unsaved edits)
--    q / <Esc>  close (same)
--
--  Token (Todoist > Settings > Integrations > Developer), never kept in this
--  repository. Either of:
--    - a file holding just the token: stdpath('data')/todoist_token
--      (~/.local/share/nvim/todoist_token, or %LOCALAPPDATA%\nvim-data\ on
--      Windows). :TodoistToken writes it for you.
--    - the TODOIST_API_TOKEN environment variable
--
--  Archive: set vim.g.pure_todoist_archive to a folder to keep tasks.md (the
--  full list), history.md (each change, with its time) and tasks.json there,
--  written in the background and only when something changed. See "Archive".
--
--  When neither exists, Neovim asks for it on startup, with the option to stop
--  asking. :TodoistToken sets the token later and turns the question back on.
-- =============================================================================

local M = {}

local api = 'https://api.todoist.com/api/v1'

-- Both live in the data directory, outside the config repository.
local token_file = vim.fn.stdpath('data') .. '/todoist_token'
local no_prompt_file = vim.fn.stdpath('data') .. '/todoist_no_prompt'

-- -----------------------------------------------------------------------------
--  HTTP
-- -----------------------------------------------------------------------------

local function token()
  local env = vim.env.TODOIST_API_TOKEN
  if env and env ~= '' then return env end
  local f = io.open(token_file, 'r')
  if not f then return nil end
  local t = vim.trim(f:read('*l') or '')
  f:close()
  -- An empty file counts as no token, so the startup question still comes up.
  return t ~= '' and t or nil
end

local function urlencode(s)
  return (s:gsub('[^%w%-_%.~]', function(c) return ('%%%02X'):format(c:byte()) end))
end

--- Call the API and hand the decoded JSON to `cb(err, data)` on the main loop.
---
--- The Authorization header is fed to curl on stdin (-H @-) rather than as an
--- argument, so the token never shows up in the process list.
---
--- `body`, when given, is sent as JSON. It is no secret, so it can go on the
--- command line; vim.system passes arguments without a shell, so its quotes
--- need no escaping on any platform.
local function request(method, path, cb, body)
  local tok = token()
  if not tok then
    return cb('No Todoist token: run :TodoistToken to set it')
  end

  local base = vim.g.pure_todoist_url or api
  local cmd = { 'curl', '-sS', '-X', method, '-H', '@-', '-w', '\n%{http_code}', base .. path }
  if body then
    vim.list_extend(cmd, { '-H', 'Content-Type: application/json', '--data-binary', vim.json.encode(body) })
  end
  local ok, err = pcall(vim.system, cmd, { stdin = 'Authorization: Bearer ' .. tok .. '\n', text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        return cb('curl failed: ' .. vim.trim(res.stderr or ''))
      end
      local body, status = res.stdout:match('^(.*)\n(%d+)$')
      status = tonumber(status)
      if not status or status >= 300 then
        return cb(('Todoist API %s %s -> HTTP %s %s'):format(method, path, tostring(status), vim.trim(body or '')))
      end
      if body == '' then return cb(nil, nil) end
      local decoded_ok, data = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
      if not decoded_ok then return cb('Invalid JSON from Todoist: ' .. tostring(data)) end
      cb(nil, data)
    end))
  if not ok then cb('Could not run curl: ' .. tostring(err)) end
end

--- GET every page of a paginated list endpoint ({ results, next_cursor }).
local function getAll(path, cb)
  local items = {}
  local function page(cursor)
    local sep = path:find('?', 1, true) and '&' or '?'
    local url = path .. sep .. 'limit=200' .. (cursor and ('&cursor=' .. urlencode(cursor)) or '')
    request('GET', url, function(err, data)
      if err then return cb(err) end
      vim.list_extend(items, data.results or {})
      if data.next_cursor then return page(data.next_cursor) end
      cb(nil, items)
    end)
  end
  page(nil)
end

-- -----------------------------------------------------------------------------
--  Shared helpers
-- -----------------------------------------------------------------------------

--- Todoist stores priority 4 as the most urgent; the app shows that as P1.
local function priorityLabel(p)
  p = tonumber(p) or 1
  return p > 1 and ('P' .. (5 - p)) or ''
end

local function dueSortKey(task)
  -- No due date sorts last.
  return task.due and task.due.date or '9999-99-99'
end

--- Due date first (none last), then the most urgent priority.
local function sortTasks(tasks)
  table.sort(tasks, function(a, b)
    local da, db = dueSortKey(a), dueSortKey(b)
    if da ~= db then return da < db end
    return (tonumber(a.priority) or 1) > (tonumber(b.priority) or 1)
  end)
end

--- The due date as the buffer shows and edits it: Todoist's own phrase
--- ("every monday"), so an untouched recurring date is sent back unchanged.
local function dueText(t)
  return t.due and (t.due.string or t.due.date) or ''
end

-- -----------------------------------------------------------------------------
--  Task buffer
-- -----------------------------------------------------------------------------
--  Works like oil.nvim: the buffer is rendered from the API, `snapshot` keeps
--  what each task looked like, and on :w the parsed buffer is compared with it
--  to work out creates, updates, moves, completions and deletes.

local state = {
  buf = nil,
  filter = nil,
  snapshot = {}, -- id -> { content, due, priority, project_id, parent_id, checked }
  projects = { by_name = {}, by_id = {}, inbox = nil },
  saving = false,
  loaded = nil, -- filter key ('' = all) the buffer currently shows
}

local id_ns = vim.api.nvim_create_namespace('pure_todoist_ids')

-- Priorities in Todoist's own colours, which are clearly apart; the theme's
-- Diagnostic groups were pale pastels where p1 and p2 looked alike. The due
-- date is secondary information, so it is dimmed rather than coloured.
-- `default`: a theme may define these groups itself.
local function setTodoistHighlights()
  vim.api.nvim_set_hl(0, 'PureTodoistP1', { fg = '#d1453b', default = true })
  vim.api.nvim_set_hl(0, 'PureTodoistP2', { fg = '#eb8909', default = true })
  vim.api.nvim_set_hl(0, 'PureTodoistP3', { fg = '#246fe0', default = true })
  vim.api.nvim_set_hl(0, 'PureTodoistDue', { link = 'Comment', default = true })
end
setTodoistHighlights()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setTodoistHighlights })
local hint_ns = vim.api.nvim_create_namespace('pure_todoist_hint')

local function oneLine(s)
  return (tostring(s or ''):gsub('\n', ' '):gsub('%s%s+', ' '))
end

--- Split a task's text from its metadata, which follows it after a single
--- space: 'due:<date phrase>' (spaces allowed: 'due:next monday 10:00') and a
--- priority 'p1'..'p4' as the last word, before or after the due date.
--- Returns content, due ('' if none), priority (API value, 4 = p1) and the
--- ranges of the metadata in `s` ({ from, to, kind }) for highlighting.
local function splitMeta(s)
  local ranges, priority = {}, 1

  -- A trailing ' pN' word; `offset` maps positions in `part` back to `s`.
  local function takePriority(part, offset)
    local head, n = part:match('^(.-)%s+[pP]([1-4])%s*$')
    if not head then return part end
    local at = part:find('[pP][1-4]%s*$', #head + 1)
    priority = 5 - tonumber(n)
    table.insert(ranges, { offset + at, offset + at + 1, 'p' .. n })
    return head
  end

  local due, content = '', s
  local at = s:find('%sdue:')
  if at then
    local tail = takePriority(s:sub(at + 1), at) -- 'due:...' without a trailing pN
    due = vim.trim(tail:sub(5))
    table.insert(ranges, { at + 1, at + #tail, 'due' })
    content = s:sub(1, at - 1)
  end
  content = takePriority(content, 0)
  return vim.trim(content), due, priority, ranges
end

-- Obsidian's extra checkbox states ([~] in progress, [!] important, [>]
-- deferred, [-] cancelled) have no field in Todoist, which only knows done or
-- not. They are kept on this machine, per task id, and drawn back into the
-- list; to Todoist those tasks are simply not done.
local states_file = vim.fn.stdpath('data') .. '/todoist_states.json'

local function readStates()
  local f = io.open(states_file, 'r')
  if not f then return {} end
  local ok, data = pcall(vim.json.decode, f:read('*a'))
  f:close()
  return ok and type(data) == 'table' and data or {}
end

--- Record the state of every parsed item (and forget completed and deleted
--- tasks). Returns true when the file changed.
local state_names = { ['~'] = 'in progress', ['!'] = 'important', ['>'] = 'deferred', ['-'] = 'cancelled' }

--- Also returns history entries for the marks that changed.
local function saveStates(items, deleted_ids)
  local store = readStates()
  local before = vim.json.encode(store)
  local entries = {}
  for _, item in ipairs(items) do
    if item.id then
      local mark = (not item.checked) and item.mark or nil
      if mark ~= store[item.id] and not item.checked then
        table.insert(entries, mark and ('marked [%s] %s · %s'):format(mark, state_names[mark] or '', item.content)
          or ('cleared mark · ' .. item.content))
      end
      store[item.id] = mark
    end
  end
  for _, id in ipairs(deleted_ids or {}) do store[id] = nil end
  local after = vim.json.encode(store)
  if after == before then return false, entries end
  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  local f = io.open(states_file, 'w')
  if f then f:write(after) f:close() end
  return true, entries
end

--- `- [ ] text due:today p1 ‹id›` at the given depth; `mark` is a local state.
local function taskLine(t, depth, mark)
  local box = t.checked and 'x' or (mark or ' ')
  local parts = { ('%s- [%s] %s'):format(string.rep('  ', depth), box, oneLine(t.content)) }
  local due = dueText(t)
  if due ~= '' then table.insert(parts, 'due:' .. due) end
  local p = priorityLabel(t.priority):lower()
  if p ~= '' then table.insert(parts, p) end
  return table.concat(parts, ' ') .. ' ‹' .. t.id .. '›'
end

--- Parse one buffer line; nil when it is not a task.
--- Accepts '- text' without a box too, so a quickly typed line still counts.
local function parseLine(line)
  local indent, rest = line:match('^(%s*)[-*+]%s+(.*)$')
  if not indent then
    -- A bare line of text is a task too, as a bare name is a file in oil:
    -- typing "Buy bread" under a heading is enough. Headings and blank
    -- lines are not.
    if line:match('^%s*$') or line:match('^%s*#') then return nil end
    indent, rest = line:match('^(%s*)(.-)%s*$')
  end

  local body, id = rest:match('^(.-)%s*‹([%w_%-]+)›%s*$')
  body = body or rest

  -- Any one-character box: [x] is done; [~] [!] [>] [-] are local states.
  local checked, mark = false, nil
  local box, after = body:match('^%[(.)%]%s*(.*)$')
  if box then
    checked = box == 'x' or box == 'X'
    if not checked and box ~= ' ' then mark = box end
    body = after
  end

  local content, due, priority = splitMeta(body)
  if content == '' then return nil end

  local width = indent:gsub('\t', '  ')
  return { indent = #width, checked = checked, mark = mark, content = content, due = due, priority = priority, id = id }
end

--- Hide the ids and colour the metadata. Re-run on every change, since
--- editing moves the text the marks were placed on.
local function decorate(buf)
  vim.api.nvim_buf_clear_namespace(buf, id_ns, 0, -1)
  local priority_hl = { 'PureTodoistP1', 'PureTodoistP2', 'PureTodoistP3' }
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if parseLine(line) then
      local id_start, id_end = line:find('%s*‹[%w_%-]+›%s*$')
      if id_start then
        vim.api.nvim_buf_set_extmark(buf, id_ns, row - 1, id_start - 1, { end_col = id_end, conceal = '' })
      end

      -- The same split parseLine uses, run on the line minus its id.
      local _, _, _, ranges = splitMeta(line:sub(1, (id_start or #line + 1) - 1))
      for _, r in ipairs(ranges) do
        if r[3] == 'due' then
          vim.api.nvim_buf_set_extmark(buf, id_ns, row - 1, r[1] - 1, { end_col = r[2], hl_group = 'PureTodoistDue' })
        else
          -- 'pN' is concealed into a coloured flag (p4, normal priority, into
          -- nothing). Like the ids it shows as text again while the line is
          -- being edited, since the window's concealcursor is 'nc'.
          local n = tonumber(r[3]:sub(2))
          vim.api.nvim_buf_set_extmark(buf, id_ns, row - 1, r[1] - 1, {
            end_col = r[2],
            conceal = priority_hl[n] and '\u{F023B}' or '', -- md-flag
            hl_group = priority_hl[n],
          })
        end
      end
    end
  end
end

local function setLines(lines)
  local buf = state.buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  decorate(buf)
end

-- -----------------------------------------------------------------------------
--  Archive
-- -----------------------------------------------------------------------------
--  With vim.g.pure_todoist_archive set to a folder, the plugin keeps there:
--
--    tasks.md    the full task list as the buffer shows it, without the ids
--    history.md  one timestamped line per change: those made here with :w,
--                and those made elsewhere (the app, the phone), noticed when
--                the full list is reloaded
--    tasks.json  the last full list, to tell what changed since
--
--  tasks.md and tasks.json hold no timestamp and are rewritten only when their
--  content differs, so reloading an unchanged list touches nothing. All disk
--  work goes through libuv's asynchronous calls, off the editing path; only
--  the text is prepared on the main loop.

local archive = { skip_external = false }
local uv = vim.uv

--- The archive folder (created on first use), or nil when archiving is off.
local function archiveDir()
  local dir = vim.g.pure_todoist_archive
  if type(dir) ~= 'string' or dir == '' then return nil end
  dir = vim.fs.normalize(vim.fn.expand(dir))
  vim.fn.mkdir(dir, 'p')
  return dir
end

local function readAsync(path, cb)
  uv.fs_open(path, 'r', 438, function(err, fd)
    if err then return cb(nil) end
    uv.fs_fstat(fd, function(_, stat)
      uv.fs_read(fd, stat and stat.size or 0, 0, function(_, data)
        uv.fs_close(fd)
        cb(data)
      end)
    end)
  end)
end

--- `flags` 'w' replaces, 'a' appends. Errors are reported on the main loop.
local function writeAsync(path, data, flags)
  uv.fs_open(path, flags, 420, function(err, fd)
    if err then
      return vim.schedule(function()
        vim.notify('Todoist archive: cannot write ' .. path .. ': ' .. err, vim.log.levels.WARN)
      end)
    end
    uv.fs_write(fd, data, -1, function() uv.fs_close(fd) end)
  end)
end

--- Replace `path` with `data` only if it differs from what is there.
local function writeIfChanged(path, data)
  readAsync(path, function(old)
    if old ~= data then writeAsync(path, data, 'w') end
  end)
end

--- Append one line per entry to history.md, all with the same time.
local function logEntries(dir, entries)
  if not dir or #entries == 0 then return end
  local stamp = os.date('%Y-%m-%d %H:%M:%S')
  local out = {}
  for _, e in ipairs(entries) do table.insert(out, ('- %s · %s\n'):format(stamp, e)) end
  writeAsync(dir .. '/history.md', table.concat(out), 'a')
end

function archive.log(entries)
  logEntries(archiveDir(), entries)
end

--- One record per task, as a JSON array sorted by id: arrays keep their order,
--- so the same list always encodes to the same text (object key order does
--- not), and an unchanged list is recognised as such.
local function records(tasks, project_names)
  local list = {}
  for _, t in ipairs(tasks) do
    table.insert(list, { t.id, oneLine(t.content), dueText(t), tonumber(t.priority) or 1,
      project_names[t.project_id] or t.project_id or '' })
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  return list
end

--- What changed between two record lists, as history entries.
local function externalChanges(old, new)
  local before, after, entries = {}, {}, {}
  for _, r in ipairs(old) do before[r[1]] = r end
  for _, r in ipairs(new) do after[r[1]] = r end
  for id, r in pairs(after) do
    local o = before[id]
    if not o then
      table.insert(entries, ('added elsewhere · %s (%s)'):format(r[2], r[5]))
    else
      local diffs = {}
      if o[2] ~= r[2] then table.insert(diffs, ('text: "%s" → "%s"'):format(o[2], r[2])) end
      if o[3] ~= r[3] then table.insert(diffs, ('due: %s → %s'):format(o[3] ~= '' and o[3] or 'none', r[3] ~= '' and r[3] or 'none')) end
      if o[4] ~= r[4] then table.insert(diffs, ('priority: p%d → p%d'):format(5 - o[4], 5 - r[4])) end
      if o[5] ~= r[5] then table.insert(diffs, ('project: %s → %s'):format(o[5], r[5])) end
      if #diffs > 0 then table.insert(entries, ('changed elsewhere · %s · %s'):format(r[2], table.concat(diffs, '; '))) end
    end
  end
  for id, o in pairs(before) do
    if not after[id] then table.insert(entries, ('gone elsewhere (completed or deleted) · %s'):format(o[2])) end
  end
  table.sort(entries)
  return entries
end

--- Archive the full task list: tasks.md and tasks.json when they changed, and
--- history lines for anything that changed outside Neovim since last time.
--- Only called with the unfiltered list; a filtered view is not the archive.
function archive.snapshot(tasks, projects)
  local dir = archiveDir()
  if not dir then return end

  local names, order = {}, {}
  for _, p in ipairs(projects) do
    names[p.id] = p.name
    table.insert(order, p.id)
  end

  -- tasks.md, grouped and nested like the buffer, local states included.
  local sorted = vim.deepcopy(tasks)
  sortTasks(sorted)
  local shown, children, top = {}, {}, {}
  for _, t in ipairs(sorted) do shown[t.id] = true end
  for _, t in ipairs(sorted) do
    if t.parent_id and shown[t.parent_id] then
      children[t.parent_id] = children[t.parent_id] or {}
      table.insert(children[t.parent_id], t)
    else
      top[t.project_id] = top[t.project_id] or {}
      table.insert(top[t.project_id], t)
    end
  end
  local marks = readStates()
  local md = { '# Todoist' }
  local function emit(t, depth)
    table.insert(md, (taskLine(t, depth, marks[t.id]):gsub('%s*‹[%w_%-]+›%s*$', '')))
    for _, c in ipairs(children[t.id] or {}) do emit(c, depth + 1) end
  end
  for pid in pairs(top) do
    if not names[pid] then table.insert(order, pid) end
  end
  for _, pid in ipairs(order) do
    if top[pid] then
      vim.list_extend(md, { '', '## ' .. (names[pid] or pid) })
      for _, t in ipairs(top[pid]) do emit(t, 0) end
    end
  end
  local md_text = table.concat(md, '\n') .. '\n'

  local new = records(tasks, names)
  local json_text = vim.json.encode(new) .. '\n'
  -- After a save the list differs from tasks.json by our own changes, which
  -- history.md already has; comparing now would log them again as external.
  local skip = archive.skip_external
  archive.skip_external = false

  writeIfChanged(dir .. '/tasks.md', md_text)
  readAsync(dir .. '/tasks.json', function(old_text)
    if old_text == json_text then return end
    local ok, old = pcall(vim.json.decode, old_text or '')
    local entries
    if not old_text or not ok or type(old) ~= 'table' then
      entries = { ('archive started · %d tasks'):format(#new) }
    elseif not skip then
      entries = externalChanges(old, new)
    end
    writeAsync(dir .. '/tasks.json', json_text, 'w')
    if entries then logEntries(dir, entries) end
  end)
end

--- Build the buffer: one ## section per project (in Todoist's order), tasks
--- nested under their parent. A subtask whose parent is not in this view
--- (filtered out) is shown at the top level.
local function render(tasks, projects)
  state.projects = { by_name = {}, by_id = {}, inbox = nil, order = {} }
  for _, p in ipairs(projects) do
    state.projects.by_id[p.id] = p.name
    if not state.projects.by_name[p.name] then state.projects.by_name[p.name] = p.id end
    if p.inbox_project or p.is_inbox_project then state.projects.inbox = p.id end
    table.insert(state.projects.order, p.id)
  end
  -- Lines above the first heading go to the Inbox, which Todoist lists first.
  state.projects.inbox = state.projects.inbox or state.projects.order[1]

  sortTasks(tasks)
  local shown = {}
  for _, t in ipairs(tasks) do shown[t.id] = true end

  local children, top = {}, {}
  for _, t in ipairs(tasks) do
    if t.parent_id and shown[t.parent_id] then
      children[t.parent_id] = children[t.parent_id] or {}
      table.insert(children[t.parent_id], t)
    else
      top[t.project_id] = top[t.project_id] or {}
      table.insert(top[t.project_id], t)
    end
  end

  local lines = { '# Todoist' .. (state.filter and (' — ' .. state.filter) or '') }
  state.snapshot = {}

  local marks = readStates()
  local function emit(t, depth, shown_parent)
    table.insert(lines, taskLine(t, depth, marks[t.id]))
    state.snapshot[t.id] = {
      content = oneLine(t.content), due = dueText(t), priority = tonumber(t.priority) or 1,
      project_id = t.project_id, parent_id = shown_parent, checked = t.checked and true or false,
    }
    for _, c in ipairs(children[t.id] or {}) do emit(c, depth + 1, t.id) end
  end

  -- Projects Todoist knows first, in its order; then any the list lacked.
  local order = vim.deepcopy(state.projects.order)
  for pid in pairs(top) do
    if not state.projects.by_id[pid] then table.insert(order, pid) end
  end
  for _, pid in ipairs(order) do
    if top[pid] then
      vim.list_extend(lines, { '', '## ' .. (state.projects.by_id[pid] or pid) })
      for _, t in ipairs(top[pid]) do emit(t, 0, nil) end
    end
  end
  -- Nothing to show: list every project as an empty section, so there is a
  -- heading to type new tasks under. (Not a line of prose: any text line
  -- would now be read as a task.)
  if #tasks == 0 then
    for _, pid in ipairs(state.projects.order) do
      vim.list_extend(lines, { '', '## ' .. state.projects.by_id[pid] })
    end
  end

  setLines(lines)
  if not state.filter then archive.snapshot(tasks, projects) end
  vim.api.nvim_buf_clear_namespace(state.buf, hint_ns, 0, -1)
  vim.api.nvim_buf_set_extmark(state.buf, hint_ns, 0, 0, {
    virt_lines = { { { ':w apply · <CR>/x toggle · r reload · q close · indent = subtask · due:…  p1-p3', 'Comment' } } },
  })
end

--- Tasks for `filter` plus the project list, as cb(err, tasks, projects).
local function fetch(filter, cb)
  local path = filter and ('/tasks/filter?query=' .. urlencode(filter)) or '/tasks'
  getAll(path, function(err, tasks)
    if err then return cb(err) end
    getAll('/projects', function(perr, projects)
      if perr then vim.notify(perr, vim.log.levels.WARN) end
      cb(nil, tasks, projects or {})
    end)
  end)
end

-- Tasks fetched in the background at startup, by filter key ('' = all), so
-- the first :Todoist draws at once instead of waiting on the network.
local prefetched = {}

--- Fetch from Todoist and redraw the buffer. Only runs on the first open of a
--- filter, after :w, and on r -- reopening the list reuses what is there.
--- `on_done(tasks)` runs after a successful redraw.
function M.reload(on_done)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  setLines({ '# Todoist', '', 'Loading…' })
  local key = state.filter or ''

  fetch(state.filter, function(err, tasks, projects)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    if err then
      state.loaded = nil
      setLines({ '# Todoist', '', 'Error: ' .. err })
      return vim.notify(err, vim.log.levels.ERROR)
    end
    render(tasks, projects)
    state.loaded = key
    if type(on_done) == 'function' then on_done(tasks) end
  end)
end

-- -----------------------------------------------------------------------------
--  Saving: buffer -> list of API calls
-- -----------------------------------------------------------------------------

--- Parse the whole buffer into task items with their project and parent.
--- Returns items, or nil and an error message naming the line.
local function collect(buf)
  local items, seen = {}, {}
  local project = state.projects.inbox
  local stack = {} -- open ancestors: { indent, item }

  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local heading = line:match('^##%s+(.-)%s*$')
    if heading then
      project = state.projects.by_name[heading]
      if not project then
        return nil, ('line %d: no Todoist project called "%s"'):format(lnum, heading)
      end
      stack = {}
    else
      local item = parseLine(line)
      if item then
        if not project then
          return nil, ('line %d: put the task under a ## Project heading'):format(lnum)
        end
        item.lnum, item.project_id = lnum, project
        while #stack > 0 and stack[#stack].indent >= item.indent do table.remove(stack) end
        item.parent = stack[#stack] and stack[#stack].item or nil
        table.insert(stack, { indent = item.indent, item = item })
        -- The same id twice means a copied line: the copy is a new task.
        if item.id and (seen[item.id] or not state.snapshot[item.id]) then item.id = nil end
        if item.id then seen[item.id] = true end
        table.insert(items, item)
      end
    end
  end
  return items, nil, seen
end

--- Work out the API calls, in an order that respects dependencies: creates
--- first and top-down (a new subtask needs its new parent's id), then edits,
--- moves, completions, and deletes last.
local function plan(items, seen)
  local ops = { create = {}, update = {}, move = {}, close = {}, reopen = {}, delete = {} }

  for _, item in ipairs(items) do
    local s = item.id and state.snapshot[item.id]
    if not s then
      table.insert(ops.create, item)
    else
      local changes = {}
      if item.content ~= s.content then changes.content = item.content end
      if item.due ~= s.due then changes.due_string = item.due ~= '' and item.due or 'no date' end
      if item.priority ~= s.priority then changes.priority = item.priority end
      if next(changes) then table.insert(ops.update, { item = item, body = changes }) end

      -- Compared with the parent as shown, so a subtask whose real parent is
      -- filtered out of this view is not "moved" to the top level.
      local parent_changed = (item.parent ~= nil) ~= (s.parent_id ~= nil)
        or (item.parent and item.parent.id ~= s.parent_id)
      if parent_changed or (not item.parent and item.project_id ~= s.project_id) then
        table.insert(ops.move, item)
      end

      if item.checked and not s.checked then table.insert(ops.close, item) end
      if not item.checked and s.checked then table.insert(ops.reopen, item) end
    end
  end

  -- Deleting a parent deletes its subtasks, so only the top of each deleted
  -- branch is sent; a separate call for a child would fail with 404.
  for id, s in pairs(state.snapshot) do
    if not seen[id] and not (s.parent_id and not seen[s.parent_id]) then
      table.insert(ops.delete, { id = id, content = s.content })
    end
  end
  return ops
end

local function summary(ops)
  local parts = {}
  for _, key in ipairs({ 'create', 'update', 'move', 'close', 'reopen', 'delete' }) do
    if #ops[key] > 0 then
      local label = ({ close = 'complete' })[key] or key
      table.insert(parts, ('%s %d'):format(label, #ops[key]))
    end
  end
  return parts
end

--- Run the calls one after another (each may need an id the previous one
--- returned), then reload. Failures are collected and reported together.
--- `log` collects a history entry for every call that succeeded.
local function apply(ops, done, log)
  local calls, errors = {}, {}
  local project_name = function(id) return state.projects.by_id[id] or id end
  local function add(fn) table.insert(calls, fn) end

  for _, item in ipairs(ops.create) do
    add(function(next_call)
      local body = { content = item.content, project_id = item.project_id, priority = item.priority }
      if item.parent then
        if not item.parent.id then
          table.insert(errors, ('line %d: parent was not created'):format(item.lnum))
          return next_call()
        end
        body.parent_id = item.parent.id
      end
      if item.due ~= '' then body.due_string = item.due end
      request('POST', '/tasks', function(err, task)
        if err then
          table.insert(errors, ('create "%s": %s'):format(item.content, err))
        else
          item.id = task and task.id
          local extra = (item.due ~= '' and (' due:' .. item.due) or '') .. (item.priority > 1 and (' p' .. (5 - item.priority)) or '')
          table.insert(log, ('created · %s (%s)%s'):format(item.content, project_name(item.project_id), extra))
          if item.checked and item.id then
            table.insert(log, 'completed · ' .. item.content)
            return request('POST', '/tasks/' .. item.id .. '/close', function() next_call() end)
          end
        end
        next_call()
      end, body)
    end)
  end
  for _, u in ipairs(ops.update) do
    add(function(next_call)
      local was = state.snapshot[u.item.id] or {}
      request('POST', '/tasks/' .. u.item.id, function(err)
        if err then
          table.insert(errors, ('update "%s": %s'):format(u.item.content, err))
        else
          local diffs = {}
          if u.body.content then table.insert(diffs, ('text: "%s" → "%s"'):format(was.content or '?', u.body.content)) end
          if u.body.due_string then
            table.insert(diffs, ('due: %s → %s'):format((was.due or '') ~= '' and was.due or 'none', u.item.due ~= '' and u.item.due or 'none'))
          end
          if u.body.priority then table.insert(diffs, ('priority: p%d → p%d'):format(5 - (was.priority or 1), 5 - u.body.priority)) end
          table.insert(log, ('edited · %s · %s'):format(u.item.content, table.concat(diffs, '; ')))
        end
        next_call()
      end, u.body)
    end)
  end
  for _, item in ipairs(ops.move) do
    add(function(next_call)
      local body = item.parent and { parent_id = item.parent.id } or { project_id = item.project_id }
      request('POST', '/tasks/' .. item.id .. '/move', function(err)
        if err then
          table.insert(errors, ('move "%s": %s'):format(item.content, err))
        else
          table.insert(log, item.parent and ('moved · %s → under "%s"'):format(item.content, item.parent.content)
            or ('moved · %s → %s'):format(item.content, project_name(item.project_id)))
        end
        next_call()
      end, body)
    end)
  end
  for key, action in pairs({ close = 'close', reopen = 'reopen' }) do
    for _, item in ipairs(ops[key]) do
      add(function(next_call)
        request('POST', '/tasks/' .. item.id .. '/' .. action, function(err)
          if err then
            table.insert(errors, ('%s "%s": %s'):format(action, item.content, err))
          else
            table.insert(log, (action == 'close' and 'completed · ' or 'reopened · ') .. item.content)
          end
          next_call()
        end)
      end)
    end
  end
  for _, d in ipairs(ops.delete) do
    add(function(next_call)
      request('DELETE', '/tasks/' .. d.id, function(err)
        if err then
          table.insert(errors, ('delete "%s": %s'):format(d.content, err))
        else
          table.insert(log, 'deleted · ' .. d.content)
        end
        next_call()
      end)
    end)
  end

  local i = 0
  local function next_call()
    i = i + 1
    if calls[i] then return calls[i](next_call) end
    done(errors)
  end
  next_call()
end

--- :w on the task buffer.
function M.save()
  local buf = state.buf
  if state.saving then return vim.notify('Still saving the previous changes', vim.log.levels.WARN) end

  local items, err, seen = collect(buf)
  if not items then return vim.notify('Todoist: ' .. err, vim.log.levels.ERROR) end

  local ops = plan(items, seen)
  local parts = summary(ops)
  if #parts == 0 then
    -- Nothing for Todoist, but a [~] / [!] / [>] / [-] may have changed.
    vim.bo[buf].modified = false
    local changed, entries = saveStates(items)
    archive.log(entries)
    return vim.notify(changed and 'Todoist: checkbox states saved (kept locally)' or 'Todoist: no changes')
  end

  -- vim.g.pure_todoist_confirm: 'all' (default) asks before every save,
  -- 'delete' only when tasks would be deleted, 'never' does not ask.
  local mode = vim.g.pure_todoist_confirm or 'all'
  if mode == 'all' or (mode == 'delete' and #ops.delete > 0) then
    -- Deletes are named: they are the one change that cannot be undone here.
    local question = 'Apply to Todoist: ' .. table.concat(parts, ', ') .. '?'
    if #ops.delete > 0 then
      local names = {}
      for _, d in ipairs(ops.delete) do table.insert(names, '  - ' .. d.content) end
      question = question .. '\n\nDeleting:\n' .. table.concat(names, '\n')
    end
    -- What <CR> answers: Yes for creates and edits, No when something would
    -- be deleted, so a reflexive Enter never deletes a task. (It used to be
    -- No always, and a save confirmed with Enter silently did nothing.)
    local default = #ops.delete > 0 and 2 or 1
    if vim.fn.confirm(question, '&Yes\n&No', default) ~= 1 then
      return vim.notify('Todoist: nothing sent; the edits are still in the buffer')
    end
  end

  state.saving = true
  vim.notify('Todoist: saving…')
  local log = {}
  apply(ops, function(errors)
    state.saving = false
    -- After apply, so new tasks have their ids; before the reload draws them.
    local deleted_ids = {}
    for _, d in ipairs(ops.delete) do table.insert(deleted_ids, d.id) end
    local _, mark_entries = saveStates(items, deleted_ids)
    vim.list_extend(log, mark_entries)
    archive.log(log)
    -- The reload below brings our own changes back; they are logged already.
    archive.skip_external = true
    if #errors > 0 then
      vim.notify('Todoist: some changes failed:\n' .. table.concat(errors, '\n'), vim.log.levels.ERROR)
    else
      local msg = 'Todoist: ' .. table.concat(parts, ', ')
      for _, item in ipairs(ops.create) do
        if item.id then msg = msg .. '\n  + ' .. item.content end
      end
      vim.notify(msg)
    end
    M.reload(function(tasks)
      -- A task created in a filtered view (say, with no date under "today")
      -- exists in Todoist but drops out on reload; say so, or it looks lost.
      local listed = {}
      for _, t in ipairs(tasks) do listed[t.id] = true end
      local hidden = {}
      for _, item in ipairs(ops.create) do
        if item.id and not listed[item.id] then table.insert(hidden, '  ' .. item.content) end
      end
      if #hidden > 0 then
        vim.notify(('Created in Todoist but not listed, as it does not match "%s":\n%s')
          :format(state.filter or '', table.concat(hidden, '\n')), vim.log.levels.WARN)
      end
    end)
    M.refreshBlocks()
  end, log)
end

--- Run `fn` now, or after confirming that unsaved edits may be dropped.
local function unlessModified(what, fn)
  return function()
    if vim.bo[state.buf].modified and vim.fn.confirm(
          'Discard unsaved Todoist changes and ' .. what .. '?', '&Discard\n&Cancel', 2) ~= 1 then
      return
    end
    fn()
  end
end

function M.open(filter)
  filter = (filter and filter ~= '') and filter or nil
  local key = filter or ''

  -- Switching filter redraws the buffer; unsaved edits would be lost.
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.loaded ~= key
      and vim.bo[state.buf].modified
      and vim.fn.confirm('Discard unsaved Todoist changes and open "' .. (filter or 'all') .. '"?',
        '&Discard\n&Cancel', 2) ~= 1 then
    return
  end
  state.filter = filter

  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    local buf = vim.api.nvim_create_buf(false, false)
    state.buf = buf
    -- acwrite: :w runs BufWriteCmd below instead of writing a file.
    vim.bo[buf].buftype = 'acwrite'
    vim.bo[buf].bufhidden = 'hide'
    vim.bo[buf].swapfile = false
    pcall(vim.api.nvim_buf_set_name, buf, 'todoist://tasks')
    -- mdview only draws in normal file buffers; this one opts in explicitly.
    vim.b[buf].pure_mdview = true
    vim.bo[buf].filetype = 'markdown'
    -- render-md.lua sets a textwidth for markdown, which would wrap long task
    -- lines into two while typing -- and the second half would be a new task.
    vim.bo[buf].textwidth = 0

    vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = M.save })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      buffer = buf,
      callback = function() decorate(buf) end,
    })

    local map = function(lhs, fn, desc) vim.keymap.set('n', lhs, fn, { buffer = buf, desc = desc }) end
    local close = unlessModified('close', function()
      -- Discarded edits are still in the (hidden) buffer: draw it afresh
      -- next time rather than showing them again.
      if vim.bo[buf].modified then state.loaded = nil end
      vim.bo[buf].modified = false
      if #vim.api.nvim_list_wins() > 1 then vim.cmd('close') else vim.cmd('bprevious') end
    end)
    -- The same toggle as <leader>tx in notes; the change is sent on :w.
    map('<CR>', require('configs.functions').toggleCheckbox, 'Toggle task checkbox')
    -- In this buffer only, x ticks the box instead of deleting a character.
    map('x', require('configs.functions').toggleCheckbox, 'Toggle task checkbox')
    -- Obsidian's states, as in notes; only [x] reaches Todoist, the others
    -- are kept locally (see states_file).
    map('<leader>x', require('configs.functions').cycleCheckbox, 'Cycle checkbox state')
    map('r', unlessModified('reload', M.reload), 'Reload tasks')
    map('q', close, 'Close Todoist')
    map('<Esc>', close, 'Close Todoist')
  end

  local win = vim.fn.bufwinid(state.buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd('botright split')
    vim.api.nvim_win_set_buf(0, state.buf)
  end
  -- Window options: render-md.lua turns spell on for markdown (task names are
  -- not prose worth underlining), and the ids need conceal to stay hidden.
  vim.wo.spell = false
  vim.wo.wrap = false
  vim.wo.conceallevel = 2
  vim.wo.concealcursor = 'nc'

  -- Same filter as what the buffer holds: just show it, no network.
  if state.loaded == key then return end
  local ready = prefetched[key]
  prefetched[key] = nil
  if ready then
    render(ready.tasks, ready.projects)
    state.loaded = key
  else
    M.reload()
  end
end

-- -----------------------------------------------------------------------------
--  Blocks in notes
-- -----------------------------------------------------------------------------
--  A fenced block in any markdown file, in the syntax of Obsidian's Todoist
--  plugin, so the same note works in both:
--
--    ```todoist
--    name: Today
--    filter: "today | overdue"
--    ```
--
--  The tasks are drawn under the block as virtual lines; the file keeps only
--  the query. They load when the note is shown and are cached for a few
--  minutes; :TodoistRefresh reloads them. :Todoist with the cursor inside a
--  block opens that filter as the interactive list, to complete tasks.
--  The plugin's older JSON form ({"name": ..., "filter": ...}) is read too.

local block_ns = vim.api.nvim_create_namespace('pure_todoist_block')
local cache_ttl = 5 * 60 -- seconds
local cache = {}         -- filter ('' for all) -> { time, tasks?, err?, loading? }
local project_cache = { time = 0, names = {} }

--- `key: value` lines, values optionally quoted. Only name and filter are
--- used; the Obsidian plugin's other keys (sorting, groupBy, ...) are ignored.
local function parseBlockBody(lines)
  local text = vim.trim(table.concat(lines, '\n'))
  if text:sub(1, 1) == '{' then
    -- luanil: a JSON null must become nil, not vim.NIL (which is truthy).
    local ok, obj = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
    if ok and type(obj) == 'table' then
      local str = function(v) return type(v) == 'string' and v or nil end
      return { name = str(obj.name), filter = str(obj.filter) }
    end
  end
  local conf = {}
  for _, line in ipairs(lines) do
    local key, value = line:match('^%s*([%w_]+)%s*:%s*(.-)%s*$')
    if key then
      conf[key] = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
    end
  end
  return { name = conf.name, filter = conf.filter }
end

--- Every ```todoist block in `buf`: { first, last (0-based fence rows), name, filter }.
local function findBlocks(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local blocks, i = {}, 1
  while i <= #lines do
    if lines[i]:match('^%s*```%s*todoist%s*$') then
      local j = i + 1
      while j <= #lines and not lines[j]:match('^%s*```%s*$') do j = j + 1 end
      local conf = parseBlockBody(vim.list_slice(lines, i + 1, j - 1))
      conf.first, conf.last = i - 1, math.min(j, #lines) - 1
      table.insert(blocks, conf)
      i = j + 1
    else
      i = i + 1
    end
  end
  return blocks
end

local function blockAt(buf, row)
  for _, b in ipairs(findBlocks(buf)) do
    if row >= b.first and row <= b.last then return b end
  end
end

--- Load `filter` into the cache unless it is fresh or already loading, then
--- call `on_done` (used to redraw).
local function load(filter, on_done)
  local key = filter or ''
  local entry = cache[key]
  if entry and (entry.loading or os.time() - entry.time < cache_ttl) then return end
  cache[key] = { time = os.time(), loading = true, tasks = entry and entry.tasks }

  local path = filter and ('/tasks/filter?query=' .. urlencode(filter)) or '/tasks'
  getAll(path, function(err, tasks)
    local function done()
      cache[key] = { time = os.time(), tasks = tasks, err = err }
      on_done()
    end
    if err or os.time() - project_cache.time < cache_ttl then return done() end
    getAll('/projects', function(_, projects)
      project_cache = { time = os.time(), names = {} }
      for _, p in ipairs(projects or {}) do project_cache.names[p.id] = p.name end
      done()
    end)
  end)
end

local priority_hl = { [4] = 'PureTodoistP1', [3] = 'PureTodoistP2', [2] = 'PureTodoistP3' }

--- The virtual lines for one block: a header, one line per task, a footer.
local function blockLines(block, entry, width)
  local title = block.name or block.filter or 'Todoist'
  local lines = {}
  local function add(chunks) table.insert(lines, chunks) end

  if not entry or (entry.loading and not entry.tasks) then
    add({ { '  󰔟 ' .. title .. ' · loading…', 'Comment' } })
    return lines
  end
  if entry.err then
    add({ { '  ' .. title .. ': ' .. entry.err, 'DiagnosticWarn' } })
    return lines
  end

  local tasks = vim.deepcopy(entry.tasks or {})
  sortTasks(tasks)
  add({ { '╭─ ', 'Comment' }, { title, 'Title' }, { (' (%d)'):format(#tasks), 'Comment' } })
  if #tasks == 0 then
    add({ { '│ ', 'Comment' }, { 'Nothing to do.', 'Comment' } })
  end

  -- Task text padded to a common width so project and due line up.
  local name_width = 10
  for _, t in ipairs(tasks) do
    name_width = math.max(name_width, vim.fn.strdisplaywidth((t.parent_id and '↳ ' or '') .. t.content))
  end
  name_width = math.min(name_width, math.max(width - 40, 20))

  for _, t in ipairs(tasks) do
    local text = (t.parent_id and '↳ ' or '') .. t.content:gsub('\n', ' ')
    if vim.fn.strdisplaywidth(text) > name_width then
      text = vim.fn.strcharpart(text, 0, name_width - 1) .. '…'
    end
    text = text .. string.rep(' ', name_width - vim.fn.strdisplaywidth(text))
    local chunks = {
      { '│ ', 'Comment' },
      { t.checked and '󰄲 ' or '󰄱 ', t.checked and 'PureMdTaskDone' or 'PureMdTaskTodo' },
      { text, t.checked and 'Comment' or 'Normal' },
    }
    local project = project_cache.names[t.project_id]
    if project then table.insert(chunks, { '  ' .. project, 'Comment' }) end
    if t.due then table.insert(chunks, { '  ' .. (t.due.string or t.due.date), 'PureTodoistDue' }) end
    local p = tonumber(t.priority) or 1
    if p > 1 then table.insert(chunks, { '  ' .. priorityLabel(p), priority_hl[p] }) end
    add(chunks)
  end
  add({ { '╰─ ', 'Comment' }, { ':Todoist in the block to complete tasks', 'Comment' } })
  return lines
end

--- Draw every block of `buf` from the cache, starting loads as needed.
function M.renderBlocks(buf)
  buf = (buf and buf ~= 0) and buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, block_ns, 0, -1)

  local blocks = findBlocks(buf)
  if #blocks == 0 then return end

  local win = vim.fn.bufwinid(buf)
  local width = win ~= -1 and vim.api.nvim_win_get_width(win) or 80

  for _, block in ipairs(blocks) do
    if not token() then
      cache[block.filter or ''] = { time = 0, err = 'no token, run :TodoistToken' }
    else
      load(block.filter, function() M.renderBlocks(buf) end)
    end
    -- Hung under the last line of the query, not the closing fence: Neovim
    -- conceals the fence lines of markdown code blocks, and virtual lines
    -- attached to a concealed line are hidden with it.
    local row = block.last > block.first + 1 and block.last - 1 or block.last
    vim.api.nvim_buf_set_extmark(buf, block_ns, row, 0, {
      virt_lines = blockLines(block, cache[block.filter or ''], width),
    })
  end
end

--- Reload every block in every loaded markdown buffer.
function M.refreshBlocks()
  cache = {}
  project_cache.time = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'markdown' then
      M.renderBlocks(buf)
    end
  end
end

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'InsertLeave', 'TextChanged' }, {
  group = vim.api.nvim_create_augroup('PureTodoistBlocks', { clear = true }),
  pattern = { '*.md', '*.markdown' },
  callback = function(args) M.renderBlocks(args.buf) end,
})

vim.api.nvim_create_user_command('TodoistRefresh', M.refreshBlocks, {
  desc = 'Reload the ```todoist blocks in open notes',
})

-- -----------------------------------------------------------------------------
--  Token setup
-- -----------------------------------------------------------------------------

--- Ask for the token with hidden input, save it to `token_file` and check it
--- against the API. Also turns the startup question back on.
function M.setToken()
  -- inputsecret shows '*' while typing and keeps the answer out of the
  -- command-line history, unlike input() or a :let.
  local ok, input = pcall(vim.fn.inputsecret, 'Todoist API token (empty to cancel): ')
  input = ok and vim.trim(input or '') or ''
  if input == '' then
    return vim.notify('Todoist token not changed')
  end
  if input:find('%s') then
    return vim.notify('That does not look like a token (it has spaces); nothing saved', vim.log.levels.WARN)
  end

  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  local f, err = io.open(token_file, 'w')
  if not f then
    return vim.notify('Could not write ' .. token_file .. ': ' .. tostring(err), vim.log.levels.ERROR)
  end
  f:write(input, '\n')
  f:close()
  -- Owner read/write only (0600). Windows ignores the mode; its per-user
  -- AppData folder already keeps the file private.
  pcall(vim.uv.fs_chmod, token_file, tonumber('600', 8))
  os.remove(no_prompt_file)

  if vim.env.TODOIST_API_TOKEN and vim.env.TODOIST_API_TOKEN ~= '' then
    vim.notify('Saved, but TODOIST_API_TOKEN is set and takes precedence over the file', vim.log.levels.WARN)
  end

  -- One cheap request to tell a typo apart from a working token now, rather
  -- than on the first :Todoist.
  vim.notify('Todoist token saved, checking it…')
  request('GET', '/projects?limit=1', function(req_err)
    if req_err then
      vim.notify('Todoist rejected the token: ' .. req_err .. '\nRun :TodoistToken to try again.',
        vim.log.levels.WARN)
    else
      vim.notify('Todoist token works')
      M.refreshBlocks() -- open notes were showing "no token"
    end
  end)
end

--- Startup question, only when there is no token, the user did not opt out,
--- and a real UI is attached (never in headless runs or scripts).
local function askOnStartup()
  if token() or vim.uv.fs_stat(no_prompt_file) or #vim.api.nvim_list_uis() == 0 then return end

  -- confirm(), not vim.ui.select: here vim.ui.select is the fzf picker from
  -- fuzzyUtils, and the token prompt opened from its callback was cancelled at
  -- once while the picker's terminal closed -- the token then went into the
  -- buffer as typed text. confirm() is a plain command-line question.
  local choice = vim.fn.confirm('No Todoist API token found (needed by :Todoist).',
    "&Enter it now\n&Ask me next time\n&Don't ask again", 2)
  if choice == 1 then
    M.setToken()
  elseif choice == 3 then
    local f = io.open(no_prompt_file, 'w')
    if f then f:close() end
    vim.notify("Won't ask again. Run :TodoistToken whenever you want to set it.")
  end
end

vim.api.nvim_create_autocmd('VimEnter', {
  group = vim.api.nvim_create_augroup('PureTodoist', { clear = true }),
  once = true,
  -- Scheduled so the dashboard and the first screen are drawn before the
  -- question takes the command line.
  callback = function()
    vim.schedule(askOnStartup)
    -- Warm the default list in the background, a moment after startup so it
    -- never competes with drawing the first screen.
    vim.defer_fn(function()
      if not token() or #vim.api.nvim_list_uis() == 0 or state.loaded then return end
      fetch(nil, function(err, tasks, projects)
        if err then return end
        -- Archive in the background too, so it stays current even on days
        -- the list is never opened.
        archive.snapshot(tasks, projects)
        if not state.loaded then prefetched[''] = { tasks = tasks, projects = projects } end
      end)
    end, 1000)
  end,
})

vim.api.nvim_create_user_command('TodoistToken', M.setToken, {
  desc = 'Set the Todoist API token (hidden input)',
})

vim.api.nvim_create_user_command('Todoist', function(opts)
  -- Without a filter, inside a ```todoist block, open that block's filter.
  if opts.args == '' then
    local block = blockAt(vim.api.nvim_get_current_buf(), vim.fn.line('.') - 1)
    if block then return M.open(block.filter) end
  end
  M.open(opts.args)
end, {
  nargs = '*',
  desc = 'Todoist tasks as a checkbox table (optional filter, e.g. :Todoist today)',
})

return M
