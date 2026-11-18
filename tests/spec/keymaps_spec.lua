-- Every key of docs/keymaps.md exists in the running configuration, in the modes the page gives, and every
-- <leader> key of the configuration is on the page. The keys tested are the global ones (an empty buffer):
-- the keys of one kind of buffer (markdown, oil, the chat...) are on their own pages.

local MODES = { n = true, x = true, i = true, t = true, o = true, v = true, s = true, c = true }
local SECTION_MODES = { ['Normal mode, no leader'] = 'n', ['Visual mode'] = 'x', ['Insert mode'] = 'i',
  ['Terminal mode'] = 't' }

--- The rows of docs/keymaps.md: { lhs, modes = { 'n', 'x' }, desc, section, line }.
local function documented()
  local rows, section = {}, ''
  local path = vim.fn.stdpath('config') .. '/docs/keymaps.md'
  for i, l in ipairs(vim.fn.readfile(path)) do
    local head = l:match('^##%s+(.*)$')
    if head then section = head end
    local key, modes, desc = l:match('^|%s*`([^`]-)`%s*|%s*([%a, ]+)%s*|%s*(.-)%s*|%s*$')
    -- The tables of the sections without <leader> have no Mode column: the section says it.
    local sectionMode = SECTION_MODES[section]
    if not key and sectionMode then
      key, desc = l:match('^|%s*`([^`]-)`%s*|%s*(.-)%s*|%s*$')
      modes = sectionMode
    end
    if key and key ~= 'Key' then
      local list = {}
      for m in modes:gmatch('%a+') do if MODES[m] then list[#list + 1] = m end end
      if #list > 0 then rows[#rows + 1] = { lhs = key, modes = list, desc = desc, section = section, line = i } end
    end
  end
  return rows
end

--- The mapping of `lhs` in `mode` (global), or nil.
local function mapping(lhs, mode)
  local m = vim.fn.maparg(lhs, mode, false, true)
  if vim.tbl_isempty(m) or m.buffer == 1 then return nil end
  return m
end

local function scratch()
  vim.cmd('enew')
  vim.bo.buftype = 'nofile'
end

T.test('docs/keymaps.md is read: sections and rows', function()
  local rows = documented()
  T.ok(#rows > 150, 'more than 150 documented keys, got ' .. #rows)
end)

T.test('every documented key exists in its modes', function()
  scratch()
  local missing = {}
  for _, r in ipairs(documented()) do
    -- The terminal's keys belong to the floating terminal's buffer: the test below.
    for _, mode in ipairs(r.section == 'Terminal mode' and {} or r.modes) do
      if not mapping(r.lhs, mode) then
        missing[#missing + 1] = ('%s (%s)  line %d, %s'):format(r.lhs, mode, r.line, r.section)
      end
    end
  end
  T.eq(missing, {}, 'documented in docs/keymaps.md but not mapped')
end)

T.test('every global <leader> key of the configuration is documented', function()
  scratch()
  local leader = vim.g.mapleader or '\\'
  local doc = {}
  for _, r in ipairs(documented()) do
    for _, mode in ipairs(r.modes) do
      doc[mode .. ' ' .. vim.api.nvim_replace_termcodes(r.lhs, true, true, true)] = true
    end
  end
  local undocumented = {}
  for _, mode in ipairs({ 'n', 'x' }) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      local lhs = vim.api.nvim_replace_termcodes(m.lhs, true, true, true)
      if lhs:sub(1, #leader) == leader and #lhs > #leader and not doc[mode .. ' ' .. lhs]
        and not (m.desc or ''):match('^org:') and not m.lhs:match('<Plug>') then
        undocumented[#undocumented + 1] = ('%s (%s) %s'):format(m.lhs:gsub('^ ', '<leader>'), mode, m.desc or '')
      end
    end
  end
  table.sort(undocumented)
  T.eq(undocumented, {}, 'mapped but not in docs/keymaps.md')
end)

T.test('every <leader> key has a description (the key hint window shows it)', function()
  scratch()
  local leader = vim.g.mapleader or '\\'
  local bare = {}
  for _, mode in ipairs({ 'n', 'x' }) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      local lhs = vim.api.nvim_replace_termcodes(m.lhs, true, true, true)
      if lhs:sub(1, #leader) == leader and (m.desc or '') == '' and not m.lhs:match('<Plug>') then
        bare[#bare + 1] = ('%s (%s)'):format(m.lhs:gsub('^ ', '<leader>'), mode)
      end
    end
  end
  table.sort(bare)
  T.eq(bare, {}, '<leader> keys without a description')
end)

T.test('the leader is <Space>', function()
  T.eq(vim.g.mapleader, ' ')
end)

T.test('the floating terminal: <Esc> leaves terminal mode, a second one hides it', function()
  local terms = require('pure.terms')
  terms.toggleTerminal()
  local buf = vim.api.nvim_get_current_buf()
  T.eq(vim.bo[buf].buftype, 'terminal')
  local t = vim.fn.maparg('<Esc>', 't', false, true)
  T.eq(t.buffer, 1, '<Esc> in terminal mode, local to the terminal')
  T.eq(vim.fn.maparg('<Esc>', 'n', false, true).buffer, 1, 'the second <Esc> (normal mode)')
  T.eq(vim.fn.maparg('<A-Esc>', 't', false, true).buffer, 1, '<A-Esc> sends a real <Esc>')
  local win = vim.api.nvim_get_current_win()
  T.ok(vim.api.nvim_win_get_config(win).relative ~= '', 'a floating window')
  terms.toggleTerminal()
  T.ok(not vim.api.nvim_win_is_valid(win), 'the toggle closes it')
  pcall(vim.cmd, 'bwipeout! ' .. buf)
end)

T.test('a terminal running a command: <Esc><Esc> hides it', function()
  local terms = require('pure.terms')
  terms.toggleTerminal(vim.fn.has('win32') == 1 and 'cmd /c pause' or 'sleep 30')
  local buf = vim.api.nvim_get_current_buf()
  T.eq(vim.bo[buf].buftype, 'terminal')
  T.eq(vim.fn.maparg('<Esc><Esc>', 't', false, true).buffer, 1)
  T.eq(vim.tbl_isempty(vim.fn.maparg('<Esc>', 't', false, true)), true, 'a single <Esc> goes to the program')
  pcall(vim.cmd, 'bwipeout! ' .. buf)
end)
