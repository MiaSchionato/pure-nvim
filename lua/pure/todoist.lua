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
--    - the TODOIST_API_TOKEN environment variable
--    - a file holding just the token: stdpath('data')/todoist_token
--      (~/.local/share/nvim/todoist_token, or %LOCALAPPDATA%\nvim-data\ on
--      Windows)
-- =============================================================================

local M = {}

local api = 'https://api.todoist.com/api/v1'

-- -----------------------------------------------------------------------------
--  HTTP
-- -----------------------------------------------------------------------------

local function token()
  local env = vim.env.TODOIST_API_TOKEN
  if env and env ~= '' then return env end
  local f = io.open(vim.fn.stdpath('data') .. '/todoist_token', 'r')
  if not f then return nil end
  local t = f:read('*l')
  f:close()
  return t and vim.trim(t) or nil
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
    return cb('No Todoist token: set TODOIST_API_TOKEN or write it to '
      .. vim.fn.stdpath('data') .. '/todoist_token')
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

  table.sort(tasks, function(a, b)
    local da, db = dueSortKey(a), dueSortKey(b)
    if da ~= db then return da < db end
    return (tonumber(a.priority) or 1) > (tonumber(b.priority) or 1)
  end)

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

vim.api.nvim_create_user_command('Todoist', function(opts) M.open(opts.args) end, {
  nargs = '*',
  desc = 'Todoist tasks as a checkbox table (optional filter, e.g. :Todoist today)',
})

return M
