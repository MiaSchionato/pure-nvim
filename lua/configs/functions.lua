local M = {}

--- Remember a toggle across restarts (configs/functions.lua). Never raises.
local function save(key, value)
  M.set(key, value)
end

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

--- Give floating windows (fuzzy finder, pickers, popups, notifications) the
--- same background as the editor: whatever `Normal` has under the current
--- colorscheme, so every theme gets matching floats instead of its own panel
--- colour or a transparent one.
local floatBgGroups = {
  "NormalFloat", "FloatBorder", "FloatTitle", "FloatFooter",
  "Pmenu", "PmenuSbar", "PmenuBorder",
}
local themeBg
--- `fresh`: a colorscheme was just applied, so forget the previous theme's
--- background. Later calls (after Normal was made transparent) keep using the
--- theme's own colour rather than going transparent too.
function M.syncFloatBg(fresh)
  if fresh then themeBg = nil end
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  themeBg = normal.bg or themeBg
  for _, group in ipairs(floatBgGroups) do
    local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    hl.bg, hl.ctermbg = themeBg, nil
    vim.api.nvim_set_hl(0, group, hl)
  end
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
  save('laststatus', vim.o.laststatus)
end

function M.toggleTabline()
    if vim.o.showtabline == 1 then
        vim.o.showtabline = 0
    else
        vim.o.showtabline = 1
    end
    save('showtabline', vim.o.showtabline)
end

function M.toggleNumber()
  if vim.o.number == true then
    vim.o.number = false
  else
    vim.o.number = true
  end
  save('number', vim.o.number)
end

function M.toggleRelativenumber()
  vim.opt.relativenumber = not vim.opt.relativenumber:get()
  save('relativenumber', vim.o.relativenumber)
end

function M.toggleSigncolumn()
  if vim.wo.signcolumn:match('^yes') or vim.wo.signcolumn:match('^auto') then
    vim.wo.signcolumn = 'no'
  else
    vim.wo.signcolumn = 'yes'
  end
  save('signcolumn', vim.wo.signcolumn)
end

function M.toggleWrap()
  vim.wo.wrap = not vim.wo.wrap
  save('wrap', vim.wo.wrap)
end

function M.toggleDiagnostics()
  local on = not vim.diagnostic.config().virtual_text
  vim.diagnostic.config({ virtual_text = on })
  save('diagnostics_virtual_text', on)
end

function M.toggleInlayHints()
  -- This used to *assign* a boolean over vim.lsp.inlay_hint.enable, replacing
  -- the function itself. After one press the API was gone, which also broke
  -- toggleZenMode() above (it calls vim.lsp.inlay_hint.enable(...)).
  local on = not vim.lsp.inlay_hint.is_enabled()
  vim.lsp.inlay_hint.enable(on)
  save('inlay_hints', on)
end

function M.getOpts(base_opts, desc)
  return vim.tbl_extend("force", base_opts, {desc = desc})
end

