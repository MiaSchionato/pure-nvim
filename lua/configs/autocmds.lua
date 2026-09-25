-- better transparency mode on solarized Theme
vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    local theme = vim.g.MY_THEME

    -- solarized-osaka applies itself over in themes/solarized-osaka.lua.
    if theme and theme ~= 'solarized-osaka' then
      -- Plugin themes expose a lua module named after the colorscheme and want
      -- setup() before being applied. The local ones (myghtfly) do not, so this
      -- step is best-effort.
      local ok, mod = pcall(require, theme)
      if ok and type(mod) == 'table' and type(mod.setup) == 'function' then
        pcall(mod.setup, { transparent = true })
      end

      -- Report rather than swallow: a bare pcall here is what hid the fact that
      -- no colorscheme was ever being applied.
      local applied, err = pcall(vim.cmd.colorscheme, theme)
      if not applied then
        vim.notify('Could not apply colorscheme "' .. tostring(theme) .. '": '
          .. tostring(err), vim.log.levels.WARN)
      end
    end
    -- Disable annoying commenting while coding 
    vim.api.nvim_set_hl(0,"DiagnosticUnnecessary", {})
  end
})

-- Dashboard
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 and vim.fn.line2byte("$") == -1 then
      require('pure.dashboard').drawDashboard()
    end
  end,
})


-- Highlight "TODO:" lines.
-- The colour is set once and again after a colorscheme change (it was reset
-- on every BufEnter). The match is added once per window, and only in
-- windows showing a real file -- not terminals, pickers or the dashboard.
local function todoColour()
  vim.api.nvim_set_hl(0, "PureTodo", { bg = 'grey', fg = 'NvimLightGrey2' })
end
todoColour()
vim.api.nvim_create_autocmd("ColorScheme", { callback = todoColour })
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  callback = function()
    local has = vim.w.pure_todo_match
    if vim.bo.buftype == '' then
      if not has then vim.w.pure_todo_match = vim.fn.matchadd("PureTodo", [[TODO:.*]], 10) end
    elseif has then
      pcall(vim.fn.matchdelete, has)
      vim.w.pure_todo_match = nil
    end
  end,
})

local netrwGroup = vim.api.nvim_create_augroup("PureNetrw", {clear = true})
vim.api.nvim_create_autocmd("FileType", {
  group = netrwGroup,
  pattern = "netrw",
  callback = function()
    local map = function (lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, {remap = true, buffer = true, desc = desc })
    end

    map("a", "%", "Create new file")
    map("A", "d", "Create new directory")
    map("r", "R", "Rename")
    map("x", "D", "Delete")
    map("<BS>", "-", "Go to parent directory")
    map("p", "-", "Go to parent directory")
    map("h", "-", "Go to parent directory")
    map("l", "<cr>", "Edit file")
    map(".", "gh", "Show hide files")

    map("<Esc>", "<cmd>Rexplore<cr>", "Return to file")
  end
})

-- Terminal transparency for floating windows
-- vim.api.nvim_create_autocmd("TermOpen", {
--   group = vim.api.nvim_create_augroup("MiaTermTransparency", { clear = true }),
--   callback = function()
--     -- Check if the current window is a floating window
--     if vim.api.nvim_win_get_config(0).relative ~= "" then
--       -- Apply transparency specifically to this window
--       vim.opt_local.winblend = 20
--     end
--   end,
-- })

vim.api.nvim_create_autocmd("VimLeave", {
  pattern = "*",
  callback = function()
    -- os.remove() takes a literal filename and never expands a glob, so these
    -- calls could only ever try to delete files literally named "*" and did
    -- nothing. Remove the scratch files this config actually creates.
    -- pick_* are pickList's lists (removed after each pick; this catches any
    -- left by a picker still open at exit).
    local cache = vim.fn.stdpath('cache')
    os.remove(cache .. '/opts_run')
    for _, file in ipairs(vim.fn.glob(cache .. '/pick_*', true, true)) do
      os.remove(file)
    end
  end,
})

-- Completion as you type is Neovim's own 'autocomplete' (configs.lua). It
-- replaces an InsertCharPre handler that fed <C-x><C-o> / <C-x><C-n> on every
-- typed letter.


