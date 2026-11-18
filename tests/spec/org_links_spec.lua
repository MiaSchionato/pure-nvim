-- lsp/orgls.lua, the links between org notes (by :ID:), on tests/fixtures/vault-org: the vault it reads,
-- what [[ completes, where a link points, and the :ID: a heading gets when a link to it is written.
local orgls = require('lsp.orgls')._module

T.test('the vault and the inbox: the settings of the configuration', function()
  T.eq(orgls.path(), vim.fs.normalize(T.vault()))
end)

T.test('parse: [[ text split into headings only, the note, the query', function()
  T.eq({ orgls._parse('first') }, { false, nil, 'first' })
  T.eq({ orgls._parse('#sprout') }, { true, nil, 'sprout' })
  T.eq({ orgls._parse('Nursery#grow') }, { true, 'Nursery', 'grow' })
  T.eq({ orgls._parse('https://x') }, { false, nil, 'https://x' }, 'a scheme is no note')
  T.eq({ orgls._parse('idea||short') }, { false, nil, 'idea' }, 'what follows || is the alias')
end)

T.test('entries: notes, headings with their :ID:, aliases', function()
  local byTitle = {}
  for _, e in ipairs(orgls._entries(vim.fs.normalize(T.vault()))) do byTitle[e.kind .. ':' .. e.title] = e end
  T.ok(byTitle['note:Inbox'], 'the inbox note by its #+TITLE')
  local seed = byTitle['heading:First seed']
  T.ok(seed, 'the heading')
  T.eq(seed.id, 'aaaaaaaa-0000-4000-8000-000000000011')
  T.ok(byTitle['alias:Ancient plant'], 'a :ROAM_ALIASES: entry')
end)

T.test('linkAt: the link under a column', function()
  local line = 'see [[id:abc][Text]] and [[file:x.org]]'
  T.eq(orgls._linkAt(line, 6).inner, 'id:abc][Text')
  T.eq(orgls._linkAt(line, 30).inner, 'file:x.org')
  T.eq(orgls._linkAt(line, 1), nil)
end)

T.test('linkTarget: an id: link points to the file and the heading', function()
  local t = orgls._linkTarget(0, 'id:aaaaaaaa-0000-4000-8000-000000000011')
  T.ok(t, 'found')
  T.eq(vim.fs.normalize(t.file), vim.fs.normalize(T.vault('inbox.org')))
  T.eq(t.lnum, T.row('inbox.org', '^%* SEED First seed'))
  T.match(t.label, 'First seed')
end)

T.test('ensureId: a heading without :ID: gets one; one with an :ID: keeps it', function()
  local file = T.vault('inbox.org')
  local row = T.row('inbox.org', '^%* SEED Second seed')
  local id = orgls._ensureId(file, row)
  T.match(id, '^%x+%-%x+%-%x+%-%x+%-%x+$')
  vim.cmd('silent! wall')
  local lines = T.read('inbox.org')
  local found = false
  for i = row, row + 5 do if (lines[i] or ''):find(':ID:%s+' .. vim.pesc(id)) then found = true end end
  T.ok(found, 'the :ID: is written under the heading')
  local again = orgls._ensureId(file, T.row('inbox.org', '^%* SEED First seed'))
  T.eq(again, 'aaaaaaaa-0000-4000-8000-000000000011')
end)

T.test('candidates: a word finds the heading; a note and # its headings', function()
  local list = orgls._candidates('first seed', 'all', T.vault('tasks.org'))
  local titles = {}
  for _, e in ipairs(list) do titles[#titles + 1] = e.title end
  T.ok(vim.tbl_contains(titles, 'First seed'), vim.inspect(titles))
end)
