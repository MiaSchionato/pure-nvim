local M = {}
local mini = require('plugins.mini')

function M.ConfigHighlightByColorscheme(colorscheme, highlightGroups)
  vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = colorscheme,
    desc = "Set transparent float background for NeoSolarized",
    callback = function()
      for key, value in pairs(highlightGroups) do
        vim.api.nvim_set_hl(0, key, value)
      end
    end,
  })
end

function M.MyTabline()
  local line = ""
  local tabs = vim.api.nvim_list_tabpages()

  for i, tab_id in ipairs(tabs) do
    local is_selected = tab_id == vim.api.nvim_get_current_tabpage()
    local win_id = vim.api.nvim_tabpage_get_win(tab_id)
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    local buf_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf_id), ":t")

    if buf_name == "" then
      buf_name = "[No Name]"
    end

    local highlight = is_selected and "%#TabLineSel#" or "%#TabLine#"
    line = line .. highlight .. " " .. i .. " " .. buf_name .. " "
  end

  return line .. "%#TabLineFill#"
end

local zen_mode_enabled = false
function M.toggleZenMode(show_notify)
  show_notify = show_notify ~= false -- Default to true if not explicitly false
  zen_mode_enabled = not zen_mode_enabled

  -- Toggle LSP features
  vim.lsp.inlay_hint.enable(not zen_mode_enabled)
  vim.diagnostic.config({
    virtual_text = not zen_mode_enabled
  })

  -- Toggle UI elements
  vim.wo.signcolumn = zen_mode_enabled and 'no' or 'auto'
  vim.wo.relativenumber = not zen_mode_enabled
  vim.wo.number = not zen_mode_enabled
  vim.o.showtabline = zen_mode_enabled and 0 or 1
  vim.o.laststatus = zen_mode_enabled and 0 or 2

  if show_notify then
    if zen_mode_enabled then
      vim.notify('Zen Mode Enabled')
    else
      vim.notify('Zen Mode Disabled')
    end
  end
end

-- Dedicated function to apply the dashboard's visual style.
function M.applyDashboardStyle()
  vim.wo.relativenumber = false
  vim.wo.number = false
  vim.wo.signcolumn = 'no'
  vim.o.showtabline = 0
  vim.o.laststatus = 0
end

-- Dedicated function to reset the dashboard's visual style.
function M.resetDashboardStyle()
  vim.wo.relativenumber = true
  vim.wo.number = true
  vim.wo.signcolumn = 'auto'
  vim.o.showtabline = 1
  vim.o.laststatus = 2
end


function M.toggleStatusline()
  if vim.o.laststatus == 0 then
    vim.o.laststatus = 2
  else
    vim.o.laststatus = 0
  end
end

function M.toggleTabline()
    if vim.o.showtabline == 1 then
        vim.o.showtabline = 0
    else
        vim.o.showtabline = 1
    end
end

function M.toggleNumber()
  if vim.o.number == true then
    vim.o.number = false
  else
    vim.o.number = true
  end
end

function M.toggleRelativenumber()
  vim.opt.relativenumber = not vim.opt.relativenumber:get()
end

function M.toggleSigncolumn()
  if vim.wo.signcolumn:match('^yes') or vim.wo.signcolumn:match('^auto') then
    vim.wo.signcolumn = 'no'
  else
    vim.wo.signcolumn = 'yes'
  end
end

function M.toggleDiagnostics()
  vim.diagnostic.config({
    virtual_text = not vim.diagnostic.config().virtual_text
  })
end

-- These probed `mini.session`, but `mini` here is require('plugins.mini'),
-- which returns an empty table -- so every call raised "attempt to index a nil
-- value". mini.snippets is currently commented out in plugins/mini.lua, hence
-- the guard rather than a hard reference.
local function snippetSessionActive()
  return _G.MiniSnippets ~= nil and MiniSnippets.session.get() ~= nil
end

function M.snippetJumpNext()
  if snippetSessionActive() then
    return '<Cmd>lua MiniSnippets.session.jump("next")<CR>'
  end
  return '<Right>'
end

function M.snippetJumpPrev()
  if snippetSessionActive() then
    return '<Cmd>lua MiniSnippets.session.jump("prev")<CR>'
  end
  return '<Left>'   -- was '<Right>'
end

function M.snippetStop()
  if snippetSessionActive() then
    MiniSnippets.session.stop()
  end
  vim.cmd.stopinsert()
end

function M.toggleInlayHints()
  -- This used to *assign* a boolean over vim.lsp.inlay_hint.enable, replacing
  -- the function itself. After one press the API was gone, which also broke
  -- toggleZenMode() above (it calls vim.lsp.inlay_hint.enable(...)).
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end

function M.getOpts(base_opts, desc)
  return vim.tbl_extend("force", base_opts, {desc = desc})
end

