-- pure/notes.lua, the links between Markdown notes (Obsidian's rules), on tests/fixtures/vault-md.
-- notes.lua finds the vault through pure/zettelkasten.lua: the Markdown vault of vim.g.pure_vaults.
local notes = require('pure.notes')
local MD = 'vault-md'

local function has(lines, pattern)
  for _, l in ipairs(lines) do if l:find(pattern, 1, true) then return true end end
  return false
end

-- ---------------------------------------------------------------------------
--  Reading links
-- ---------------------------------------------------------------------------
T.test('linksIn: wiki links with heading, block and alias, embeds, markdown links, URLs', function()
  local l = notes._linksIn('a [[Note]] b [[Note#Head|Alias]] c ![[Pic#^b1]] d [t](Other%20note.md) e https://x.org/y')
  T.eq(#l, 5)
  T.eq({ l[1].kind, l[1].inner }, { 'wiki', 'Note' })
  T.eq({ l[2].kind, l[2].inner }, { 'wiki', 'Note#Head|Alias' })
  T.eq({ l[3].kind, l[3].inner, l[3].embed }, { 'wiki', 'Pic#^b1', true })
  T.eq({ l[4].kind, l[4].inner }, { 'md', 'Other%20note.md' })
  T.eq({ l[5].kind, l[5].inner }, { 'url', 'https://x.org/y' })
end)

T.test('linksIn: the columns of a link are where it is written', function()
  local line = 'xx [[Note]] yy'
  local l = notes._linksIn(line)[1]
  T.eq(line:sub(l.s, l.e), '[[Note]]')
end)

T.test('resolve: case blind; a path; the same folder first, else the shortest path', function()
  local files = { 'garden/old_plant.md', 'projects/client/old_plant.md', 'inbox.md', 'garden/nursery.md', 'img/pic.png' }
  T.eq(notes._resolve(files, 'INBOX'), 'inbox.md')
  T.eq(notes._resolve(files, 'old_plant', 'garden/nursery.md'), 'garden/old_plant.md', 'the same folder')
  T.eq(notes._resolve(files, 'old_plant', 'projects/client/x.md'), 'projects/client/old_plant.md', 'the same folder')
  T.eq(notes._resolve(files, 'old_plant', 'inbox.md'), 'garden/old_plant.md', 'the shortest path')
  T.eq(notes._resolve(files, 'client/old_plant', 'inbox.md'), 'projects/client/old_plant.md', 'a partial path')
  T.eq(notes._resolve(files, 'pic.png'), 'img/pic.png', 'a file that is not a note keeps its extension')
  T.eq(notes._resolve(files, 'missing'), nil)
end)

-- ---------------------------------------------------------------------------
--  Following links (<CR>, K)
-- ---------------------------------------------------------------------------
local function onLink(rel, pattern)
  T.edit(rel, nil, MD)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    local c = l:find(pattern, 1, true)
    if c then vim.api.nvim_win_set_cursor(0, { i, c + 1 }) return end
  end
  error('no ' .. pattern .. ' in ' .. rel)
end

T.test('follow: [[note]] opens the note', function()
  onLink('garden/hubs.md', '[[nursery]]')
  notes.follow()
  T.match(vim.api.nvim_buf_get_name(0), 'garden/nursery%.md$')
end)

T.test('follow: [[note#Heading|text]] lands on the heading', function()
  onLink('inbox.md', '[[nursery#A sprout')
  notes.follow()
  T.match(vim.api.nvim_buf_get_name(0), 'nursery%.md$')
  T.eq(vim.api.nvim_get_current_line(), '# A sprout to grow')
end)

T.test('follow: [[note#^block]] lands on the block', function()
  onLink('garden/old_plant.md', '[[tasks#^t1a2b3c4]]')
  notes.follow()
  T.match(vim.api.nvim_buf_get_name(0), 'tasks%.md$')
  T.match(vim.api.nvim_get_current_line(), '%^t1a2b3c4$')
end)

T.test('follow: a link to a note that does not exist asks; No makes nothing', function()
  T.write('garden/hubs.md', { 'See [[Brand new]].' }, MD)
  onLink('garden/hubs.md', '[[Brand new]]')
  T.answers({ confirm = 2 })
  notes.follow()
  T.ok(not T.exists('Brand new.md', MD) and not T.exists('garden/Brand new.md', MD), 'nothing made')
end)

-- ---------------------------------------------------------------------------
--  Renaming a note fixes the links to it
-- ---------------------------------------------------------------------------
T.test('rename: the file moves and every link to it follows, keeping heading, alias and embed', function()
  T.edit('garden/old_plant.md', 1, MD)
  T.answers({ confirm = 1 })
  notes.rename('young_tree')
  T.ok(not T.exists('garden/old_plant.md', MD), 'the old file is gone')
  T.ok(T.exists('garden/young_tree.md', MD), 'the new one')
  T.match(vim.api.nvim_buf_get_name(0), 'young_tree%.md$', 'the buffer follows')
  local nursery = T.read('garden/nursery.md', MD)
  T.ok(has(nursery, '[[young_tree]]'), 'a bare link: ' .. vim.inspect(nursery))
  T.ok(has(nursery, '[[young_tree#Old plant|the plant]]'), 'heading and alias kept')
  T.eq(T.read('projects/client/old_plant.md', MD)[1], '# A note with the same name in another folder',
    'the note of the same name elsewhere is not touched')
end)

T.test('rename: answering No to the fix leaves the links as they were', function()
  T.edit('garden/old_plant.md', 1, MD)
  T.answers({ confirm = 2 })
  notes.rename('young_tree')
  T.ok(T.exists('garden/young_tree.md', MD), 'the file is renamed')
  T.ok(has(T.read('garden/nursery.md', MD), '[[old_plant]]'), 'the links are not')
end)

T.test('rename: a name that exists is refused', function()
  T.edit('garden/old_plant.md', 1, MD)
  notes.rename('hubs')
  T.ok(T.exists('garden/old_plant.md', MD))
  T.match(T.lastMessage(), 'already exists')
end)

T.test('fixLinks: a moved note, the links seen from the notes that hold them', function()
  vim.uv.fs_rename(T.vault('inbox.md', MD), T.vault('archive/inbox.md', MD))
  local n = notes.fixLinks({ { old = 'inbox.md', new = 'archive/inbox.md' } }, true)
  T.ok(n and n >= 1, 'links fixed: ' .. tostring(n))
  local plant = T.read('garden/old_plant.md', MD)
  T.ok(has(plant, '[[inbox#First seed|First seed]]'), 'the bare name still leads there: ' .. vim.inspect(plant))
end)

-- ---------------------------------------------------------------------------
--  Completion of [[ (omnifunc)
-- ---------------------------------------------------------------------------
T.test('omnifunc: [[ lists the notes; [[note# its headings', function()
  T.write('scratch.md', { '[[nurs' }, MD)
  T.edit('scratch.md', 1, MD)
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  local start = notes.omnifunc(1, '')
  T.ok(start >= 0, 'a start column')
  local items = notes.omnifunc(0, vim.api.nvim_get_current_line():sub(start + 1, 6))
  items = items.words or items
  local words = {}
  for _, it in ipairs(items) do words[#words + 1] = type(it) == 'table' and (it.abbr or it.word) or it end
  local found = false
  for _, w in ipairs(words) do if w:find('nursery', 1, true) then found = true end end
  T.ok(found, 'nursery is offered: ' .. vim.inspect(words))
end)
