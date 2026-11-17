-- pure/vault.lua on an org vault (tests/fixtures/vault-org): what <leader>v does, checked on the files.
local vault = require('pure.vault')

local function has(lines, pattern)
  for _, l in ipairs(lines) do if l:find(pattern) then return true end end
  return false
end

local function count(lines, pattern)
  local n = 0
  for _, l in ipairs(lines) do if l:find(pattern) then n = n + 1 end end
  return n
end

-- ---------------------------------------------------------------------------
--  Settings and paths
-- ---------------------------------------------------------------------------
T.test('notes: defaults, inbox, and a setting that overrides one', function()
  T.eq(vault.inbox(), 'inbox.org')
  T.eq(vault.note('inbox'), 'inbox.org')
  T.eq(vault.note('nursery'), 'garden/nursery.org')
  T.eq(vault.note('tasks'), 'tasks.org')
  T.eq(vault.note('books'), 'sources/books.org')
  T.eq(vault.note('nope'), nil)
  vim.g.pure_vault_notes = { nursery = 'garden/other.org' }
  T.eq(vault.nursery(), 'garden/other.org')
  T.eq(vault.note('tasks'), 'tasks.org', 'a name left out keeps its default')
  vim.g.pure_vault_notes = nil
end)

T.test('path: nil with a warning when the folder is missing', function()
  local saved = vim.g.pure_vault
  vim.g.pure_vault = T.vault('nowhere')
  T.eq(vault.path(), nil)
  T.match(T.lastMessage(), 'folder not found')
  vim.g.pure_vault = saved
  T.eq(vault.path(), vim.fs.normalize(T.vault()))
end)

T.test('sourceFile: the note of sources/ by type, any case', function()
  T.eq(vault.sourceFile('books'), 'sources/books.org')
  T.eq(vault.sourceFile('BOOKS'), 'sources/books.org')
  T.eq(vault.sourceFile(' Books '), 'sources/books.org')
  T.eq(vault.sourceFile('films'), nil)
  T.eq(vault.sourceFile(''), nil)
  T.eq(vault.sourceFile(nil), nil)
end)

-- ---------------------------------------------------------------------------
--  Find (<leader>vf)
-- ---------------------------------------------------------------------------
T.test('find: notes before headings, aliases, archive last', function()
  local entries = vault._find.entries(vim.fs.normalize(T.vault()))
  local kinds, firstHeading, lastNote, archiveAt = {}, nil, nil, nil
  for i, e in ipairs(entries) do
    kinds[e.kind] = (kinds[e.kind] or 0) + 1
    if e.kind == 'heading' and not e.archive and not firstHeading then firstHeading = i end
    if (e.kind == 'note' or (e.kind == 'alias' and not e.heading)) and not e.archive then lastNote = i end
    if e.archive and not archiveAt then archiveAt = i end
  end
  T.ok(kinds.note >= 6, 'every file is a note entry')
  T.ok(kinds.heading >= 6, 'headings are entries')
  T.ok(lastNote < firstHeading, 'every note comes before the first heading')
  for i = archiveAt, #entries do T.ok(entries[i].archive, 'archive/ is last: entry ' .. i) end
  local alias
  for _, e in ipairs(entries) do if e.kind == 'alias' and e.title == 'Ancient plant' then alias = e end end
  T.ok(alias, 'the :ROAM_ALIASES: of a heading is an entry')
  T.eq(alias.target, 'Old plant')
end)

T.test('find: a heading entry drops its state, priority and tags', function()
  local titles = {}
  for _, e in ipairs(vault._find.entries(vim.fs.normalize(T.vault()))) do
    if e.kind == 'heading' then titles[e.title] = e end
  end
  T.ok(titles['First seed'], 'SEED and :tag: are left out of the title')
  T.eq(titles['First seed'].lnum, T.row('inbox.org', '^%* SEED First seed'))
  T.ok(titles['A sprout to grow'], 'SPROUT and :idea: left out')
end)

T.test('find: a line carries the file and the row after tabs', function()
  local e = vault._find.entries(vim.fs.normalize(T.vault()))[1]
  local line = vault._find.line(e)
  local file, lnum = line:match('\t([^\t]+)\t(%d+)%s*$')
  T.eq(file, e.file)
  T.eq(tonumber(lnum), e.lnum)
end)

