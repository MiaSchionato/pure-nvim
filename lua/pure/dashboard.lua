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

-- Your function to draw the dashboard, now with UI management
function M.drawDashboard()
  -- If the dashboard isn't already active, save the current UI state
  -- and set up the autocommand to manage restoring it.
  if not M.state.is_active then
    M.save_ui_options()
    setup_ui_management_autocommand()
  end

  local buf = vim.api.nvim_create_buf(false, true)

  local header = require('pure.ascii')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, header.saturn)

  -- Set buffer options
  vim.bo[buf].filetype = 'dashboard'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  -- Apply dashboard-specific UI settings now
  M.set_dashboard_ui()

  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 8, 0 })

  -- Set your keymaps for the dashboard buffer
  local opts = { buffer = buf, silent = true, nowait = true }
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
