-- =============================================================================
--  Notifications
-- =============================================================================
--  Replaces mini.notify. Takes over vim.notify and shows each message in a
--  floating window in the top-right corner, newest at the bottom. A message
--  stays for a few seconds (longer for warnings and errors), then goes away;
--  all of them are kept in a history.
--
--    :Notifications        open the history in a split
--    require('pure.notify').get_all()   the history as a Lua list
--
--  Colours: PureNotifyNormal / PureNotifyBorder (link to NormalFloat /
--  FloatBorder); warnings and errors use DiagnosticWarn / DiagnosticError.
-- =============================================================================

local M = {}

local levels = vim.log.levels

--- How long a message stays on screen, per level (ms).
local duration = {
  [levels.ERROR] = 8000,
  [levels.WARN]  = 6000,
}
local default_duration = 4000
local max_width_share = 0.382 -- of the editor width, as mini.notify was set up

local level_hl = {
  [levels.ERROR] = 'DiagnosticError',
  [levels.WARN]  = 'DiagnosticWarn',
}

local level_name = {}
for name, value in pairs(levels) do level_name[value] = name end

vim.api.nvim_set_hl(0, 'PureNotifyNormal', { link = 'NormalFloat', default = true })
vim.api.nvim_set_hl(0, 'PureNotifyBorder', { link = 'FloatBorder', default = true })

local history = {} -- every message, oldest first: { id, msg, level, time }
local active = {}  -- the ones on screen now, in the same order
local next_id = 1

local ns = vim.api.nvim_create_namespace('pure_notify')
local buf, win

-- -----------------------------------------------------------------------------
--  Window
-- -----------------------------------------------------------------------------
local function close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
end

--- Rebuild the window from `active`: one block of lines per message.
local function render()
  if #active == 0 then return close() end

  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'pure-notify'
  end

  local lines, spans = {}, {}
  for _, item in ipairs(active) do
    local first = #lines
    for _, line in ipairs(vim.split(item.msg, '\n', { plain = true })) do
      table.insert(lines, line)
    end
    table.insert(spans, { first, #lines, level_hl[item.level] })
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, span in ipairs(spans) do
    if span[3] then
      vim.api.nvim_buf_set_extmark(buf, ns, span[1], 0, { end_row = span[2], hl_group = span[3], hl_eol = true })
    end
  end

  -- Width is the longest line, capped; the height counts wrapped lines, so a
  -- long error is shown whole instead of cut at the window edge.
  local max_width = math.max(math.floor(vim.o.columns * max_width_share), 20)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width, max_width)
  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  height = math.min(height, math.max(vim.o.lines - 4, 1))

  local config = {
    relative = 'editor',
    anchor = 'NE',
    row = vim.o.showtabline == 2 and 1 or 0,
    col = vim.o.columns,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    zindex = 250,
  }

  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, config)
  else
    config.noautocmd = true
    win = vim.api.nvim_open_win(buf, false, config)
    vim.wo[win].wrap = true
    vim.wo[win].winhighlight = 'NormalFloat:PureNotifyNormal,FloatBorder:PureNotifyBorder'
  end
end

local function remove(id)
  for i, item in ipairs(active) do
    if item.id == id then
      table.remove(active, i)
      break
    end
  end
  render()
end

-- -----------------------------------------------------------------------------
--  API
-- -----------------------------------------------------------------------------

--- Drop-in for vim.notify (same arguments; `opts` is accepted and ignored).
function M.notify(msg, level, opts)
  level = level or levels.INFO
  if level == levels.OFF then return end

  local item = { id = next_id, msg = tostring(msg), level = level, time = os.time() }
  next_id = next_id + 1
  table.insert(history, item)

  -- vim.notify may be called from a libuv callback (a job, an LSP handler)
  -- where windows cannot be touched, so the drawing always waits for the main
  -- loop. The history above is updated right away either way.
  vim.schedule(function()
    table.insert(active, item)
    render()
    vim.defer_fn(function() remove(item.id) end, duration[level] or default_duration)
  end)
end

--- Every message since startup, oldest first. Each entry is a copy.
function M.get_all()
  return vim.deepcopy(history)
end

--- Hide everything on screen now (the history is kept).
function M.clear()
  active = {}
  render()
end

--- Show the history in a scratch split, one line per message line.
function M.showHistory()
  local lines = {}
  for _, item in ipairs(history) do
    local prefix = os.date('%H:%M:%S', item.time) .. ' ' .. (level_name[item.level] or '?') .. ' '
    for i, line in ipairs(vim.split(item.msg, '\n', { plain = true })) do
      table.insert(lines, (i == 1 and prefix or string.rep(' ', #prefix)) .. line)
    end
  end
  if #lines == 0 then lines = { 'No notifications yet.' } end

  vim.cmd('botright new')
  local hbuf = vim.api.nvim_get_current_buf()
  vim.bo[hbuf].buftype = 'nofile'
  vim.bo[hbuf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, lines)
  vim.bo[hbuf].modifiable = false
  -- pcall: the name is taken while an earlier history split is still open.
  pcall(vim.api.nvim_buf_set_name, hbuf, 'Notifications')
  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = hbuf, desc = 'Close notification history' })
  vim.cmd('normal! G')
end

vim.api.nvim_create_user_command('Notifications', M.showHistory, { desc = 'Show notification history' })

-- Keep the window in the corner when the editor is resized.
vim.api.nvim_create_autocmd('VimResized', {
  group = vim.api.nvim_create_augroup('PureNotify', { clear = true }),
  callback = function() if #active > 0 then render() end end,
})

vim.notify = M.notify

return M
