-- True while VimEnter applies the saved theme: that is a reading of the choice, not a new choice.
local applyingSaved = false

vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    local okOm, omarchy = pcall(require, 'pure.omarchy-theme')
    local theme = okOm and omarchy.saved() or vim.g.MY_THEME

    if theme == 'omarchy' and okOm then
      local scheme, why = omarchy.resolved()
      if not scheme then
        vim.notify('Omarchy theme: ' .. tostring(why), vim.log.levels.WARN)
      end
      theme = scheme
    end

    -- Nothing saved yet: the local theme (colors/myghtfly.lua), which needs no download.
    theme = theme or 'myghtfly'

    -- Any saved theme is applied here, and only here: no theme applies itself.
    applyingSaved = true
    local applied = pcall(vim.cmd.colorscheme, theme)
    if not applied and theme ~= 'myghtfly' then
      pcall(vim.cmd.colorscheme, 'myghtfly')
    end
    applyingSaved = false

    -- Disable annoying commenting while coding
    vim.api.nvim_set_hl(0, "DiagnosticUnnecessary", {})
  end,
})

-- Persist whatever colorscheme is applied (via :colorscheme, <leader>fc, etc.)
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function(args)
    local scheme = args.match
    if applyingSaved or vim.g.pure_reapplying_theme or not scheme or scheme == "" then return end
    vim.g.MY_THEME = scheme
    local okOm, omarchy = pcall(require, 'pure.omarchy-theme')
    -- In "omarchy" mode the saved choice is the mode, not the scheme it resolved to.
    if okOm and omarchy.saved() ~= omarchy.NAME then
      omarchy.save(scheme)
    end
  end,
})

-- Floats follow the theme's Normal background (see syncFloatBg); the scheduled
-- call runs again after any Normal override (neovide.lua).
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    local func = require('configs.functions')
    func.syncFloatBg(true)
    vim.schedule(func.syncFloatBg)
  end,
})

-- Dashboard
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 and vim.fn.line2byte("$") == -1 then
      require('pure.dashboard').drawDashboard()
    end
  end,
})

-- A new tab (:tabnew, <leader>wn) opens on the scratch note, not on an empty
-- buffer (pure/scratch.lua; vim.g.pure_newtab = 'dashboard' brings the dashboard back there).


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
--
-- Where a language server completes, it alone fills the menu: it already
-- knows the buffer's names, and the plain word sources listed each of them a
-- second time ("banana" and "banana  Variable"). Prose keeps the words.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    local prose = { markdown = true, text = true, gitcommit = true }
    -- Copilot is a language server too, but for inline suggestions only.
    if client and not client.name:lower():find("copilot", 1, true)
      and client:supports_method("textDocument/completion")
      and not prose[vim.bo[args.buf].filetype] then
      vim.bo[args.buf].complete = "o"
    end
  end,
})



-- Tell WezTerm that this pane runs nvim (user var IN_NVIM): its Win+C / Win+V keys
-- (F16 / F15) are handed to nvim here and used for the terminal clipboard elsewhere.
do
  local function setNvimFlag(value)
    local b64 = value == "" and "" or vim.base64.encode(value)
    io.stdout:write("\027]1337;SetUserVar=IN_NVIM=" .. b64 .. "\007")
  end
  vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, { callback = function() setNvimFlag("1") end })
  vim.api.nvim_create_autocmd({ "VimLeave", "VimSuspend" }, { callback = function() setNvimFlag("") end })
end