T.test('find: a new title makes a seed at the end of the inbox', function()
  vault._find.newSeed('A brand new idea')
  local lines = T.read('inbox.org')
  local at = T.row('inbox.org', '^%* SEED A brand new idea$')
  T.match(lines[at + 1], '^:PROPERTIES:$')
  T.match(lines[at + 2], '^:CREATED:  %[%d%d%d%d%-%d%d%-%d%d %a+ %d%d:%d%d%]$')
  T.match(lines[at + 3], '^:END:$')
  T.eq(lines[at - 1], '', 'an empty line before it')
  T.match(vim.api.nvim_buf_get_name(0), 'inbox%.org$')
  T.eq(vim.api.nvim_win_get_cursor(0)[1], at)
end)

-- ---------------------------------------------------------------------------
--  Grow (<leader>vn)
-- ---------------------------------------------------------------------------
T.test('grow: a seed of the inbox becomes a sprout of the nursery, with its subtree and ID', function()
  T.edit('inbox.org', T.row('inbox.org', '^%* SEED First seed'))
  vault.grow()
  local inbox, nursery = T.read('inbox.org'), T.read('garden/nursery.org')
  T.ok(not has(inbox, 'First seed'), 'gone from the inbox')
  T.ok(has(nursery, '^%* SPROUT First seed'), 'a SPROUT in the nursery')
  T.ok(has(nursery, '^%*%* A child of the first seed'), 'the child came along')
  T.eq(count(nursery, 'aaaaaaaa%-0000%-4000%-8000%-000000000011'), 1, 'the :ID: once')
  T.ok(has(nursery, 'Body of the first seed%.'), 'the body came along')
  T.ok(has(inbox, '^%* SEED Second seed'), 'the other seed stays')
end)

T.test('grow: a sprout becomes a plant in a note of its own in garden/', function()
  T.edit('garden/nursery.org', T.row('garden/nursery.org', '^%* SPROUT'))
  vault.grow()
  T.ok(not has(T.read('garden/nursery.org'), 'A sprout to grow'), 'gone from the nursery')
  T.ok(T.exists('garden/a_sprout_to_grow.org'), 'garden/a_sprout_to_grow.org made')
  local own = T.read('garden/a_sprout_to_grow.org')
  T.eq(own[1], '#+title: A sprout to grow')
  T.ok(has(own, '^#%+TODO: SEED'), 'the garden keywords')
  T.ok(has(own, '^#%+TODO: TODO'), 'the task keywords')
  T.ok(has(own, '^%* PLANT A sprout to grow'), 'a PLANT')
  T.eq(count(own, 'aaaaaaaa%-0000%-4000%-8000%-000000000021'), 1, 'the :ID: once')
end)

T.test('grow: a taken name gets _2', function()
  T.write('garden/a_sprout_to_grow.org', { '#+title: Taken' })
  T.edit('garden/nursery.org', T.row('garden/nursery.org', '^%* SPROUT'))
  vault.grow()
  T.ok(T.exists('garden/a_sprout_to_grow_2.org'), 'the _2 note')
  T.eq(T.read('garden/a_sprout_to_grow.org'), { '#+title: Taken' }, 'the other note untouched')
end)

T.test('grow: a plant becomes a tree in the same note', function()
  T.edit('garden/old_plant.org', T.row('garden/old_plant.org', '^%* PLANT'))
  vault.grow()
  T.ok(has(T.read('garden/old_plant.org'), '^%* TREE Old plant'), 'TREE, same file')
end)

T.test('grow: a tree is the top of the ladder; a seed outside the inbox stays where it is', function()
  T.write('garden/tall.org', { '#+title: Tall', '#+TODO: SEED SPROUT PLANT TREE FRUIT | COMPOST', '', '* TREE Tall' })
  T.edit('garden/tall.org', 4)
  vault.grow()
  T.match(T.lastMessage(), 'Already a TREE')
  T.write('garden/loose.org', { '#+title: Loose', '#+TODO: SEED SPROUT PLANT TREE FRUIT | COMPOST', '', '* SEED Loose' })
  T.edit('garden/loose.org', 4)
  vault.grow()
  T.ok(has(T.read('garden/loose.org'), '^%* SPROUT Loose'), 'a SPROUT, in place')
end)

T.test('grow: a task or a plain heading is not an idea', function()
  T.edit('tasks.org', T.row('tasks.org', '^%* TODO'))
  vault.grow()
  T.match(T.lastMessage(), 'not on the ladder')
  T.edit('sources/books.org', T.row('sources/books.org', '^%* A book'))
  vault.grow()
  T.match(T.lastMessage(), 'not an idea heading')
end)