--- A centred floating window. `opts`: enter (default true) false leaves the
--- focus where it was; buf shows an existing buffer instead of a new scratch one.
function M.createWindow(title, ratio, opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_create_buf(false, true)
  local height = math.ceil(vim.o.lines * ratio)
  local width = math.ceil(vim.o.columns * ratio)
  if title == " " then
    title = nil
  end

  local win = vim.api.nvim_open_win(buf, opts.enter ~= false, {
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

-- TODO:Add signcolumn always shown ()
local namespace_id =vim.api.nvim_create_namespace("git-diff")
-- Per buffer (b:pure_git_diff): one global flag meant toggling in a second
-- buffer "deactivated" it there, while the first kept its marks.
function M.gitDiffToggle()
  if vim.b.pure_git_diff then
    vim.api.nvim_buf_clear_namespace(0,namespace_id,0,-1)
    vim.b.pure_git_diff = false
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

  vim.b.pure_git_diff = true
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

--- The selected lines (visual mode) all take the state that follows the one of
--- the first task in the selection, so five tasks end up the same whatever
--- their states were before. Plain '- item' lines get an empty box, lines
--- that are not list items are left alone.
function M.cycleCheckboxRange()
  local order = { ' ', '~', '!', '>', '-', 'x' }
  local first, last = vim.fn.line('v'), vim.fn.line('.')
  if first > last then first, last = last, first end
  local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)

  local target
  for _, line in ipairs(lines) do
    local state = line:match('^%s*[-*+]%s+%[(.?)%]')
    if state then
      state = state == '' and ' ' or state:lower()
      target = ' '
      for i, s in ipairs(order) do
        if s == state then target = order[i % #order + 1] end
      end
      break
    end
  end
  target = target or ' '

  for i, line in ipairs(lines) do
    local prefix, rest = line:match('^(%s*[-*+]%s+)%[.?%](.*)$')
    if prefix then
      lines[i] = prefix .. '[' .. target .. ']' .. rest
    else
      local bullet, text = line:match('^(%s*[-*+]%s+)(.*)$')
      if bullet then lines[i] = bullet .. '[' .. target .. '] ' .. text end
    end
  end
  vim.api.nvim_buf_set_lines(0, first - 1, last, false, lines)
  vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
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

--- copilot.vim treats an unset g:copilot_enabled as enabled, so checking for
--- `== true` made the first press "enable" what was already on: nothing
--- changed, and it took a second press to turn Copilot off.
function M.toggleCopilot()
  local enabled = vim.g.copilot_enabled ~= false and vim.g.copilot_enabled ~= 0
  vim.g.copilot_enabled = not enabled
  save('copilot', not enabled)
  vim.notify(enabled and "Copilot Disabled" or "Copilot Enabled")
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

-- =============================================================================
--  Transparency  (<leader>oxc)
-- =============================================================================
-- Every theme starts opaque, with its own background (themes/colorschemes.lua). One
-- variable holds the state: false = the theme's own background, true = transparent.
--   Neovide  the window opacity: 1.0 or vim.g.transparencyAmount.
--   Terminal the backgrounds of themes.colorschemes.groups are cleared; going back
--            applies the colorscheme again, which brings its own colours back.
-- A colorscheme change keeps the state, so a transparent session stays transparent.
M.transparent = false

local groups = require('themes.colorschemes').groups

local function applyTransparency()
  if vim.g.neovide then
    local opacity = M.transparent and (vim.g.transparencyAmount or 0.9) or 1.0
    vim.g.neovide_opacity = opacity
    vim.g.neovide_normal_opacity = opacity
    return
  end
  for _, name in ipairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", hl, { bg = "NONE", ctermbg = "NONE" }))
  end
end

M.applyTransparency = applyTransparency

-- Some themes (night-owl) never set g:colors_name, so the last scheme is kept here.
local lastScheme

vim.api.nvim_create_autocmd("ColorScheme", {
  desc = "Remember the colorscheme; keep the editor transparent after a change",
  callback = function(args)
    lastScheme = args.match
    if M.transparent and not vim.g.neovide then
      vim.schedule(applyTransparency)
    end
  end,
})

function M.toggleTransparency()
  M.transparent = not M.transparent
  save('transparent', M.transparent)
  if M.transparent or vim.g.neovide then
    applyTransparency()
  else
    local scheme = vim.g.colors_name or lastScheme
    if scheme and scheme ~= "" then
      -- Not a new choice: configs/autocmds.lua must not save it.
      vim.g.pure_reapplying_theme = true
      pcall(vim.cmd.colorscheme, scheme)
      vim.g.pure_reapplying_theme = false
    end
  end
end

local file = vim.fn.stdpath('data') .. '/toggles.json'
local data

local function load()
  if data then return data end
  data = {}
  local fh = io.open(file, 'r')
  if fh then
    local text = fh:read('*a')
    fh:close()
    local ok, decoded = pcall(vim.json.decode, text)
    if ok and type(decoded) == 'table' then data = decoded end
  end
  return data
end

--- The saved value of a toggle, or `default` when it was never pressed.
function M.get(key, default)
  local value = load()[key]
  if value == nil then return default end
  return value
end

--- Save a value (nil forgets it). Never raises: a read-only data folder must not break a toggle.
function M.set(key, value)
  -- Read the file again and change only this key: another Neovim (or an older
  -- run) may have saved other toggles since this one started.
  data = nil
  load()[key] = value
  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  local ok, text = pcall(vim.json.encode, data)
  if not ok then return end
  local fh = io.open(file, 'w')
  if fh then
    fh:write(text)
    fh:close()
  end
end

-- -----------------------------------------------------------------------------
--  The coloured bar behind the headings (md and org): <leader>oH
-- -----------------------------------------------------------------------------
function M.headingBand()
  return M.get('heading_band', true)
end

function M.setHeadingBand(on)
  M.set('heading_band', on)
  for _, name in ipairs({ 'pure.render-md', 'pure.render-org' }) do
    local module = package.loaded[name]
    if type(module) == 'table' and module.refresh then pcall(module.refresh, true) end
  end
end

function M.toggleHeadingBand()
  local on = not M.headingBand()
  M.setHeadingBand(on)
  vim.notify('Heading background ' .. (on and 'on' or 'off'))
end

-- -----------------------------------------------------------------------------
--  The automatic hover (configs/lspConfigs.lua): <leader>tk
-- -----------------------------------------------------------------------------
--  On unless vim.g.lsp_auto_hover is false; the choice is saved like the other toggles.
function M.toggleAutoHover()
  local on = vim.g.lsp_auto_hover == false
  vim.g.lsp_auto_hover = on
  M.set('lsp_auto_hover', on)
  vim.notify('Automatic hover ' .. (on and 'on' or 'off'))
end

-- -----------------------------------------------------------------------------
--  Put the saved state back
-- -----------------------------------------------------------------------------
local function restore()
  local function saved(key, apply)
    local value = M.get(key)
    if value ~= nil then pcall(apply, value) end
  end

  saved('number', function(v) vim.o.number = v end)
  saved('relativenumber', function(v) vim.o.relativenumber = v end)
  saved('signcolumn', function(v) vim.o.signcolumn = v end)
  saved('wrap', function(v) vim.o.wrap = v end)
  saved('laststatus', function(v) vim.o.laststatus = v end)
  saved('showtabline', function(v) vim.o.showtabline = v end)
  saved('diagnostics_virtual_text', function(v) vim.diagnostic.config({ virtual_text = v }) end)
  saved('copilot', function(v) vim.g.copilot_enabled = v end)
  saved('lsp_auto_hover', function(v) vim.g.lsp_auto_hover = v end)
  saved('transparent', function(v) require('configs.functions').transparent = v end)
end

restore()

-- What needs a running UI or the LSP client: after startup.
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    local func = require('configs.functions')
    if func.transparent then pcall(func.applyTransparency) end
    local hints = M.get('inlay_hints')
    if hints ~= nil then pcall(vim.lsp.inlay_hint.enable, hints) end
  end,
})

vim.api.nvim_create_user_command('PureToggles', function(opts)
  if opts.args == 'reset' then
    data = {}
    pcall(os.remove, file)
    vim.notify('Saved toggles forgotten (the defaults apply on the next start)')
    return
  end
  vim.notify(vim.inspect(load()))
end, {
  nargs = '?',
  complete = function() return { 'reset' } end,
  desc = 'Show or reset the saved toggle states',
})


--- The directory `dir` names (a path, or a function returning one) when it exists; else nil, saying why.
--- Used by explore and inDir.
local function checkedDir(dir)
  -- Not `type(dir) == 'function' and dir() or dir`: when dir() returns nil
  -- (no vault yet) that idiom falls through to `or dir`, the function itself.
  local path = dir
  if type(dir) == 'function' then path = dir() end
  if not path then
    vim.notify('No directory set for this key', vim.log.levels.WARN)
    return nil
  end
  if vim.fn.isdirectory(path) == 0 then
    vim.notify('Directory does not exist: ' .. path, vim.log.levels.WARN)
    return nil
  end
  return path
end

--- Toggle an oil float on `dir` (a path, or a function returning one).
---
--- The same key closes the float again. That check comes first: inside oil the
--- buffer name is an oil:// URL, so here() would yield a path that isdirectory()
--- rejects and the key would warn instead of closing.
---
--- oil is required on use: plugins/oil.lua loads after the keymaps, so the module
--- is not on the runtimepath yet when they are defined.
function M.explore(dir)
  return function()
    local oil = require('oil')
    if vim.w.is_oil_win then
      return oil.close()
    end
    local path = checkedDir(dir)
    if path then oil.open_float(path) end
  end
end

-- =============================================================================
--  Helpers of the keymaps (moved from keymaps.lua, the logic as it was)
-- =============================================================================

local home = vim.uv.os_homedir():gsub("\\", "/") .. "/"

--- The vault folder with a trailing slash.
local function vaultDir()
  local vault = vim.fs.normalize(vim.fn.expand(vim.g.flora_dir or '~/Flora'))
  return vault and (vault .. '/') or nil
end

--- One table feeds explore (<leader>e_), find (<leader>f_) and new file
--- (<leader>n_), so each directory is written once instead of three times in
--- three near-identical blocks.
---
--TODO:Make those global variables and put it on configs.lua
M.dirs = {
  ['~'] = home,
  ['.'] = home .. '.config/',
  n     = home .. '.config/nvim/',
  -- The vault (org), vim.g.flora_dir or ~/Flora (pure/flora.lua).
  v     = vaultDir,
  p     = home .. 'Projects',
  -- The file new notes go to (<leader>oi opens it): vim.g.orgls_inbox, as in lsp/orgls.lua, or inbox.org.
  inbox = function()
    local vault = vaultDir()
    return vault and (vault .. (vim.g.orgls_inbox or 'inbox.org')) or nil
  end,
}

--- Directory `levels` up from the current file, always with a trailing slash.
--- A function, not a string: a string would be expanded once at startup and
--- keep pointing at the first file. In the scratch note (which lives in the
--- data folder) it counts from the folder the window was opened from:
--- pure/scratch.lua, scratch.dir(levels up).
function M.up(levels) return require('pure.scratch').dir(levels) .. '/' end

--- Directory of the current file.
function M.here()
  return M.up(0)
end

--- The directories above the current file, as functions (see M.up).
M.fileDirs = {
  p      = function() return M.up(0) end,
  pp     = function() return M.up(1) end,
  ["3p"] = function() return M.up(2) end,
  ["4p"] = function() return M.up(3) end,
}

--- Run `picker` on `dir`, saying so when the directory simply is not there.
--- Without this the picker opens, the shell fails on a missing path, and the
--- floating window blinks shut with nothing explaining why.
function M.inDir(picker, dir)
  return function()
    local path = checkedDir(dir)
    if path then picker(path) end
  end
end

--- Move lines (<up>/<down> in normal and visual mode).
---
--- Guarded by buffer type. The fuzzy pickers run fzf inside a terminal buffer,
--- and any moment spent in terminal-normal mode there (fuzzyLogic only calls
--- startinsert after a delay) meant the arrow keys fired this mapping instead of
--- reaching fzf -- failing with "E21: Cannot make changes, 'modifiable' is off"
--- and leaving the arrows apparently dead inside the picker.
---
--- Returning the key itself falls through to the builtin, because these mappings
--- are noremap: the returned key is not looked up again.
function M.moveLine(keys, fallback)
  return function()
    if vim.bo.buftype ~= '' or not vim.bo.modifiable then
      return fallback
    end
    return keys
  end
end

--- The file about you that every LLM request reads (outside any git repository).
function M.openUserContext()
  local path = require('pure.llm').userContextFile()
  if not path then return vim.notify('User context is off (vim.g.pure_llm_user_context = false)') end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

--- On a link, K follows it (pure/notes.lua): in markdown any link, elsewhere
--- only web links, since [[x]] in code is not a note. Else LSP hover.
function M.followOrHover()
  if require('pure.notes').follow(vim.bo.filetype ~= 'markdown') then return end
  vim.lsp.buf.hover()
end

--- <Up> in insert mode (expr map). Signature help only where a language server
--- can answer: in markdown (no such server) it raised 'method
--- "textDocument/signatureHelp" is not supported' on every press (Improvment.md).
--- Elsewhere <Up> moves up, as it would unmapped.
function M.signatureHelpOrUp()
  if #vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/signatureHelp' }) > 0 then
    return "<Cmd>lua vim.lsp.buf.signature_help()<CR>"
  end
  return "<Up>"
end

--- One toggle for the notes: markdown (pure/render-md.lua) or org (pure/render-org.lua), by the buffer.
function M.toggleNoteRendering()
  local module = vim.bo.filetype == 'org' and 'pure.render-org' or 'pure.render-md'
  require(module).toggle()
end

--- Delete the fold under the cursor, saying why when there is none.
function M.deleteFold()
  local ok, err = pcall(vim.cmd, 'normal! zd')
  if not ok then vim.notify(err:gsub('^.-E%d+: ', ''), vim.log.levels.WARN) end
end

--- One key for zR / zM: opens everything if any fold is closed, otherwise
--- closes them all.
function M.toggleAllFolds()
  for lnum = 1, vim.fn.line('$') do
    if vim.fn.foldclosed(lnum) ~= -1 then return vim.cmd('normal! zR') end
  end
  vim.cmd('normal! zM')
end

--- dd (expr map): an empty line is deleted without overwriting the default register.
function M.smartDd()
  if vim.api.nvim_get_current_line():match("^%s*$") then
    return '"_dd'
  end
  return "dd"
end

-- -----------------------------------------------------------------------------
--  Insert mode: Tab, S-Tab, Esc, Enter (completion, closing pairs, snippets, lists)
-- -----------------------------------------------------------------------------
--  Tab in insert mode (as asked in the vault's Improvment.md, second
--  round: Tab must not indent, and walks the suggestions). In order:
--    the completion menu open           next suggestion (<CR> takes it)
--    closers right after the cursor     step past all of them: "[[a|]]" -> "[[a]]|"
--    a snippet with a next field        jump to it
--    anything else                      a plain Tab, the one way left to
--                                       type one (<C-v><Tab> works too)
--  Tab never opens the menu itself ('autocomplete' opens it as you type):
--  returning <C-n> from this mapping with the menu closed crashed Neovim
--  0.12.5 (segfault) together with 'lazyredraw' and 'autocomplete'; it
--  reproduces with --clean, so it is Neovim's bug, not this config's.
--  The menu wins over a closer (third round, "option b"): inside [[...]]
--  the ]] is always there, so with the closer first Tab could never pick a
--  link. Esc closes the menu (below), then Tab steps past the pair.
--  The first version of this indented a markdown list item (<C-t>); that
--  was taken out on request. >> and << in normal mode still indent.
local closers = "[%)%]}>\"'`]"
local function closersAhead()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local ahead = vim.api.nvim_get_current_line():sub(col + 1)
  return #(ahead:match('^' .. closers .. '+') or '')
