-- =============================================================================
--  Reading mode  (a column of text in the middle, wide margins)
-- =============================================================================
--  Two empty windows, one on each side, take the width the text does not need, so
--  the window with the text is a column in the middle: lines wrap at its width, a
--  note reads like a page. The margins are plain windows, not padding drawn in the
--  text, so wrapping, the cursor and every other module see an ordinary window.
--
--    toggle (<leader>tR)   reading mode on / off in this tab
--    :PureReading [on|off|toggle]
--    :PureReading width 100      the text column is 100 columns wide (now, and from then on)
--    :PureReading width +8 / -8  wider / narrower by 8
--    :PureReading width          shows it
--
--  It is saved (configs/toggles.lua keys `reading`, `reading_width`) and applied again at the
--  next start and in new tabs that open on a file.
--
--  Settings (configs.lua):
--    vim.g.pure_reading_width   the width of the text column when none was chosen with the command (84)
--    vim.g.pure_reading_min     the smallest margin, in columns (default 4); a window
--                               too narrow for the column keeps the margins and the text shrinks
--
--  The margins never take the cursor: entering one goes back to the text. :q in the
--  text window closes the margins first, so it quits as it would without them. Splits
--  inside the column are your own business: the margins are laid out for the layout
--  as it is when the mode starts (toggle it off and on to lay them out again). The big
--  headings of a terminal that needs the full width (WezTerm's DECDHL) fall back to the
--  icon and band while the margins are there.
-- =============================================================================

local M = {}

local api = vim.api

-- tab -> { left = win, right = win, main = win }
local tabs = {}

local function setting(name, default)
  local value = vim.g['pure_reading_' .. name]
  return type(value) == 'number' and value or default
end

local function save(on)
  local ok, toggles = pcall(require, 'configs.toggles')
  if ok then toggles.set('reading', on) end
end

local function saved()
  local ok, toggles = pcall(require, 'configs.toggles')
  return ok and toggles.get('reading', false) == true
end

local function valid(win)
  return win and api.nvim_win_is_valid(win)
end

local MIN_WIDTH, MAX_WIDTH = 30, 400

--- The width of the text column: what :PureReading width chose (saved), else vim.g.pure_reading_width, else 84.
function M.width()
  local ok, toggles = pcall(require, 'configs.toggles')
  local chosen = ok and toggles.get('reading_width')
  if type(chosen) == 'number' then return chosen end
  return setting('width', 84)
end

--- The margin that centres a column of the wanted width, never below the minimum.
local function marginFor(total)
  local width = M.width()
  local min = setting('min', 4)
  return math.max(math.floor((total - width) / 2), min)
end

--- A margin window: empty, nothing to see (no numbers, no bars, no end-of-buffer tildes).
local function dress(win)
  local buf = api.nvim_win_get_buf(win)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'pure_reading_margin'
  vim.b[buf].pure_reading_margin = true
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn = false, false, 'no', '0'
  wo.cursorline, wo.cursorcolumn, wo.colorcolumn, wo.list, wo.spell = false, false, '', false, false
  wo.winfixwidth = true
  wo.statusline = ' '
  wo.winhighlight = 'Normal:Normal,NormalNC:Normal,EndOfBuffer:Normal,StatusLine:Normal,StatusLineNC:Normal,WinSeparator:Normal'
  wo.fillchars = 'eob: ,stl: ,stlnc: ,vert: '
end

local function sizes(state)
  if not (valid(state.main) and valid(state.left) and valid(state.right)) then return end
  local total = api.nvim_win_get_width(state.main) + api.nvim_win_get_width(state.left) + api.nvim_win_get_width(state.right)
  local margin = marginFor(total)
  api.nvim_win_set_width(state.left, margin)
  api.nvim_win_set_width(state.right, margin)
end

local function off(tab)
  local state = tabs[tab]
  tabs[tab] = nil
  if not state then return false end
  for _, win in ipairs({ state.left, state.right }) do
    if valid(win) and #api.nvim_tabpage_list_wins(tab) > 1 then pcall(api.nvim_win_close, win, true) end
  end
  return true
end

local function on(tab)
  if tabs[tab] then return end
  local main = api.nvim_get_current_win()
  if api.nvim_win_get_config(main).relative ~= '' then return end
  -- The whole width of the editor is what the column is centred in.
  local margin = marginFor(vim.o.columns)
  if vim.o.columns - 2 * margin < 20 then return end

  vim.cmd('noautocmd topleft vnew')
  local left = api.nvim_get_current_win()
  dress(left)
  vim.cmd('noautocmd botright vnew')
  local right = api.nvim_get_current_win()
  dress(right)
  api.nvim_set_current_win(main)

  tabs[tab] = { main = main, left = left, right = right }
  sizes(tabs[tab])
end

--- Turn the mode on or off in this tab (nil: flip it).
function M.set(want, quiet)
  local tab = api.nvim_get_current_tabpage()
  local current = tabs[tab] ~= nil
  if want == nil then want = not current end
  if want and not current then
    on(tab)
  elseif not want and current then
    off(tab)
  end
  save(want)
  if not quiet then vim.notify('Reading mode ' .. (want and 'on' or 'off')) end
end

function M.toggle() M.set(nil) end

--- Set the width of the text column: a number, or "+8" / "-8" from the current one. Saved; the margins
--- of every tab are laid out again at once.
function M.set_width(spec)
  local current = M.width()
  local text = tostring(spec):gsub('%s', '')
  local width
  if text:match('^[+-]%d+$') then
    width = current + tonumber(text)
  elseif text:match('^%d+$') then
    width = tonumber(text)
  else
    return vim.notify('Reading width: ' .. current .. ' (use a number, +N or -N)')
  end
  width = math.min(math.max(width, MIN_WIDTH), MAX_WIDTH)
  local ok, toggles = pcall(require, 'configs.toggles')
  if ok then toggles.set('reading_width', width) end
  for _, state in pairs(tabs) do sizes(state) end
  vim.notify('Reading width ' .. width)
end

function M.is_on() return tabs[api.nvim_get_current_tabpage()] ~= nil end

local group = api.nvim_create_augroup('PureReading', { clear = true })

-- The margins never keep the cursor.
api.nvim_create_autocmd('WinEnter', {
  group = group,
  callback = function()
    local win = api.nvim_get_current_win()
    if not vim.b[api.nvim_win_get_buf(win)].pure_reading_margin then return end
    local state = tabs[api.nvim_get_current_tabpage()]
    vim.schedule(function()
      if state and valid(state.main) then pcall(api.nvim_set_current_win, state.main) end
    end)
  end,
})

-- :q in the text window quits as it would without the margins: they go first.
api.nvim_create_autocmd('QuitPre', {
  group = group,
  callback = function()
    local tab = api.nvim_get_current_tabpage()
    local state = tabs[tab]
    if state and api.nvim_get_current_win() == state.main then
      off(tab)
    end
  end,
})

-- The text window was closed another way, or a margin was: the mode ends in that tab.
api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(args)
    local closed = tonumber(args.match)
    for tab, state in pairs(tabs) do
      if closed == state.main or closed == state.left or closed == state.right then
        vim.schedule(function() off(tab) end)
        return
      end
    end
  end,
})

