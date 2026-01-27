-- better transparency mode on solarized Theme
vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    if vim.g.MY_THEME ~= 'solarized-osaka' then
      local ok, theme = pcall(require, vim.g.MY_THEME)

      if ok and theme then pcall(theme.setup, {transparent = true}) end
      pcall(vim.cmd.colorscheme, vim.g.MY_THEME)
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


-- Highlight todo tasks
vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"},{
  pattern = '*',
  callback = function ()
    pcall(vim.fn.matchdelete, 1234)
    vim.fn.matchadd("Todo", [[TODO:.*]],10,1234)
    vim.api.nvim_set_hl(0, "Todo", {bg = 'grey', fg = 'NvimLightGrey2'})
  end

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
    os.remove(vim.fn.expand("~/.cache/nvim/*"))
    os.remove(vim.fn.expand("~/.scratch/**/*"))
  end,
})

-- PopUp Menu Completion
vim.api.nvim_create_autocmd("InsertCharPre", {
  callback = function()
    if vim.fn.pumvisible() == 0 and vim.v.char:match("[%w_]") then

      vim.schedule(function()

        if next(vim.lsp.get_clients({bufnr = 0})) and vim.bo.omnifunc ~= "" then
          vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-o>", true, false, true), "n")
        else
          vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-n>", true, false, true), "n")
        end
      end)
    end
  end,
})
vim.api.nvim_create_autocmd("CompleteDone", {
  callback = function()
    local completed_item = vim.v.completed_item
    if completed_item and completed_item.user_data and completed_item.user_data.nvim and completed_item.user_data.nvim.lsp then
    end
  end
})