T.test('grow: outside the vault, a warning and nothing changes', function()
  local outside = vim.fn.tempname() .. '.org'
  vim.fn.writefile({ '* SEED Outside' }, outside)
  vim.cmd('edit ' .. vim.fn.fnameescape(outside))
  vault.grow()
  T.match(T.lastMessage(), 'not a note of the vault')
  T.eq(vim.fn.readfile(outside), { '* SEED Outside' })
end)

-- ---------------------------------------------------------------------------
--  Compost (<leader>vc)
-- ---------------------------------------------------------------------------
T.test('compost: asks first; No changes nothing', function()
  local before = T.read('inbox.org')
  T.edit('inbox.org', T.row('inbox.org', '^%* SEED Second seed'))
  T.answers({ confirm = 2 })
  vault.compost()
  T.eq(T.read('inbox.org'), before)
end)

T.test('compost: Yes makes it COMPOST and moves it to archive/compost.org', function()
  T.edit('inbox.org', T.row('inbox.org', '^%* SEED First seed'))
  T.answers({ confirm = 1 })
  vault.compost()
  local compost = T.read('archive/compost.org')
  T.ok(not has(T.read('inbox.org'), 'First seed'), 'gone from the inbox')
  T.ok(has(compost, '^%* COMPOST First seed'), 'COMPOST in the compost')
  T.ok(has(compost, '^%* COMPOST An idea let go of'), 'what was there stays')
  T.eq(count(compost, 'aaaaaaaa%-0000%-4000%-8000%-000000000011'), 1, 'the :ID: once')
end)

T.test('compost: archive/compost.org is made when missing', function()
  vim.fn.delete(T.vault('archive/compost.org'))
  T.edit('inbox.org', T.row('inbox.org', '^%* SEED Second seed'))
  T.answers({ confirm = 1 })
  vault.compost()
  local compost = T.read('archive/compost.org')
  T.eq(compost[1], '#+title: Compost')
  T.ok(has(compost, '^%* COMPOST Second seed'))
end)

-- ---------------------------------------------------------------------------
--  Move (<leader>vm)
-- ---------------------------------------------------------------------------
T.test('move: a heading with a :TYPE: of sources/ goes to that note', function()
  T.edit('inbox.org', T.row('inbox.org', '^%* Book with a type'))
  vault.move()
  T.ok(not has(T.read('inbox.org'), 'Book with a type'), 'gone from the inbox')
  local books = T.read('sources/books.org')
  T.ok(has(books, '^%* Book with a type'), 'in sources/books.org')
  T.ok(has(books, ':AUTHOR:%s+Someone'), 'its properties came along')
end)

T.test('move: without a type, the note picked in the list', function()
  local offered
  T.answers({ select = function(items) offered = items return 'tasks.org' end })
  T.edit('inbox.org', T.row('inbox.org', '^%* SEED Second seed'))
  vault.move()
  T.ok(vim.tbl_contains(offered, 'garden/nursery.org'), 'other notes offered')
  T.ok(not vim.tbl_contains(offered, 'inbox.org'), 'not the note itself')
  T.ok(has(T.read('tasks.org'), 'Second seed'), 'moved to tasks.org')
  T.ok(not has(T.read('inbox.org'), 'Second seed'), 'gone from the inbox')
end)

T.test('move: cancelling the list changes nothing', function()
  local before = T.read('inbox.org')
  T.answers({ select = nil })
  T.edit('inbox.org', T.row('inbox.org', '^%* SEED Second seed'))
  vault.move()
  T.eq(T.read('inbox.org'), before)
end)