api.nvim_create_autocmd('VimResized', {
  group = group,
  callback = function()
    for _, state in pairs(tabs) do sizes(state) end
  end,
})

-- A new tab that opens on a file reads the same way (when the mode is saved as on).
api.nvim_create_autocmd('TabEnter', {
  group = group,
  callback = function()
    if not saved() then return end
    vim.schedule(function()
      local tab = api.nvim_get_current_tabpage()
      if tabs[tab] or vim.bo.buftype ~= '' or vim.api.nvim_buf_get_name(0) == '' then return end
      on(tab)
    end)
  end,
})

-- At start: the first window, once the file (if any) is there.
api.nvim_create_autocmd('VimEnter', {
  group = group,
  once = true,
  callback = function()
    if not saved() then return end
    vim.schedule(function()
      local tab = api.nvim_get_current_tabpage()
      if not tabs[tab] and vim.bo.buftype == '' and api.nvim_buf_get_name(0) ~= '' then on(tab) end
    end)
  end,
})

api.nvim_create_user_command('PureReading', function(opts)
  local arg = vim.trim(opts.args)
  if arg == 'on' then M.set(true)
  elseif arg == 'off' then M.set(false)
  elseif arg:match('^width') then M.set_width(vim.trim(arg:sub(6)))
  else M.toggle() end
end, {
  nargs = '*',
  complete = function() return { 'on', 'off', 'toggle', 'width' } end,
  desc = 'Reading mode: a column of text between wide margins',
})

return M
