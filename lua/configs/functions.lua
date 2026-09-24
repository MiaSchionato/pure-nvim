local M = {}

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

--- Highlight every occurrence of the word under the cursor, or turn the
--- highlight off when it is already showing that same word. On another word
--- it switches to that word instead of just turning off.
---
--- This used to yank with 'viw"vy ', which clobbered register v and, through
--- the trailing space, moved the cursor one column right on every use.
function M.toggleWordHighlight()
  local word = vim.fn.expand('<cword>')
  -- \V: no regex magic ('.' or '*' in the word match literally);
  -- \< \>: whole word only, so 'foo' no longer lights up 'foobar'.
  local pattern = '\\V\\<' .. vim.fn.escape(word, '\\') .. '\\>'

  if vim.o.hlsearch and (word == '' or vim.fn.getreg('/') == pattern) then
    vim.o.hlsearch = false
    return
  end
  if word == '' then return end

  vim.fn.setreg('/', pattern)
  vim.fn.histadd('/', pattern) -- so / then <Up> recalls it
  vim.o.hlsearch = true
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

--- Toggle the checkbox of the list item on the cursor line: [ ] -> [x] -> [ ].
--- Obsidian's other states ([~] [!] [>] [-]) count as not done, so they go to
--- [x]. A plain '- item' gets an empty box.
---
--- Only the box right after the bullet is touched; this used to change the
--- first "[ ]" anywhere in the line, so brackets in the task text could flip.
--- Shared by <leader>tx in notes and <CR> in the Todoist list, so every way of
--- ticking a box behaves the same.
function M.toggleCheckbox()
  local line = vim.api.nvim_get_current_line()
  local prefix, state, rest = line:match('^(%s*[-*+]%s+)%[(.?)%](.*)$')
  local new_line
  if prefix then
    new_line = prefix .. (state:match('[xX]') and '[ ]' or '[x]') .. rest
  else
    local bullet, text = line:match('^(%s*[-*+]%s+)(.*)$')
    if not bullet then return end
    new_line = bullet .. '[ ] ' .. text
  end
  vim.api.nvim_set_current_line(new_line)
end

--- Cycle the checkbox of the list item on the cursor line through Obsidian's
--- states: [ ] -> [~] in progress -> [!] important -> [>] deferred ->
--- [-] cancelled -> [x] done -> [ ]. A plain '- item' gets an empty box.
--- For notes only: Todoist knows just [ ] and [x].
function M.cycleCheckbox()
  local order = { ' ', '~', '!', '>', '-', 'x' }
  local line = vim.api.nvim_get_current_line()
  local prefix, state, rest = line:match('^(%s*[-*+]%s+)%[(.?)%](.*)$')
  local new_line
  if prefix then
    state = state == '' and ' ' or state:lower()
    local next_state = ' '
    for i, s in ipairs(order) do
      if s == state then next_state = order[i % #order + 1] end
    end
    new_line = prefix .. '[' .. next_state .. ']' .. rest
  else
    local bullet, text = line:match('^(%s*[-*+]%s+)(.*)$')
    if not bullet then return end
    new_line = bullet .. '[ ] ' .. text
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
