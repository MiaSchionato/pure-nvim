-- pure/vault.lua's settings: vim.g.pure_vaults (several vaults, a format each), which vault a command uses,
-- the notes by name without extension, read-only vaults, and the older one-vault settings.
local vault = require('pure.vault')
local ORG, MD = vim.fs.normalize(T.vault()), vim.fs.normalize(T.vault(nil, 'vault-md'))

-- NONE stands for nil in a table of settings (pairs skips a nil value).
local NONE = {}
local function with(settings, fn)
  local saved = {}
  for k, v in pairs(settings) do
    saved[k] = vim.g[k]
    if v == NONE then vim.g[k] = nil else vim.g[k] = v end
  end
  local ok, err = pcall(fn)
  for k in pairs(settings) do vim.g[k] = saved[k] end
  if not ok then error(err, 0) end
end

T.test('list: every vault, the default first, made whole', function()
  local list = vault.list()
  T.eq(#list, 2)
  T.eq({ list[1].name, list[1].format, list[1].dir }, { 'org', 'org', ORG })
  T.eq({ list[2].name, list[2].format, list[2].dir }, { 'md', 'md', MD })
  T.eq(list[2].readonly, false)
  with({ pure_vault_default = 'md' }, function() T.eq(vault.list()[1].name, 'md') end)
end)

T.test('list: a vault without a folder is left out; an unknown format warns', function()
  with({ pure_vaults = { a = { format = 'org' }, b = { dir = T.vault(), format = 'txt' }, c = { dir = T.vault() } } },
    function()
      local list = vault.list()
      T.eq(#list, 1)
      T.eq({ list[1].name, list[1].format }, { 'c', 'org' }, 'org when the format is not given')
      T.match(table.concat(vim.tbl_map(function(m) return m.msg end, T.messages), '\n'), 'format must be org or md')
    end)
end)

T.test('of / current: the vault of a file, else the default', function()
  T.eq(vault.of(T.vault('inbox.org')).name, 'org')
  T.eq(vault.of(T.vault('garden/nursery.md', 'vault-md')).name, 'md')
  T.eq(vault.of(T.vault('../elsewhere.txt')), nil)
  T.eq(vault.of(''), nil)
  vim.cmd('enew')
  T.eq(vault.current().name, 'org', 'no file: the default vault')
  T.edit('garden/nursery.md', 1, 'vault-md')
  T.eq(vault.current().name, 'md')
  T.eq(vault.dir(), MD, 'dir(): the current vault')
  T.eq(vault.dir('org'), ORG, "dir('org'): the org vault, from a Markdown note too")
  T.eq(vault.dir('md'), MD)
end)

T.test('of: a vault inside another one: the deepest folder wins', function()
  with({ pure_vaults = { outer = { dir = T.vault() }, inner = { dir = T.vault('garden'), format = 'md' } } }, function()
    T.eq(vault.of(T.vault('garden/nursery.org')).name, 'inner')
    T.eq(vault.of(T.vault('inbox.org')).name, 'outer')
  end)
end)

T.test('note: names without extension; the format adds it; folders end in /', function()
  T.eq(vault.note('inbox', 'org'), 'inbox.org')
  T.eq(vault.note('inbox', 'md'), 'inbox.md')
  T.eq(vault.note('nursery', 'md'), 'garden/nursery.md')
  T.eq(vault.note('compost', 'md'), 'archive/compost.md')
  T.eq(vault.note('journal', 'org'), 'journal.org')
  T.eq(vault.note('garden', 'md'), 'garden/')
  T.eq(vault.note('trash', 'org'), 'archive/trash/')
  T.eq(vault.note('nope', 'org'), nil)
  local v = vim.deepcopy(vim.g.pure_vaults)
  v.md.notes = { inbox = 'seeds.md', tasks = 'todo' }
  with({ pure_vaults = v }, function()
    T.eq(vault.note('inbox', 'md'), 'seeds.md', 'an extension written in the setting is not doubled')
    T.eq(vault.note('tasks', 'md'), 'todo.md')
    T.eq(vault.inbox('md'), 'seeds.md')
  end)
end)

T.test('contains: a file of any vault, or of one vault', function()
  T.eq(vault.contains(T.vault('inbox.org')), true)
  T.eq(vault.contains(T.vault('inbox.md', 'vault-md')), true)
  T.eq(vault.contains('org', T.vault('inbox.md', 'vault-md')), false)
  T.eq(vault.contains('md', T.vault('inbox.md', 'vault-md')), true)
  T.eq(vault.contains(vim.fn.tempname()), false)
end)

T.test('configuredDir: from vim.g.pure_vaults only', function()
  T.eq(vault.configuredDir('md'), MD)
  T.eq(vault.configuredDir('org'), ORG)
  T.eq(vault.configuredDir(), ORG, 'no format: the default')
  with({ pure_vaults = NONE, pure_vault = T.vault() }, function() T.eq(vault.configuredDir(), nil) end)
end)

T.test('read-only: the commands that write refuse it, find and open still work', function()
  local v = vim.deepcopy(vim.g.pure_vaults)
  v.org.readonly = true
  with({ pure_vaults = v }, function()
    local before = T.read('inbox.org')
    T.edit('inbox.org', T.row('inbox.org', '^%* SEED First seed'))
    vault.grow()
    T.match(T.lastMessage(), 'read%-only')
    T.answers({ confirm = 1 })
    vault.compost()
    vault.delete()
    vault._find.newSeed('Should not be written')
    T.eq(T.read('inbox.org'), before, 'nothing changed')
    T.ok(T.exists('inbox.org'), 'not deleted')
    T.ok(#vault._find.entries(ORG) > 0, 'find still lists the notes')
  end)
end)

T.test('the older settings: g.pure_vault, g.orgls_inbox, g.pure_vault_notes (one org vault)', function()
  with({ pure_vaults = NONE, pure_vault = T.vault(), orgls_inbox = 'seeds.org', pure_vault_notes = { nursery = 'garden/n.org' } },
    function()
      local list = vault.list()
      T.eq(#list, 1)
      T.eq({ list[1].format, list[1].dir }, { 'org', ORG })
      T.eq(vault.inbox(), 'seeds.org')
      T.eq(vault.nursery(), 'garden/n.org')
      T.eq(vault.note('tasks'), 'tasks.org')
    end)
end)

T.test('no vault at all: path warns, commands warn', function()
  with({ pure_vaults = NONE, pure_vault = NONE }, function()
    T.eq(vault.path(), nil)
    T.match(T.lastMessage(), 'no vault folder')
  end)
end)

T.test('a command of a format that does not have it yet warns', function()
  T.edit('garden/nursery.md', 1, 'vault-md')
  package.loaded['pure.vault.md'] = package.loaded['pure.vault.md'] or {}
  local had = package.loaded['pure.vault.md'].agenda
  package.loaded['pure.vault.md'].agenda = nil
  vault.agenda()
  T.match(T.lastMessage(), 'agenda is not there for md vaults')
  package.loaded['pure.vault.md'].agenda = had
end)