end

-- Right after a list item's marker ("- [ ] |", "- |", "1. |"), where the
-- item is still empty: Tab / S-Tab make it a sub-item / take it back out
-- (Improvment.md, fourth round). Anywhere else Tab never indents.
local function atItemStart()
  local it = require('pure.lists').item()
  return it ~= nil and vim.api.nvim_win_get_cursor(0)[2] == it.start
end

--- <Tab> in insert mode (expr map, replace_keycodes).
function M.insertTab()
  if atItemStart() then
    return (vim.fn.pumvisible() == 1 and "<C-e>" or "") .. "<C-t>"
  end
  if vim.fn.pumvisible() == 1 then return "<C-n>" end
  local n = closersAhead()
  if n > 0 then return string.rep("<right>", n) end
  if vim.snippet.active({ direction = 1 }) then
    return "<cmd>lua vim.snippet.jump(1)<cr>"
  end
  return "<tab>"
end

--- Mirrors Tab backwards: previous suggestion, snippet back; else the builtin.
function M.insertShiftTab()
  if atItemStart() then
    return (vim.fn.pumvisible() == 1 and "<C-e>" or "") .. "<C-d>"
  end
  if vim.fn.pumvisible() == 1 then return "<C-p>" end
  -- was `direction = 1` here too, so the backward jump asked whether a
  -- *forward* jump was possible.
  if vim.snippet.active({ direction = -1 }) then
    return "<cmd>lua vim.snippet.jump(-1)<cr>"
  end
  return "<S-tab>"
