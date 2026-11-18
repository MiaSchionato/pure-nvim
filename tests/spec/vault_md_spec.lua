-- pure/vault/md.lua through pure/vault.lua, on tests/fixtures/vault-md: the garden in Markdown (grow, compost,
-- the state menu, move), the links that follow a moved heading, the id:: lines (never lost, never copied), the
-- checkbox dates of the Tasks plugin, the captures, find.
local vault = require('pure.vault')
local md = require('pure.vault.md')
local MD = 'vault-md'

local function read(rel) return T.read(rel, MD) end
local function has(lines, text)
  for _, l in ipairs(lines) do if l:find(text, 1, true) then return true end end
  return false
end
local function row(rel, text)
  for i, l in ipairs(read(rel)) do if l:find(text, 1, true) then return i end end
  error('no line of ' .. rel .. ' holds ' .. text, 2)
end
local function edit(rel, text) T.edit(rel, text and row(rel, text) or 1, MD) end

--- Every id:: line of the vault: { id = count }.
local function ids()
  local out = {}
  for _, f in ipairs(md.files(T.vault(nil, MD))) do
    for _, l in ipairs(vim.fn.readfile(f.path)) do
      local id = l:match('^id::%s*(%w+)%s*$')
      if id then out[id] = (out[id] or 0) + 1 end
    end
  end
  return out
end
local IDS = { ['1a2b3c'] = 1, ['4d5e6f'] = 1, ['7a8b9c'] = 1 }

-- ---------------------------------------------------------------------------
--  Reading a note
-- ---------------------------------------------------------------------------
T.test('headings and sections: front matter and code fences are not headings', function()
  local lines = { '---', 'aliases:', '  - "x"', '---', '# One', '```', '# not a heading', '```', '## Two', 'text', '# Three' }
  local hs = md.headings(lines)
  T.eq(vim.tbl_map(function(h) return h.title end, hs), { 'One', 'Two', 'Three' })
  local sec = md.section(lines, 10)
  T.eq({ sec.title, sec.line, sec.last }, { 'Two', 9, 10 })
  sec = md.section(lines, 6)
  T.eq({ sec.title, sec.last }, { 'One', 10 }, 'a section holds its children')
  T.eq(md.section(lines, 2), nil, 'above the first heading')
end)

T.test('stateOf / withState: the state tag, the other tags, the properties untouched', function()
  local lines = { '# Idea', '#seed #B #Devaneios', 'created:: 2026-11-18', 'id:: 3f9a2c', 'Body.' }
  local sec = md.section(lines, 1)
  T.eq(md.stateOf(lines, sec), 'seed')
  T.eq(md.withState(lines, sec, 'sprout'), { '# Idea', '#sprout #B #Devaneios', 'created:: 2026-11-18', 'id:: 3f9a2c', 'Body.' })
  T.eq(md.withState(lines, sec, nil), { '# Idea', '#B #Devaneios', 'created:: 2026-11-18', 'id:: 3f9a2c', 'Body.' })
  local bare = { '# Idea', 'id:: 3f9a2c' }
  T.eq(md.stateOf(bare, md.section(bare, 1)), nil)
  T.eq(md.withState(bare, md.section(bare, 1), 'seed'), { '# Idea', '#seed', 'id:: 3f9a2c' }, 'a tag line is made')
  local only = { '# Idea', '#seed', 'x' }
  T.eq(md.withState(only, md.section(only, 1), nil), { '# Idea', 'x' }, 'an empty tag line goes')
end)

T.test('compareKey: headings compared as Obsidian does', function()
  T.eq(md.compareKey('A sprout: to grow!'), md.compareKey('a SPROUT to   grow'))
  T.ok(md.compareKey('One') ~= md.compareKey('Two'))
end)

-- ---------------------------------------------------------------------------
--  Grow (<leader>vn)
-- ---------------------------------------------------------------------------
T.test('grow: a seed of the inbox becomes a sprout of the nursery, with its child, id:: once, links follow', function()
  edit('inbox.md', '# First seed')
  vault.grow()
  T.ok(not has(read('inbox.md'), 'First seed'), 'gone from the inbox')
  local nursery = read('garden/nursery.md')
  local at = row('garden/nursery.md', '# First seed')
  T.eq(nursery[at + 1], '#sprout #tag', 'the state, the other tag kept')
  T.ok(has(nursery, '## A child of the first seed'), 'the child came along')
  T.eq(ids(), IDS, 'every id:: once')
  T.ok(has(read('garden/old_plant.md'), '[[nursery#First seed|First seed]]'), 'the link follows the heading')
  T.match(T.lastMessage(), '1 link updated')
end)

