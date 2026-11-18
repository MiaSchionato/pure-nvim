-- What the editing keys do (configs/keymaps.lua, pure/surround.lua, pure/pairs.lua, pure/lists.lua,
-- configs/functions.lua): each one typed in a buffer, as a person types it, and the text checked after.

--- A scratch buffer of `ft` holding `lines`, the cursor at (row, col) (1-based row, 0-based col).
--- A markdown buffer is a real file of the test's HOME (the lists work only in a file).
local function buffer(lines, row, col, ft)
  vim.cmd('silent! %bwipeout!')
  if ft == 'markdown' then
    local path = T.vault('scratch.md')
    vim.fn.writefile(lines, path)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  else
    vim.cmd('enew!')
    vim.bo.buftype = 'nofile'
    if ft then vim.bo.filetype = ft end
    -- The text is not an undo step: u in a test undoes what the test typed.
    local levels = vim.bo.undolevels
    vim.bo.undolevels = -1
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.undolevels = levels
  end
  vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
end

--- Type `keys` with the mappings on, as typed (<Esc>, <CR>... in <> notation).
local function type(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), 'mx', false)
end

local function text() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function cursor() return vim.api.nvim_win_get_cursor(0) end

-- ---------------------------------------------------------------------------
--  Motions and plain keys
-- ---------------------------------------------------------------------------
T.test('gl / gh: end of line, first non-blank', function()
  buffer({ '   hello world' }, 1, 5)
  type('gl') T.eq(cursor()[2], 13)
  type('gh') T.eq(cursor()[2], 3)
end)

T.test('ge: the last line', function()
  buffer({ 'a', 'b', 'c' }, 1, 0)
  type('ge') T.eq(cursor()[1], 3)
end)

T.test('Y yanks to the end of the line', function()
  buffer({ 'one two three' }, 1, 4)
  type('Y') T.eq(vim.fn.getreg('"'), 'two three')
end)

T.test('U is redo', function()
  buffer({ 'abc' }, 1, 0)
  type('x') T.eq(text(), { 'bc' })
  type('u') T.eq(text(), { 'abc' })
  type('U') T.eq(text(), { 'bc' })
end)

T.test('J joins and keeps the cursor where it was', function()
  buffer({ 'first line', 'second' }, 1, 3)
  type('J')
  T.eq(text(), { 'first line second' })
  T.eq(cursor(), { 1, 3 })
end)

T.test('vv selects the word', function()
  buffer({ 'one two three' }, 1, 5)
  type('vvy') T.eq(vim.fn.getreg('"'), 'two')
end)

T.test('[<Space> and ]<Space> add an empty line above / below', function()
  buffer({ 'x' }, 1, 0)
  type('[<Space>') T.eq(text(), { '', 'x' })
  buffer({ 'x' }, 1, 0)
  type(']<Space>') T.eq(text(), { 'x', '' })
end)

T.test('dd on an empty line does not overwrite the register', function()
  buffer({ 'keep me', '', 'end' }, 1, 0)
  type('yy')
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  type('dd')
  T.eq(text(), { 'keep me', 'end' })
  T.eq(vim.fn.getreg('"'), 'keep me\n')
  type('dd')
  T.eq(vim.fn.getreg('"'), 'end\n', 'a line with text is yanked as usual')
end)

T.test('visual > and < indent and keep the selection', function()
  buffer({ 'a', 'b' }, 1, 0)
  vim.bo.shiftwidth = 4
  type('Vj>>')
  T.eq(text(), { '        a', '        b' }, 'twice, the selection kept')
  type('<Esc>')
end)

T.test('visual J / K move 5 lines', function()
  buffer({ '1', '2', '3', '4', '5', '6', '7', '8' }, 1, 0)
  type('vJ') T.eq(cursor()[1], 6)
  type('K') T.eq(cursor()[1], 1)
  type('<Esc>')
end)

-- ---------------------------------------------------------------------------
--  Text objects
-- ---------------------------------------------------------------------------
T.test('ip / ap are parentheses, is / as square brackets, ic / ac curly brackets', function()
  buffer({ 'f(one, two)' }, 1, 4)
  type('dip') T.eq(text(), { 'f()' })
  buffer({ 'f(one, two)' }, 1, 4)
  type('dap') T.eq(text(), { 'f' })
  buffer({ 'x[1, 2]' }, 1, 3)
  type('dis') T.eq(text(), { 'x[]' })
  buffer({ 'x {a}' }, 1, 3)
  type('dac') T.eq(text(), { 'x ' })
  buffer({ 'x {a}' }, 1, 3)
  type('dic') T.eq(text(), { 'x {}' })
end)