end

--- Esc with the completion menu open closes only the menu and stays in
--- insert mode (Improvment.md): then Tab steps past the pair. A suggestion
--- picked with Tab is kept (<C-y>); with none picked the typed text stays
--- (<C-e>). A second Esc leaves insert mode as always.
function M.insertEsc()
  if vim.fn.pumvisible() == 0 then return "<Esc>" end
  return vim.fn.complete_info({ 'selected' }).selected ~= -1 and "<C-y>" or "<C-e>"
end

--- <CR>: a Copilot suggestion on screen is accepted. With the completion menu
--- open the suggestion is taken: the selected item, or the first one when
--- none is (completeopt has noselect, so usually none is). Only when the
--- word typed already is that first item (nothing left to complete) does
--- <CR> close the menu and make the new line. Otherwise, in a markdown list,
--- the next item starts (pure/lists.lua), else a plain new line.
--- (expr map, replace_keycodes = false: the keys are returned already translated.)
function M.insertEnter()
  local ok, shown = pcall(vim.fn['copilot#GetDisplayedSuggestion'])
  if ok and type(shown) == 'table' and (shown.text or '') ~= '' then
    return vim.fn['copilot#Accept']('')
  end
  local cr = vim.keycode('<CR>')
  if vim.fn.pumvisible() == 1 then
    local info = vim.fn.complete_info({ 'selected', 'items' })
    if info.selected ~= -1 then return vim.keycode('<C-y>') end
    local first = info.items[1] and info.items[1].word or ''
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local before = vim.api.nvim_get_current_line():sub(1, col)
    if first ~= '' and before:sub(-#first) ~= first then
      return vim.keycode('<C-n><C-y>')
    end
    local list = require('pure.lists').enter()
    return vim.keycode('<C-e>') .. (list or cr)
  end
  return require('pure.lists').enter() or cr
end

return M