T.test('grow: a sprout becomes a plant in a note of its own; the links to it follow', function()
  edit('garden/nursery.md', '# A sprout to grow')
  vault.grow()
  T.ok(T.exists('garden/a_sprout_to_grow.md', MD), 'its own note')
  local own = read('garden/a_sprout_to_grow.md')
  T.eq({ own[1], own[2] }, { '# A sprout to grow', '#plant #idea' })
  T.ok(has(own, '## Connections'), 'its children came along')
  T.ok(not has(read('garden/nursery.md'), 'A sprout to grow'), 'gone from the nursery')
  T.ok(has(read('inbox.md'), '[[a_sprout_to_grow#A sprout to grow|the sprout]]'), 'the link of the inbox follows')
  T.eq(ids(), IDS)
end)

T.test('grow: a plant becomes a tree in place, the rest of the section untouched', function()
  local before = read('garden/old_plant.md')
  edit('garden/old_plant.md', '# Old plant')
  vault.grow()
  local after = read('garden/old_plant.md')
  T.eq(after[row('garden/old_plant.md', '# Old plant') + 1], '#tree')
  T.eq(#after, #before)
  T.ok(has(after, 'id:: 7a8b9c'))
end)

T.test('grow: a tree is the top; a fruit is not on the ladder; no state is no idea', function()
  T.write('garden/tall.md', { '# Tall', '#tree' }, MD)
  edit('garden/tall.md', '# Tall')
  vault.grow()
  T.match(T.lastMessage(), 'Already a tree')
  T.write('garden/ripe.md', { '# Ripe', '#fruit' }, MD)
  edit('garden/ripe.md', '# Ripe')
  vault.grow()
  T.match(T.lastMessage(), 'not on the ladder')
  edit('inbox.md', '# Book with a type')
  vault.grow()
  T.match(T.lastMessage(), 'not an idea heading')
end)

T.test('grow: a heading of level 2 lands at the top level', function()
  T.write('inbox.md', { '# Parent', '## Deep seed', '#seed', '### Its child' }, MD)
  edit('inbox.md', '## Deep seed')
  vault.grow()
  local nursery = read('garden/nursery.md')
  T.ok(has(nursery, '# Deep seed'), 'level 1')
  T.ok(has(nursery, '## Its child'), 'the child one level up too')
  T.eq(read('inbox.md'), { '# Parent' })
end)

-- ---------------------------------------------------------------------------
--  Compost (<leader>vc)
-- ---------------------------------------------------------------------------
T.test('compost: No changes nothing; a seed goes to archive/compost.md', function()
  local before = read('inbox.md')
  edit('inbox.md', '# Second seed')
  T.answers({ confirm = 2 })
  vault.compost()
  T.eq(read('inbox.md'), before)
  T.answers({ confirm = 1 })
  vault.compost()
  local compost = read('archive/compost.md')
  T.eq(compost[row('archive/compost.md', '# Second seed') + 1], '#compost')
  T.ok(has(compost, '# An idea let go of'), 'what was there stays')
  T.ok(not has(read('inbox.md'), 'Second seed'))
end)

T.test('compost: a plant stays in its note, only #compost', function()
  edit('garden/old_plant.md', '# Old plant')
  T.answers({ confirm = 1 })
  vault.compost()
  local plant = read('garden/old_plant.md')
  T.eq(plant[row('garden/old_plant.md', '# Old plant') + 1], '#compost')
  T.ok(has(plant, 'id:: 7a8b9c'), 'its id stays')
  T.ok(not has(read('archive/compost.md'), 'Old plant'))
  T.eq(ids(), IDS)
end)

-- ---------------------------------------------------------------------------
--  The state menu (<leader>vt)
-- ---------------------------------------------------------------------------
T.test('state menu on a heading: the garden states and "no state"', function()
  local offered
  T.answers({ select = function(items) offered = items return items[2] end })
  edit('inbox.md', '# First seed')
  vault.todoState()
  T.eq(offered, { '• SEED', 'SPROUT', 'PLANT', 'TREE', 'FRUIT', 'COMPOST', 'no state' })
  T.eq(read('inbox.md')[row('inbox.md', '# First seed') + 1], '#sprout #tag')
  T.answers({ select = function(items) return items[#items] end })
  edit('inbox.md', '# First seed')
  vault.todoState()
  T.eq(read('inbox.md')[row('inbox.md', '# First seed') + 1], '#tag', 'no state: the other tags stay')
  T.eq(ids(), IDS)
end)

T.test('state menu on a checkbox: the six task states, with the Tasks dates', function()
  local offered
  T.answers({ select = function(items) offered = items return items[6] end })
  edit('tasks.md', 'Write the report')
  vault.todoState()
  T.eq(offered, { '• TODO', 'IN PROGRESS', 'IMPORTANT', 'DEFERRED', 'CANCELLED', 'DONE' })
  T.eq(vim.api.nvim_get_current_line(), '- [x] Write the report ⏳ 2026-11-20 ✅ ' .. os.date('%Y-%m-%d'))
end)

-- ---------------------------------------------------------------------------
--  Move (<leader>vm)
-- ---------------------------------------------------------------------------
T.test('move: a heading with a type:: of sources/ goes to that note', function()
  edit('inbox.md', '# Book with a type')
  vault.move()
  T.ok(has(read('sources/books.md'), '# Book with a type'))
  T.ok(has(read('sources/books.md'), 'author:: Someone'))
  T.ok(not has(read('inbox.md'), 'Book with a type'))
end)

T.test('move: without a type, the note picked in the list; links follow; cancel changes nothing', function()
  local before = read('inbox.md')
  T.answers({ select = nil })
  edit('inbox.md', '# First seed')
  vault.move()
  T.eq(read('inbox.md'), before)
  local offered
  T.answers({ select = function(items) offered = items return 'garden/hubs.md' end })
  vault.move()
  T.ok(not vim.tbl_contains(offered, 'inbox.md'), 'not the note itself')
  T.ok(has(read('garden/hubs.md'), '# First seed'))
  T.ok(has(read('garden/old_plant.md'), '[[hubs#First seed|First seed]]'))
  T.eq(ids(), IDS)
end)

-- ---------------------------------------------------------------------------
--  Checkbox dates (the Tasks plugin)
-- ---------------------------------------------------------------------------
T.test('taskLine: ✅ on done, ❌ on cancelled, taken away when leaving; before a ^block id', function()
  local d = '2026-11-18'
  T.eq(md.taskLine('- [ ] a ⏳ 2026-11-20', 'x', d), '- [x] a ⏳ 2026-11-20 ✅ 2026-11-18')
  T.eq(md.taskLine('- [x] a ✅ 2026-11-10', ' ', d), '- [ ] a')
  T.eq(md.taskLine('- [-] a ❌ 2026-11-10', 'x', d), '- [x] a ✅ 2026-11-18', 'cancelled > done: the date changes')
  T.eq(md.taskLine('- [x] a ✅ 2026-11-10', '-', d), '- [-] a ❌ 2026-11-18')
  T.eq(md.taskLine('- [ ] linked ^t1a2b3c4', 'x', d), '- [x] linked ✅ 2026-11-18 ^t1a2b3c4')
  T.eq(md.taskLine('  * [~] nested', '!', d), '  * [!] nested')
  T.eq(md.taskLine('1. [ ] numbered', 'x', d), '1. [x] numbered ✅ 2026-11-18')
  T.eq(md.taskLine('not a task', 'x', d), nil)
end)

T.test('<leader>x in a note of the Markdown vault writes the dates; [-] > [x] > [ ] as the Tasks plugin', function()
  T.write('tasks.md', { '- [>] item' }, MD)
  edit('tasks.md')
  local f = require('configs.functions')
  local today = os.date('%Y-%m-%d')
  f.cycleCheckbox() T.eq(vim.api.nvim_get_current_line(), '- [-] item ❌ ' .. today)
  f.cycleCheckbox() T.eq(vim.api.nvim_get_current_line(), '- [x] item ✅ ' .. today)
  f.cycleCheckbox() T.eq(vim.api.nvim_get_current_line(), '- [ ] item')
end)

T.test('outside a Markdown vault the checkbox keys write no date', function()
  local path = T.vault('plain.md')
  vim.fn.writefile({ '- [-] item' }, path)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  require('configs.functions').cycleCheckbox()
  T.eq(vim.api.nvim_get_current_line(), '- [x] item')
end)

-- ---------------------------------------------------------------------------
--  Captures (<leader>vq)
-- ---------------------------------------------------------------------------
T.test('readDate: words, Portuguese and Italian, +3d, weekdays, a date, a time', function()
  local now = os.time({ year = 2026, month = 11, day = 18, hour = 10 }) -- a Wednesday
  T.eq(md.readDate('today', now), '2026-11-18')
  T.eq(md.readDate('amanhã', now), '2026-11-19')
  T.eq(md.readDate('domani', now), '2026-11-19')
  T.eq(md.readDate('+3d', now), '2026-11-21')
  T.eq(md.readDate('+2w', now), '2026-12-02')
  T.eq(md.readDate('fri', now), '2026-11-20')
  T.eq(md.readDate('wednesday', now), '2026-11-18', 'today included')
  T.eq(md.readDate('2026-12-5', now), '2026-12-05')
  T.eq({ md.readDate('tomorrow 9:30', now) }, { '2026-11-19', '09:30' })
  T.eq(md.readDate('someday', now), nil)
end)

T.test('capture node: no type is a seed of the inbox; empty properties dropped; created:: added', function()
  T.ok(md.store('node', { '# A new idea', 'type:: ', 'author:: ', '', 'Its body.' }))
  local inbox = read('inbox.md')
  local at = row('inbox.md', '# A new idea')
  T.eq(inbox[at + 1], '#seed')
  T.match(inbox[at + 2], '^created:: %d%d%d%d%-%d%d%-%d%d %d%d:%d%d$')
  T.eq(inbox[at + 3], '', 'no empty property (author:: left out)')
  T.eq(inbox[at + 4], 'Its body.')
end)

T.test('capture node: garden types and source notes', function()
  md.store('node', { '# Young', 'type:: sprout' })
  T.ok(has(read('garden/nursery.md'), '# Young'))
  md.store('node', { '# Big one', 'type:: plant' })
  T.ok(T.exists('garden/big_one.md', MD))
  T.eq(read('garden/big_one.md')[2], '#plant')
  md.store('node', { '# Dropped', 'type:: compost' })
  T.ok(has(read('archive/compost.md'), '# Dropped'))
  md.store('node', { '# A novel', 'type:: Books', 'author:: Someone' })
  local books = read('sources/books.md')
  T.ok(has(books, '# A novel') and has(books, 'type:: Books'), 'the type kept in a source note')
  md.store('node', { '# A film', 'type:: films' })
  T.ok(has(read('inbox.md'), '# A film'), 'a type with no note: the inbox')
  T.match(T.lastMessage(), 'Captured')
end)

T.test('capture task: a checkbox of the Tasks plugin, dates in words, a time on its own line', function()
  T.ok(md.store('task', { '# Call the bank', 'scheduled:: tomorrow 10:00', '', 'Ask about the card.' }))
  local tasks = read('tasks.md')
  local tomorrow = os.date('%Y-%m-%d', os.time() + 86400)
  local at = row('tasks.md', 'Call the bank')
  T.eq(tasks[at], '- [ ] Call the bank ➕ ' .. os.date('%Y-%m-%d') .. ' ⏳ ' .. tomorrow)
  T.eq(tasks[at + 1], '  scheduled:: ' .. tomorrow .. ' 10:00')
  T.eq(tasks[at + 2], '  Ask about the card.')
  T.ok(not has(tasks, '#todo'), 'no tag: tasks are checkboxes')
end)

T.test('capture task: an empty scheduled is no date; a deadline must be filled; a date that cannot be read keeps it open', function()
  T.ok(md.store('task', { '# Plain task', 'scheduled:: ' }))
  T.eq(read('tasks.md')[row('tasks.md', 'Plain task')], '- [ ] Plain task ➕ ' .. os.date('%Y-%m-%d'))
  T.eq(md.store('deadline', { '# Due', 'deadline:: ' }), false)
  T.match(T.lastMessage(), 'deadline is empty')
  T.eq(md.store('task', { '# Odd', 'scheduled:: someday' }), false)
  T.ok(md.store('deadline', { '# Due', 'deadline:: 2026-12-01' }))
  T.match(read('tasks.md')[row('tasks.md', 'Due')], '📅 2026%-12%-01$')
end)

T.test('capture link and an empty draft', function()
  T.ok(md.store('link', { '# [The page](https://x.org/a b)' }))
  T.ok(has(read('inbox.md'), '# [The page](<https://x.org/a b>)'), 'an address with spaces inside < >')
  local before = read('inbox.md')
  T.ok(md.store('node', { '# ', 'type:: ', 'author:: ' }))
  T.eq(read('inbox.md'), before, 'nothing written: nothing stored')
end)

T.test('capture journal: the day, month and year made when missing, in date order', function()
  local now = os.time({ year = 2026, month = 11, day = 18, hour = 10 })
  local lines = { '# 2026', '', '## 2026-11 November', '', '### 2026-11-17 Tuesday', '', '#### 22:57 A line.' }
  local out = md.journalInsert(lines, { '#### 10:00 Today.' }, now)
  T.eq(out, { '# 2026', '', '## 2026-11 November', '', '### 2026-11-17 Tuesday', '', '#### 22:57 A line.', '',
    '### 2026-11-18 Wednesday', '#### 10:00 Today.' })
  out = md.journalInsert(out, { '#### 11:00 Later.' }, now)
  -- One empty line between the entries of a day, as the journal is written.
  T.eq({ out[#out - 2], out[#out - 1], out[#out] }, { '#### 10:00 Today.', '', '#### 11:00 Later.' }, 'at the end of its day')
  local earlier = md.journalInsert({ '# 2026', '', '## 2026-12 December' }, { '#### x' }, now)
  -- As the vault's capture.js writes it: no empty line between a new heading and its parent.
  T.eq(earlier, { '# 2026', '', '## 2026-11 November', '### 2026-11-18 Wednesday', '#### x', '## 2026-12 December' })
end)

T.test('capture window: :w stores the draft and closes it', function()
  local buf, win = md.openCapture('node')
  vim.cmd('stopinsert')
  T.eq(vim.api.nvim_buf_get_lines(buf, 0, 2, false), { '# ', 'type:: ' })
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# From the window' })
  vim.cmd('write')
  T.ok(not vim.api.nvim_win_is_valid(win), 'closed')
  T.ok(has(read('inbox.md'), '# From the window'))
end)

T.test('the capture menu of the Markdown vault offers the five captures', function()
  local offered
  T.answers({ select = function(items) offered = items return nil end })
  edit('inbox.md')
  vault.capture()
  T.eq(#offered, 5)
  T.match(offered[1], '^n')
end)

-- ---------------------------------------------------------------------------
--  Find, a new seed, the journal, read-only
-- ---------------------------------------------------------------------------
T.test('find: a note is its file name; aliases of the front matter; headings', function()
  local by = {}
  for _, e in ipairs(vault._find.entries(vim.fs.normalize(T.vault(nil, MD)))) do by[e.kind .. ':' .. e.title] = e end
  T.ok(by['note:old_plant'], 'the file name')
  T.ok(by['alias:Ancient plant'], 'the front matter alias')
  T.eq(by['alias:Ancient plant'].target, 'old_plant')
  T.ok(by['heading:First seed'], 'a heading')
  T.ok(not by['heading:not a heading'], 'not inside a fence')
  T.ok(by['note:compost'].archive, 'archive/ marked')
end)

T.test('find: a new title is a seed of the Markdown inbox', function()
  edit('garden/nursery.md')
  vault._find.newSeed('Brand new')
  local inbox = read('inbox.md')
  local at = row('inbox.md', '# Brand new')
  T.eq(inbox[at + 1], '#seed')
  T.match(vim.api.nvim_buf_get_name(0), 'vault%-md/inbox%.md$')
end)

T.test('journalToday: today\'s heading, made when missing', function()
  edit('inbox.md')
  vault.journalToday()
  T.match(vim.api.nvim_buf_get_name(0), 'journal%.md$')
  T.eq(vim.api.nvim_get_current_line():sub(1, 14), '### ' .. os.date('%Y-%m-%d'))
end)

T.test('a read-only Markdown vault refuses grow, compost and captures', function()
  local saved = vim.g.pure_vaults
  local v = vim.deepcopy(saved)
  v.md.readonly = true
  vim.g.pure_vaults = v
  local before = read('inbox.md')
  edit('inbox.md', '# First seed')
  vault.grow()
  T.match(T.lastMessage(), 'read%-only')
  vault.capture()
  vault.newSeed()
  vim.g.pure_vaults = saved
  T.eq(read('inbox.md'), before)
end)
