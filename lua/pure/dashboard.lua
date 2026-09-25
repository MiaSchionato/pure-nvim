-- ~/.config/nvim/lua/Custom_dashboard.lua

local M = {}

-- State to hold your original UI options
M.state = {
  is_active = false,
  user_laststatus = nil,
  user_showtabline = nil,
  user_winbar = nil,
  user_cursorline = nil,
  user_number = nil,
  user_relativenumber = nil,
}

-- Configuration for which UI elements to hide on the dashboard
local dashboard_ui_opts = {
  hide = {
    statusline = true,
    tabline = true,
    winbar = true,
    cursorline = true,
    number = true,
    relativenumber = true,
  }
}

-- Saves your current UI options
function M.save_ui_options()
  M.state.user_laststatus = vim.opt.laststatus:get()
  M.state.user_showtabline = vim.opt.showtabline:get()
  M.state.user_winbar = vim.opt.winbar:get()
  M.state.user_cursorline = vim.opt.cursorline:get()
  M.state.user_number = vim.opt.number:get()
  M.state.user_relativenumber= vim.opt.relativenumber:get()
  M.state.is_active = true
end

-- Applies the special UI settings for the dashboard
function M.set_dashboard_ui()
  if dashboard_ui_opts.hide.statusline then vim.opt.laststatus = 0 end
  if dashboard_ui_opts.hide.tabline then vim.opt.showtabline = 0 end
  if dashboard_ui_opts.hide.winbar then vim.opt.winbar = '' end
  if dashboard_ui_opts.hide.cursorline then vim.opt.cursorline = false end
  if dashboard_ui_opts.hide.number then vim.opt.number = false end
  if dashboard_ui_opts.hide.relativenumber then vim.opt.relativenumber = false end
end

-- Restores your original UI options
function M.restore_ui_options()
  if not M.state.is_active then return end

  vim.opt.laststatus = M.state.user_laststatus
  vim.opt.showtabline = M.state.user_showtabline
  vim.opt.winbar = M.state.user_winbar
  vim.opt.cursorline = M.state.user_cursorline
  -- number/relativenumber were saved and hidden but never restored, so line
  -- numbers stayed off for the rest of the session after leaving the dashboard.
  vim.opt.number = M.state.user_number
  vim.opt.relativenumber = M.state.user_relativenumber

  -- Reset state to indicate dashboard is no longer controlling the UI
  M.state.is_active = false
end

-- Creates a single, robust autocommand to manage UI state.
-- This is inspired by the logic in dashboard.nvim.
local function setup_ui_management_autocommand()
  local group = vim.api.nvim_create_augroup('CustomDashboardUIMgmt', { clear = true })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(args)
      -- When entering a dashboard buffer, ensure its special UI is set
      if vim.bo[args.buf].filetype == 'dashboard' then
        M.set_dashboard_ui()
        return
      end

      -- If we are in a normal buffer, check if we should restore the original UI
      if M.state.is_active then
        local dashboard_is_visible = false
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dashboard' then
            dashboard_is_visible = true
            break
          end
        end

        if not dashboard_is_visible then
          M.restore_ui_options()
          -- The autocommand has done its job, so we can remove it.
          vim.api.nvim_del_augroup_by_name('CustomDashboardUIMgmt')
        end
      end
    end,
  })
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

-- Your function to draw the dashboard, now with UI management
function M.drawDashboard()
  -- If the dashboard isn't already active, save the current UI state
  -- and set up the autocommand to manage restoring it.
  if not M.state.is_active then
    M.save_ui_options()
    setup_ui_management_autocommand()
  end

  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.bo[buf].filetype = 'dashboard'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false

  -- Apply dashboard-specific UI settings now
  M.set_dashboard_ui()

  vim.api.nvim_win_set_buf(0, buf)
  render(buf, vim.api.nvim_get_current_win())

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
  vim.keymap.set('n', 'q', ':qa<CR>', opts)
  vim.keymap.set('n', 'u', function()
    if vim.pack.update then
      vim.pack.update()
    else
      print("vim.pack.update is not defined.")
    end
  end, opts)
end

return M