function M.createWindow(title, ratio)
  local buf = vim.api.nvim_create_buf(false, true)
  local height = math.ceil(vim.o.lines * ratio)
  local width = math.ceil(vim.o.columns * ratio)
  if title == " " then
    title = nil
  end

  local win = vim.api.nvim_open_win(buf, true,{
    relative = "editor",
    width = width,
    height = height,
    row = math.ceil((vim.o.lines - height) / 2),
    col = math.ceil((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = title,
  })

  return win, buf
end

function M.toggleHighlightSearch()
  local is_active = vim.opt.hlsearch:get()
  vim.opt.hlsearch = not is_active
end

function M.toggleWordHighlight()
  local is_active = vim.opt.hlsearch:get()
  vim.opt.hlsearch = not is_active
  vim.cmd('noautocmd normal! viw"vy ')
  local text = vim.fn.getreg('v')
  vim.fn.setreg('/', text)
end

-- TODO: Move this func to its own file to extend functionality
-- Git Diff

-- TODO:Add signcolumn always shown ()
local namespace_id =vim.api.nvim_create_namespace("git-diff")
local diff_active = false
function M.gitDiffToggle()
  if diff_active then
    vim.api.nvim_buf_clear_namespace(0,namespace_id,0,-1)
    diff_active = false
    vim.notify("diff deactivated")
    return
  end

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then return end
  local file_path = vim.fn.fnamemodify(buf_path, ":h")


  local cmd = string.format("git -C %s diff -U0 --no-color -- %s",
  vim.fn.shellescape(file_path), -- buff parent dir
  vim.fn.shellescape(vim.fn.fnamemodify(buf_path, ":t"))
  )

  local output = vim.fn.systemlist(cmd)

  if not output or #output == 0 then
    vim.notify("Git diff: nothing to show")
    return
  end

  diff_active = true
  vim.notify("Git diff activated")
  local current_line = 0

  for i = 1, #output do
    local line = output[i]
    local start_line = line:match("^@@.-%+(%d+)")

    if start_line then
      current_line = tonumber(start_line) or 0

    elseif line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
      vim.api.nvim_buf_set_extmark(0, namespace_id, current_line - 1, 0, {
        line_hl_group = "DiffAdd",
        end_row = current_line, -- covers whole line
        sign_text = "+",
        sign_hl_group = "GitSignAdd",
        priority = 100,
      })
      current_line = current_line + 1

    elseif line:sub(1,1) == "-" and line:sub(1, 3) ~= "---" then
      local deleted_text = line:sub(2)
      vim.api.nvim_buf_set_extmark(0, namespace_id, math.max(0, current_line -1), 0, {
        sign_text = " ",
        virt_lines = {{{" - " .. deleted_text, "DiffDelete"}}},
        virt_lines_above = true,
      })

    end
  end
end

function M.toggleCheckbox()
  local line = vim.api.nvim_get_current_line()
  local new_line = ""
  if line:find("%[%s?%]") then
    new_line = line:gsub("%[%s?%]", "[x]", 1)
  elseif line:find("%[[xX]%]") then
    new_line = line:gsub("%[[xX]%]", "[ ]", 1)
  elseif line:find("^%s*-%s") then
    new_line = line:gsub("(-%s)", "- [ ] ", 1)
  else
    return
  end
  vim.api.nvim_set_current_line(new_line)
end

function M.toggleExplore()
  if vim.bo.filetype == "netrw" then
    vim.cmd("Rexplore")
  else
    vim.cmd("Ex")
  end
end

function M.smartQuote()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] -- column

  local beforeCursor = line:sub(1, col + 1)
  local _, doubleQuotes= beforeCursor:gsub('"', "")
  local _, singleQuotes = beforeCursor:gsub("'", "")

  -- if there's an odd number of quotes before the cursor, means the cursor are inside a quote
  if doubleQuotes % 2 ~= 0 then return '"' end
  if singleQuotes % 2 ~= 0 then return "'" end

  -- if both even number, change the next quotes from the cursor
  local afterCursor = line:sub(col+2)
  local nextDoble = afterCursor:find('"') or 999
  local nextSingle = afterCursor:find("'") or 999

  if nextSingle < nextDoble then
    return "'"
  else
    return '"'
  end
end

function M.toggleCopilot()
  if vim.g.copilot_enabled == true then
    vim.g.copilot_enabled = false
    vim.notify("Copilot Disabled")
  else
    vim.g.copilot_enabled = true
    vim.notify("Copilot Enabled")
  end
end

---@return boolean verify if it's a blank line or space before the cursor
function M.isBlank()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  if col == 0 then
    return true
  end

  local line = vim.api.nvim_get_current_line()
  local charBeforeLine = line:sub(col, col)

  return charBeforeLine == " " or charBeforeLine == "\t"
end

return M