-- ---------------------------------------------------------------------------
--  The node capture's routing (routeNode, the store filter of plugins/org.lua)
-- ---------------------------------------------------------------------------
local function node(type, extra)
  local lines = { '* My entry', ':PROPERTIES:' }
  if type then lines[#lines + 1] = ':TYPE:     ' .. type end
  vim.list_extend(lines, extra or { ':AUTHOR:   ', ':CREATED:  [2026-11-18 Wed 10:00]' })
  lines[#lines + 1] = ':END:'
  return lines
end

T.test('routeNode: no type is a SEED of the inbox, empty properties dropped', function()
  local out, rel = vault.routeNode(node(nil))
  T.eq(rel, nil)
  T.eq(out, { '* SEED My entry', ':PROPERTIES:', ':CREATED:  [2026-11-18 Wed 10:00]', ':END:' })
end)

T.test('routeNode: garden types get their state and place, TYPE dropped', function()
  local out, rel = vault.routeNode(node('seed'))
  T.eq(rel, nil); T.eq(out[1], '* SEED My entry'); T.ok(not has(out, ':TYPE:'))
  out, rel = vault.routeNode(node('Sprout'))
  T.eq(rel, 'garden/nursery.org'); T.eq(out[1], '* SPROUT My entry')
  out, rel = vault.routeNode(node('compost'))
  T.eq(rel, 'archive/compost.org'); T.eq(out[1], '* COMPOST My entry')
  out, rel = vault.routeNode(node('PLANT'))
  T.eq(rel, 'garden/my_entry.org'); T.eq(out[1], '* PLANT My entry')
  T.ok(T.exists('garden/my_entry.org'), 'the own note is made')
  T.eq(T.read('garden/my_entry.org')[1], '#+title: My entry')
end)

T.test('routeNode: a type of sources/ keeps TYPE and goes there', function()
  local out, rel = vault.routeNode(node('books'))
  T.eq(rel, 'sources/books.org')
  T.eq(out[1], '* My entry', 'no state')
  T.ok(has(out, ':TYPE:%s+books'))
end)

T.test('routeNode: an unknown type is a SEED of the inbox and keeps its TYPE', function()
  local out, rel = vault.routeNode(node('films'))
  T.eq(rel, nil)
  T.eq(out[1], '* SEED My entry')
  T.ok(has(out, ':TYPE:%s+films'))
  T.match(T.lastMessage(), 'No note sources/films%.org')
end)

T.test('routeNode: a heading that already has a state gets the new one in its place', function()
  local lines = node('tree')
  lines[1] = '* SEED Grown up'
  local out = vault.routeNode(lines)
  T.eq(out[1], '* TREE Grown up')
end)

-- ---------------------------------------------------------------------------
--  Rename, delete (<leader>vr, <leader>vd)
-- ---------------------------------------------------------------------------
T.test('rename: new title and file name; the old file is gone', function()
  T.edit('garden/old_plant.org', 1)
  T.answers({ input = 'Renamed plant' })
  vault.rename()
  T.ok(not T.exists('garden/old_plant.org'), 'the old file is gone')
  T.ok(T.exists('garden/renamed_plant.org'), 'the new file')
  T.eq(T.read('garden/renamed_plant.org')[1], '#+title: Renamed plant')
  T.ok(has(T.read('garden/renamed_plant.org'), 'aaaaaaaa%-0000%-4000%-8000%-000000000031'), 'the :ID: stays')
end)

T.test('rename: a name that exists is refused', function()
  T.edit('garden/old_plant.org', 1)
  T.answers({ input = 'Nursery' })
  vault.rename()
  T.match(T.lastMessage(), 'nursery%.org exists')
  T.ok(T.exists('garden/old_plant.org'))
end)

T.test('rename: a note without a title gets one after its file properties', function()
  T.edit('inbox.org', 1)
  vim.api.nvim_buf_set_lines(0, 3, 4, false, {}) -- drop #+TITLE: Inbox
  vim.cmd('silent write')
  T.answers({ input = 'My inbox' })
  vault.rename()
  local lines = T.read('my_inbox.org')
  T.eq(lines[1], ':PROPERTIES:')
  T.eq(lines[4], '#+title: My inbox')
end)

T.test('delete: asks; Yes moves the note to archive/trash/', function()
  T.edit('garden/old_plant.org', 1)
  T.answers({ confirm = 2 })
  vault.delete()
  T.ok(T.exists('garden/old_plant.org'), 'No keeps it')
  T.answers({ confirm = 1 })
  vault.delete()
  T.ok(not T.exists('garden/old_plant.org'), 'gone')
  T.ok(T.exists('archive/trash/old_plant.org'), 'in the trash')
end)

T.test('delete: a note of the same name in the trash is not overwritten', function()
  T.write('archive/trash/old_plant.org', { 'older' })
  T.edit('garden/old_plant.org', 1)
  T.answers({ confirm = 1 })
  vault.delete()
  T.eq(T.read('archive/trash/old_plant.org'), { 'older' })
  local found = false
  for name in vim.fs.dir(T.vault('archive/trash')) do
    if name:match('^%d+%-old_plant%.org$') then found = true end
  end
  T.ok(found, 'a timestamped copy')
end)
