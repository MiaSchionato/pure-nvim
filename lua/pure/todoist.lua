-- =============================================================================
--  Todoist
-- =============================================================================
--  Lists Todoist tasks in a markdown table with checkboxes, and completes them
--  from Neovim. Talks to the Todoist API v1 through curl.
--
--    :Todoist                 all active tasks
--    :Todoist today | overdue any Todoist filter query (as in the app)
--
--  In the task buffer:
--    <CR> / x   complete the task on the cursor line (again to reopen it)
--    r          reload
--    q          close
--
--  The table is plain markdown, so pure/mdview.lua draws the borders and the
--  checkbox icons.
--
--  Token (Todoist > Settings > Integrations > Developer), never kept in this
--  repository. Either of:
--    - a file holding just the token: stdpath('data')/todoist_token
--      (~/.local/share/nvim/todoist_token, or %LOCALAPPDATA%\nvim-data\ on
--      Windows). :TodoistToken writes it for you.
--    - the TODOIST_API_TOKEN environment variable
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
local function request(method, path, cb)
  local tok = token()
  if not tok then
    return cb('No Todoist token: run :TodoistToken to set it')
  end

  local base = vim.g.pure_todoist_url or api
  local cmd = { 'curl', '-sS', '-X', method, '-H', '@-', '-w', '\n%{http_code}', base .. path }
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
--  Table
-- -----------------------------------------------------------------------------

--- Text safe inside a table cell. A '|' would end the cell; escaped as '\|'
--- it would still show its backslash, so it becomes the look-alike '¦'.
local function cell(s)
  return (tostring(s or ''):gsub('\n', ' '):gsub('|', '¦'))
end

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

--- Pad every column to its widest cell, so the raw text lines up as well.
local function formatTable(header, rows)
  local widths = {}
  for _, row in ipairs(vim.list_extend({ header }, rows)) do
    for i, c in ipairs(row) do
      widths[i] = math.max(widths[i] or 3, vim.fn.strdisplaywidth(c))
    end
  end
  local function line(row)
    local parts = {}
    for i, c in ipairs(row) do
      table.insert(parts, c .. string.rep(' ', widths[i] - vim.fn.strdisplaywidth(c)))
    end
    return '| ' .. table.concat(parts, ' | ') .. ' |'
  end
  local out = { line(header) }
  local rule = {}
  for i = 1, #header do rule[i] = string.rep('-', widths[i]) end
  table.insert(out, '|-' .. table.concat(rule, '-|-') .. '-|')
  for _, row in ipairs(rows) do table.insert(out, line(row)) end
  return out
end

-- -----------------------------------------------------------------------------
--  Buffer
-- -----------------------------------------------------------------------------

local state = { buf = nil, filter = nil, rows = {} } -- rows: line number -> task

local function setLines(lines)
  local buf = state.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local function render(tasks, projects)
  local project_name = {}
  for _, p in ipairs(projects) do project_name[p.id] = p.name end

  sortTasks(tasks)

  local title = '# Todoist' .. (state.filter and (' — ' .. state.filter) or '')
  local lines = { title, '', ('%d tasks · updated %s'):format(#tasks, os.date('%H:%M')), '' }

  local rows = {}
  for _, t in ipairs(tasks) do
    table.insert(rows, {
      t.checked and '[x]' or '[ ]',
      cell((t.parent_id and '↳ ' or '') .. t.content),
      cell(project_name[t.project_id] or ''),
      cell(t.due and (t.due.string or t.due.date) or ''),
      priorityLabel(t.priority),
    })
  end

  state.rows = {}
  local first_row = #lines + 3 -- title block, then header and delimiter rows
  for i, t in ipairs(tasks) do state.rows[first_row + i - 1] = t end

  if #tasks == 0 then
    vim.list_extend(lines, { 'Nothing to do.' })
  else
    vim.list_extend(lines, formatTable({ ' ✓ ', 'Task', 'Project', 'Due', 'P' }, rows))
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '<CR>/x complete · r reload · q close'
  setLines(lines)
end

function M.reload()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  setLines({ '# Todoist', '', 'Loading…' })

  local path = state.filter and ('/tasks/filter?query=' .. urlencode(state.filter)) or '/tasks'
  getAll(path, function(err, tasks)
    if err then
      setLines({ '# Todoist', '', 'Error: ' .. err })
      return vim.notify(err, vim.log.levels.ERROR)
    end
    getAll('/projects', function(perr, projects)
      if perr then vim.notify(perr, vim.log.levels.WARN) end
      if vim.api.nvim_buf_is_valid(state.buf) then render(tasks, projects or {}) end
    end)
  end)
end

--- Complete (or reopen) the task on the cursor line. The box flips at once;
--- if the API refuses, it flips back and says why.
function M.toggle()
  local lnum = vim.fn.line('.')
  local task = state.rows[lnum]
  if not task then return end

  local done = not task.checked
  local function mark(checked)
    task.checked = checked
    local line = vim.api.nvim_buf_get_lines(state.buf, lnum - 1, lnum, false)[1]
    local new = line:gsub(checked and '%[ %]' or '%[x%]', checked and '[x]' or '[ ]', 1)
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, lnum - 1, lnum, false, { new })
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].modified = false
  end

  mark(done)
  request('POST', '/tasks/' .. task.id .. (done and '/close' or '/reopen'), function(err)
    if err then
      mark(not done)
      return vim.notify(err, vim.log.levels.ERROR)
    end
    vim.notify((done and 'Completed: ' or 'Reopened: ') .. task.content)
    -- Blocks in open notes may list the same task.
    M.refreshBlocks()
  end)
end

function M.open(filter)
  state.filter = (filter and filter ~= '') and filter or nil

  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = 'nofile'
    vim.bo[state.buf].bufhidden = 'hide'
    vim.bo[state.buf].swapfile = false
    pcall(vim.api.nvim_buf_set_name, state.buf, 'Todoist')
    -- mdview only draws in normal file buffers; this one opts in explicitly.
    vim.b[state.buf].pure_mdview = true
    vim.bo[state.buf].filetype = 'markdown'

    local map = function(lhs, fn, desc) vim.keymap.set('n', lhs, fn, { buffer = state.buf, desc = desc }) end
    map('<CR>', M.toggle, 'Complete / reopen task')
    map('x', M.toggle, 'Complete / reopen task')
    map('r', M.reload, 'Reload tasks')
    map('q', '<cmd>close<cr>', 'Close Todoist')
  end

  local win = vim.fn.bufwinid(state.buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd('botright split')
    vim.api.nvim_win_set_buf(0, state.buf)
  end
  -- Set on the window showing the list: render-md.lua turns spell on for
  -- markdown, and task names are not prose worth underlining.
  vim.wo.spell = false
  vim.wo.wrap = false
  M.reload()
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

local priority_hl = { [4] = 'DiagnosticError', [3] = 'DiagnosticWarn', [2] = 'DiagnosticInfo' }

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
      { t.checked and '󰄲 ' or '󰄱 ', t.checked and 'PureMdChecked' or 'PureMdUnchecked' },
      { text, t.checked and 'Comment' or 'Normal' },
    }
    local project = project_cache.names[t.project_id]
    if project then table.insert(chunks, { '  ' .. project, 'Comment' }) end
    if t.due then table.insert(chunks, { '  ' .. (t.due.string or t.due.date), 'Special' }) end
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
  callback = function() vim.schedule(askOnStartup) end,
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