T.test('iq picks the quotes around the cursor', function()
  buffer({ [[say "hello there" now]] }, 1, 8)
  type('diq') T.eq(text(), { [[say "" now]] })
  buffer({ [[it's 'single one' here]] }, 1, 10)
  type('diq') T.eq(text(), { [[it's '' here]] })
end)

-- ---------------------------------------------------------------------------
--  Surround (pure/surround.lua)
-- ---------------------------------------------------------------------------
T.test('s<char> surrounds the word; letters name the pairs', function()
  buffer({ 'say hello now' }, 1, 5)
  type('s(') T.eq(text(), { 'say (hello) now' })
  buffer({ 'say hello now' }, 1, 5)
  type('sq') T.eq(text(), { "say 'hello' now" })
  buffer({ 'say hello now' }, 1, 5)
  type('s*') T.eq(text(), { 'say *hello* now' })
end)

T.test('ds deletes the surrounding pair, cs changes it', function()
  buffer({ 'a (word) b' }, 1, 4)
  type('ds(') T.eq(text(), { 'a word b' })
  buffer({ 'a (word) b' }, 1, 4)
  type('cs([') T.eq(text(), { 'a [word] b' })
  buffer({ 'a "word" b' }, 1, 4)
  type([[cs"q]]) T.eq(text(), { "a 'word' b" })
end)

T.test('visual s surrounds the selection', function()
  buffer({ 'one two three' }, 1, 4)
  type('ves[') T.eq(text(), { 'one [two] three' })
end)

-- ---------------------------------------------------------------------------
--  Pairs (pure/pairs.lua)
-- ---------------------------------------------------------------------------
T.test('typing an opener closes it; typing the closer steps over it', function()
  buffer({ '' }, 1, 0)
  type('iif (x<Esc>') T.eq(text(), { 'if (x)' })
  buffer({ '' }, 1, 0)
  type('ia[ ]b<Esc>') T.eq(text(), { 'a[ ]b' }, 'no second ]')
  buffer({ '' }, 1, 0)
  type('ii"q"z<Esc>') T.eq(text(), { 'i"q"z' }, 'a quote steps over its pair')
end)

-- ---------------------------------------------------------------------------
--  Lists (pure/lists.lua) and checkboxes (configs/functions.lua)
-- ---------------------------------------------------------------------------
T.test('<CR> in a markdown list starts the next item; on an empty item it ends the list', function()
  buffer({ '- first' }, 1, 7, 'markdown')
  type('A<CR>second<Esc>') T.eq(text(), { '- first', '- second' })
  buffer({ '- [x] done' }, 1, 10, 'markdown')
  type('A<CR>next<Esc>') T.eq(text(), { '- [x] done', '- [ ] next' }, 'a checkbox, unchecked')
  buffer({ '3. three' }, 1, 8, 'markdown')
  type('A<CR>four<Esc>') T.eq(text(), { '3. three', '4. four' })
  -- An empty item (already in the note) ends the list. Typed in one go here (A, Enter, Enter), the second
  -- Enter made another item instead: whether that happens with keys typed by hand is not known yet.
  buffer({ '- item', '- ' }, 2, 2, 'markdown')
  type('A<CR>plain<Esc>') T.eq(text(), { '- item', 'plain' }, 'an empty item loses its marker')
end)

T.test('o in a markdown list starts the next item', function()
  buffer({ '  * nested' }, 1, 0, 'markdown')
  type('oafter<Esc>') T.eq(text(), { '  * nested', '  * after' })
end)

T.test('cycleCheckbox: [ ] > [~] > [!] > [>] > [-] > [x] > [ ]; a plain item gets a box', function()
  local f = require('configs.functions')
  buffer({ '- [ ] task' }, 1, 0, 'markdown')
  local seen = {}
  for _ = 1, 6 do
    f.cycleCheckbox()
    seen[#seen + 1] = vim.api.nvim_get_current_line()
  end
  T.eq(seen, { '- [~] task', '- [!] task', '- [>] task', '- [-] task', '- [x] task', '- [ ] task' })
  buffer({ '- plain' }, 1, 0, 'markdown')
  f.cycleCheckbox()
  T.eq(text(), { '- [ ] plain' })
  buffer({ 'not a list' }, 1, 0, 'markdown')
  f.cycleCheckbox()
  T.eq(text(), { 'not a list' })
end)

T.test('cycleCheckbox: only the box after the bullet changes', function()
  buffer({ '- [ ] keep [x] in the text' }, 1, 0, 'markdown')
  require('configs.functions').cycleCheckbox()
  T.eq(text(), { '- [~] keep [x] in the text' })
end)

T.test('toggleCheckbox: [ ] <> [x]; the other states go to [x]', function()
  local f = require('configs.functions')
  buffer({ '- [ ] a' }, 1, 0, 'markdown')
  f.toggleCheckbox() T.eq(text(), { '- [x] a' })
  f.toggleCheckbox() T.eq(text(), { '- [ ] a' })
  buffer({ '- [>] a' }, 1, 0, 'markdown')
  f.toggleCheckbox() T.eq(text(), { '- [x] a' })
end)

-- A plain item of the selection takes that state too (the comment of cycleCheckboxRange says an empty box:
-- the code, which makes every line of the selection the same, is what is tested).
T.test('cycleCheckboxRange: every item of the selection takes the state after the first one', function()
  buffer({ '- [ ] a', 'text', '- [x] b', '- c' }, 1, 0, 'markdown')
  type('V3j')
  require('configs.functions').cycleCheckboxRange()
  type('<Esc>')
  T.eq(text(), { '- [~] a', 'text', '- [~] b', '- [~] c' })
end)

T.test('<leader>x cycles the checkbox in a markdown note', function()
  local path = T.vault('note.md')
  vim.fn.writefile({ '- [ ] task' }, path)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  type(' x')
  T.eq(text(), { '- [~] task' })
end)

-- ---------------------------------------------------------------------------
--  Folds of tasks (pure/folding.lua)
-- ---------------------------------------------------------------------------
T.test('zt folds the done tasks, zT the open ones', function()
  local path = T.vault('tasks.md')
  vim.fn.writefile({ '# Tasks', '- [x] done one', '- [ ] open one', '- [-] cancelled', '- [ ] open two' }, path)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  type('zt')
  T.ok(vim.fn.foldclosed(2) ~= -1, 'the done task is folded')
  T.eq(vim.fn.foldclosed(3), -1, 'the open task is not')
  type('zT')
  T.ok(vim.fn.foldclosed(3) ~= -1, 'now the open task is folded')
end)
