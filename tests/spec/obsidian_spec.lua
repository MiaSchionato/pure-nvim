-- pure/vault/obsidian.lua: a heading with an id:: renamed or moved by hand is noticed on save, and the vault's
-- Obsidian is started (then closed) to fix the links; the moves of pure/vault/md.lua update the state file.
-- Obsidian itself is a stub here: nothing is started.
local obsidian = require('pure.vault.obsidian')
local vault = require('pure.vault')
local MD = 'vault-md'
local STATE = 'files/config/headlinks.json'

local calls
local running
local function stub(opts)
  calls, running = {}, opts.running or false
  obsidian.sys = {
    running = function() return running end,
    open = function(name)
      calls[#calls + 1] = 'open ' .. name
      running = true
      if opts.writes ~= false then
        vim.defer_fn(function() vim.fn.writefile({ '{}' }, T.vault(STATE, MD)) end, 300)
      end
    end,
    close = function() calls[#calls + 1] = 'close' running = false end,
  }
  obsidian.pending = {}
  obsidian.timeout = opts.timeout or 5000
end
local function state() return vim.json.decode(table.concat(T.read(STATE, MD), '\n')) end

T.test('idsOf: the id under each heading, past its tags and properties only', function()
  local ids = obsidian.idsOf({ '# One', '#seed', 'created:: x', 'id:: abc123', '# Two', 'text', 'id:: notmine', '# Three', 'id:: def456' })
  T.eq(ids, { abc123 = 'One', def456 = 'Three' })
end)

T.test('a heading renamed by hand and saved is pending; saved back as it was, it is not', function()
  stub({})
  T.edit('garden/old_plant.md', 2, MD)
  vim.api.nvim_buf_set_lines(0, 4, 5, false, { '# Old plant renamed' })
  vim.cmd('silent write')
  T.ok(obsidian.pending['7a8b9c'], 'pending')
  vim.api.nvim_buf_set_lines(0, 4, 5, false, { '# Old plant' })
  vim.cmd('silent write')
  T.eq(obsidian.pending['7a8b9c'], nil, 'not any more')
end)

T.test('a heading pasted into another note by hand is pending', function()
  stub({})
  T.write('garden/hubs.md', { '# Old plant', '#plant', 'id:: 7a8b9c' }, MD)
  T.edit('garden/hubs.md', 1, MD)
  vim.cmd('silent write')
  T.ok(obsidian.pending['7a8b9c'])
end)

T.test('fix with Obsidian closed: it is started, its state file awaited, then closed', function()
  stub({})
  obsidian.pending = { x = true }
  T.ok(obsidian.fix())
  T.eq(calls, { 'open test-vault', 'close' })
  T.eq(obsidian.hasPending(), false)
  T.match(T.lastMessage(), 'links fixed')
end)

T.test('fix with Obsidian open: nothing is started or closed', function()
  stub({ running = true })
  obsidian.pending = { x = true }
  T.ok(obsidian.fix())
  T.eq(calls, {})
  T.eq(obsidian.hasPending(), false)
end)

T.test('fix: Obsidian that never writes its state is closed after the wait, and the links stay pending', function()
  stub({ writes = false, timeout = 500 })
  obsidian.pending = { x = true }
  T.eq(obsidian.fix(), false)
  T.eq(calls, { 'open test-vault', 'close' })
  T.ok(obsidian.hasPending())
  T.match(T.lastMessage(), 'did not finish')
end)

T.test('grow (pure/vault/md.lua) writes the new note into the state file: nothing is pending', function()
  stub({})
  T.edit('inbox.md', 7, MD)
  vault.grow()
  T.eq(state()['1a2b3c'], { 'garden/nursery.md', 'First seed' })
  T.eq(obsidian.hasPending(), false)
end)

T.test('with Obsidian open the moves leave the state file to it', function()
  stub({ running = true })
  T.edit('inbox.md', 7, MD)
  vault.grow()
  T.eq(state()['1a2b3c'], { 'inbox.md', 'First seed' })
end)

T.test('a vault without an obsidian entry: nothing runs', function()
  stub({})
  local saved = vim.g.pure_vaults
  local v = vim.deepcopy(saved)
  v.md.obsidian = nil
  vim.g.pure_vaults = v
  T.eq(obsidian.fix({ quiet = true }), false)
  T.eq(calls, {})
  vim.g.pure_vaults = saved
end)

T.test(':VaultFixLinks exists', function()
  T.eq(vim.fn.exists(':VaultFixLinks'), 2)
end)
