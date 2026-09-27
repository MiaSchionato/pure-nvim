-- ~/.config/nvim/lua/Custom_dashboard.lua

local M = {}

-- What the dashboard hides, in two parts:
--
-- * Line numbers and the cursorline are set on the dashboard's own window,
--   like :setlocal (vim.wo[win][0]): they belong to the dashboard buffer in
--   that window and go with it, so a file opened there, or any other window,
--   keeps its own. (They used to be set globally, for every window, and put
--   back afterwards.)
-- * The statusline and the tabline are global, so they follow the current
--   tab: hidden while it shows the dashboard, back as soon as it does not (a
--   file opened over it, another tab entered). With other tabs open the
--   tabline stays, so they can still be seen. The check used to look at the
--   windows of every tab, and gave up after the first restore: a dashboard in
--   one tab kept the statusline hidden in the others.
M.state = {
  hidden = false,   -- the statusline / tabline are the dashboard's
  laststatus = nil, -- the values to put back
  showtabline = nil,
}

local function tabShowsDashboard()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dashboard' then return true end
  end
  return false
end

--- Hide the statusline and tabline if the current tab shows the dashboard,
--- or put them back if it no longer does.
function M.syncUI()
  if tabShowsDashboard() then
    if not M.state.hidden then
      M.state.laststatus, M.state.showtabline = vim.o.laststatus, vim.o.showtabline
      M.state.hidden = true
    end
    vim.o.laststatus = 0
    vim.o.showtabline = #vim.api.nvim_list_tabpages() > 1 and M.state.showtabline or 0
  elseif M.state.hidden then
    vim.o.laststatus, vim.o.showtabline = M.state.laststatus, M.state.showtabline
    M.state.hidden = false
  end
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter', 'TabEnter' }, {
  group = vim.api.nvim_create_augroup('PureDashboardUI', { clear = true }),
  callback = function() M.syncUI() end,
})

--- Whether `buf` is the blank buffer Neovim starts with, or :tabnew opens:
--- no name, a normal buffer, unchanged and empty.
local function isBlank(buf)
  return vim.api.nvim_buf_get_name(buf) == '' and vim.bo[buf].buftype == ''
    and not vim.bo[buf].modified and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
end

