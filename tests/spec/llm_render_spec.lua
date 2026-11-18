-- pure/llm.lua without a model (nothing is sent): the private folders no cloud model may see, the actions'
-- files, what the user context already knows. Then the drawing of notes (render-md, render-org) and the
-- statusline: a note opens drawn, without errors.
local llm = require('pure.llm')
local private = llm._private

-- ---------------------------------------------------------------------------
--  Private folders (vim.g.pure_llm_private)
-- ---------------------------------------------------------------------------
local function withPrivate(list, fn)
  local saved = vim.g.pure_llm_private
  vim.g.pure_llm_private = list
  local ok, err = pcall(fn)
  vim.g.pure_llm_private = saved
  if not ok then error(err, 0) end
end

T.test('private: a file inside a private folder is private; outside it is not', function()
  local secret = T.vault('secret')
  vim.fn.mkdir(secret, 'p')
  withPrivate({ secret }, function()
    T.eq(private.isPrivate(secret .. '/diary.org'), true)
    T.eq(private.isPrivate(T.vault('inbox.org')), false)
    T.eq(private.isPrivate(''), false)
  end)
end)

T.test('private: a folder of the vault by its name inside the vault', function()
  vim.fn.mkdir(T.vault('secret'), 'p')
  withPrivate({ 'secret' }, function()
    T.eq(private.isPrivate(T.vault('secret/x.org')), true)
  end)
end)

T.test('private: a request holding a private note, or reaching a private folder, is refused for the cloud', function()
  local secret = T.vault('secret')
  vim.fn.mkdir(secret, 'p')
  withPrivate({ secret }, function()
    T.match(private.reason({ prompt = 'x ' .. private.mark .. ' y' }, 'claude'), 'holds a note')
    T.match(private.reason({ prompt = 'hi', cwd = secret }, 'claude'), 'reach')
    T.match(private.reason({ prompt = 'hi', cwd = T.vault('elsewhere'), dirs = { secret } }, 'ollama') or '', 'reach')
    T.eq(private.reason({ prompt = 'hi', cwd = T.vault('garden') }, 'claude'), nil, 'a folder that holds none')
  end)
end)

T.test('private: no private folder set, nothing is refused', function()
  withPrivate({}, function()
    T.eq(private.reason({ prompt = 'x ' .. private.mark, cwd = T.vault() }, 'claude'), nil)
  end)
end)

-- ---------------------------------------------------------------------------
--  Actions and the user context
-- ---------------------------------------------------------------------------
T.test('readAction: front matter, body, output by the tools it may use', function()
  local path = T.vault('ai/actions/Summarize.md')
  vim.fn.writefile({ '---', 'description: "Summarize the note"', 'model: haiku', 'tools: Read, Edit', 'dirs: notes, archive',
    '---', '', 'Summarize {{note}}.' }, path)
  local a = llm._readAction(path)
  T.eq(a.name, 'Summarize')
  T.eq(a.description, 'Summarize the note')
  T.eq(a.model, 'haiku')
  T.eq(a.tools, { 'Read', 'Edit' })
  T.eq(a.writes, true, 'Edit writes')
  T.eq(a.output, 'notify', 'an action that writes notifies')
  T.eq(a.dirs, { 'notes', 'archive' })
  T.eq(a.body, 'Summarize {{note}}.')
end)

T.test('readAction: no description, or no front matter, is no action', function()
  local path = T.vault('ai/actions/Nothing.md')
  vim.fn.writefile({ '---', 'model: haiku', '---', 'body' }, path)
  T.eq(llm._readAction(path), nil)
  vim.fn.writefile({ 'just text' }, path)
  T.eq(llm._readAction(path), nil)
end)

T.test('knownFact: a fact said again in other words is known', function()
  local lines = { '- 2026-11-01: The user is called Mia and lives in Italy.' }
  T.eq(llm._knownFact('The user is called Mia', lines), true)
  T.eq(llm._knownFact('The user plays the cello every morning', lines), false)
end)

-- ---------------------------------------------------------------------------
--  Drawing: render-md, render-org, the statusline
-- ---------------------------------------------------------------------------
local function marks(buf)
  local n = 0
  for _, ns in pairs(vim.api.nvim_get_namespaces()) do
    n = n + #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  end
  return n
end

T.test('a Markdown note opens drawn (headings, tasks, links)', function()
  T.edit('tasks.md', 1, 'vault-md')
  vim.cmd('redraw')
  T.wait(function() return marks(0) > 0 end, 2000)
  T.ok(marks(0) > 0, 'marks are drawn')
  T.eq(vim.wo.conceallevel > 0, true, 'markdown turns conceal on')
  local errors = vim.tbl_filter(function(m) return m.level == vim.log.levels.ERROR end, T.messages)
  T.eq(errors, {}, 'no error')
end)

T.test('an org note opens drawn', function()
  T.edit('inbox.org', 1)
  vim.cmd('redraw')
  T.wait(function() return marks(0) > 0 end, 2000)
  T.ok(marks(0) > 0, 'marks are drawn')
  local errors = vim.tbl_filter(function(m) return m.level == vim.log.levels.ERROR end, T.messages)
  T.eq(errors, {}, 'no error')
end)

T.test('the statusline draws for a note, a scratch buffer and a terminal-less window', function()
  local sl = require('pure.statusline')
  T.edit('inbox.org', 1)
  T.eq(type(sl.MyStatusLine()), 'string')
  vim.cmd('enew')
  T.eq(type(sl.MyStatusLine()), 'string')
  T.eq(type(require('configs.functions').MyTabline()), 'string')
end)