--- The art without its surrounding blank space: trailing blank lines dropped
--- and the indentation shared by every line removed, so it can be centred.
local function trimArt(lines)
  local out = vim.deepcopy(lines)
  while #out > 0 and out[#out]:match('^%s*$') do table.remove(out) end
  local indent = math.huge
  for _, l in ipairs(out) do
    if l:match('%S') then indent = math.min(indent, #l:match('^%s*')) end
  end
  if indent == math.huge then indent = 0 end
  for i, l in ipairs(out) do out[i] = l:sub(indent + 1):gsub('%s+$', '') end
  return out
end

--- Scale the art by `k`: each character repeated k times, each line k times,
--- which keeps its proportions (a cell is about twice as tall as wide either
--- way). Menu lines ("[n] New File ...") are text, so they are left as is.
local function scaleArt(lines, k)
  if k <= 1 then return lines end
  local out = {}
  for _, l in ipairs(lines) do
    if l:match('%[%a%]') then
      table.insert(out, l)
    else
      local wide = table.concat(vim.tbl_map(function(c) return c:rep(k) end, vim.fn.split(l, [[\zs]])))
      for _ = 1, k do table.insert(out, wide) end
    end
  end
  return out
end

--- Fill the window with the art centred in it, at the largest scale that fits
--- (vim.g.pure_dashboard_scale: 'auto', the default, or a fixed number).
--- It used to be written as is, at the top left: in a big or full-screen
--- window the planet sat in one corner.
local function render(buf, win)
  if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then return end
  local art = trimArt(require('pure.ascii').saturn)
  local width, height = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)

  local art_w = 0
  for _, l in ipairs(art) do art_w = math.max(art_w, vim.fn.strdisplaywidth(l)) end
  local setting = vim.g.pure_dashboard_scale or 'auto'
  local k = tonumber(setting) or 1
  if setting == 'auto' then
    k = math.max(1, math.min(math.floor(width / math.max(art_w, 1)), math.floor(height / math.max(#art, 1))))
  end
  local lines = scaleArt(art, k)

  -- One left margin for the whole drawing, so it keeps its shape; the menu
  -- line is centred on its own.
  local block_w = 0
  for _, l in ipairs(lines) do
    if not l:match('%[%a%]') then block_w = math.max(block_w, vim.fn.strdisplaywidth(l)) end
  end
  local left = string.rep(' ', math.max(0, math.floor((width - block_w) / 2)))
  local out, menu_row = {}, 1
  for _ = 1, math.max(0, math.floor((height - #lines) / 2)) do table.insert(out, '') end
  for _, l in ipairs(lines) do
    if l:match('%[%a%]') then
      local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(l)) / 2))
      table.insert(out, string.rep(' ', pad) .. l)
      menu_row = #out
    else
      table.insert(out, l ~= '' and (left .. l) or '')
    end
  end

  -- Blank lines down to the bottom of the window. Past a buffer's last line
  -- Neovim draws '~', which showed under the drawing whenever it did not fill
  -- the window; the blank lines at the end of the art itself cannot do it,
  -- trimArt() drops them to centre it. Recomputed on every resize.
  while #out < height do table.insert(out, '') end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable = false
  -- Rest the cursor on the menu line, out of the drawing.
  pcall(vim.api.nvim_win_set_cursor, win, { menu_row, 0 })
end

--- Show the dashboard in the current window.
function M.drawDashboard()
  local previous = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.bo[buf].filetype = 'dashboard'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false

  vim.api.nvim_win_set_buf(0, buf)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win][0].number = false
  vim.wo[win][0].relativenumber = false
  vim.wo[win][0].cursorline = false
  M.syncUI()
  render(buf, win)

  -- The blank buffer it covers (Neovim's first one, or the one :tabnew made)
  -- would stay behind in the buffer list, unnamed and unused.
  if previous ~= buf and isBlank(previous) and #vim.fn.win_findbuf(previous) == 0 then
    pcall(vim.api.nvim_buf_delete, previous, {})
  end

  -- Redraw centred (and rescaled) whenever the window changes size: going
  -- full screen, a split, a font change.
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    callback = function()
      if not vim.api.nvim_buf_is_valid(buf) then return true end -- drop the autocmd
      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then render(buf, win) end
    end,
  })

  -- Set your keymaps for the dashboard buffer
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set('n', 'd', function() require('pure.zettelkasten').openDaily() end, opts)
  vim.keymap.set('n', 'n', ':enew<CR>', opts)
  -- In a tab of its own, q closes that tab; from the last one it quits.
  vim.keymap.set('n', 'q', function()
    vim.cmd(#vim.api.nvim_list_tabpages() > 1 and 'tabclose' or 'qa')
  end, opts)
  -- The configuration's own repository first, then the plugins (pure/update.lua).
  vim.keymap.set('n', 'u', function() require('pure.update').run() end, opts)
end

--- Show the dashboard in `tab` if it is still what :tabnew leaves: one
--- window on a blank buffer. Called once the command that opened the tab is
--- done, so a tab opened on a file, or filled in right away by whatever
--- opened it, is left alone.
function M.drawInBlankTab(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) or tab ~= vim.api.nvim_get_current_tabpage() then return end
  local win = vim.api.nvim_get_current_win()
  for _, other in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    -- Floating windows (a notification) do not count.
    if other ~= win and vim.api.nvim_win_get_config(other).relative == '' then return end
  end
  if isBlank(vim.api.nvim_win_get_buf(win)) then M.drawDashboard() end
end

return M
