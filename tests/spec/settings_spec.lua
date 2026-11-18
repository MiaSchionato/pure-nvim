-- The settings: docs/README.md lists every one, configs.lua names every one (set, or commented out with its
-- default), and the helpers that read them (folders by name, the vault's notes, the Markdown vault engine).

local root = vim.fn.stdpath('config')

--- The names of the "Settings in one place" table of docs/README.md.
local function documented()
  local names, inTable = {}, false
  for _, l in ipairs(vim.fn.readfile(root .. '/docs/README.md')) do
    if l:match('^## Settings in one place') then inTable = true
    elseif inTable and l:match('^## ') then break
    elseif inTable then
      local name = l:match('^| `vim%.[gb]%.([%w_]+)`')
      if name then names[#names + 1] = name end
    end
  end
  return names
end

T.test('docs/README.md lists the settings', function()
  T.ok(#documented() > 50, 'more than 50 settings, got ' .. #documented())
end)

T.test('every setting of docs/README.md is named in configs.lua or in the module that reads it', function()
  local configs = table.concat(vim.fn.readfile(root .. '/lua/configs/configs.lua'), '\n')
  local all = configs
  for _, f in ipairs(vim.fn.glob(root .. '/lua/**/*.lua', true, true)) do
    all = all .. '\n' .. table.concat(vim.fn.readfile(f), '\n')
  end
  local unknown = {}
  for _, name in ipairs(documented()) do
    if not all:find(name, 1, true) then unknown[#unknown + 1] = name end
  end
  T.eq(unknown, {}, 'documented, but no module reads them')
end)

T.test('configs.lua sets the editor options it says it sets', function()
  T.eq(vim.o.expandtab, true)
  T.eq(vim.o.shiftwidth, 4)
  T.eq(vim.o.tabstop, 4)
  T.eq(vim.o.number, true)
  T.eq(vim.o.relativenumber, true)
  T.eq(vim.o.ignorecase, true)
  T.eq(vim.o.smartcase, true)
  T.eq(vim.o.swapfile, false)
  T.eq(vim.o.undofile, true)
  T.eq(vim.o.mouse, '')
  T.eq(vim.o.splitbelow, true)
  T.eq(vim.o.splitright, true)
  T.eq(vim.o.cmdheight, 0)
  T.eq(vim.o.showmode, false)
  T.eq(vim.o.foldlevelstart, 99)
  T.eq(vim.o.autocomplete, true)
  T.eq(vim.o.completeopt, 'menu,menuone,noinsert,noselect')
  T.match(vim.o.undodir, 'undo$')
  T.ok(vim.fn.isdirectory(vim.o.undodir) == 1, 'the undo folder exists')
end)

T.test('the folders by name: defaults, a setting, an unknown name, the vault', function()
  local f = require('configs.functions')
  local home = vim.fs.normalize(vim.fn.expand('~'))
  T.eq(f.dir('home'), home .. '/')
  T.eq(f.dir('config'), home .. '/.config/')
  T.eq(f.dir('nope'), nil)
  local saved = vim.g.pure_dirs
  vim.g.pure_dirs = { projects = '~/Work' }
  T.eq(f.dir('projects'), home .. '/Work/')
  T.eq(f.dir('home'), home .. '/', 'a name left out keeps its default')
  vim.g.pure_dirs = saved
  T.eq(f.dir('vault'), vim.fs.normalize(T.vault()) .. '/')
  T.eq(f.dirs.config(), f.dir('config'), 'dirs.<name>() asks dir(name)')
end)

T.test('openVaultNote: <leader>o_ opens the note of that name; an unknown name warns', function()
  local f = require('configs.functions')
  f.openVaultNote('nursery')()
  T.match(vim.api.nvim_buf_get_name(0), 'vault%-org/garden/nursery%.org$')
  f.openVaultNote('inbox')()
  T.match(vim.api.nvim_buf_get_name(0), 'vault%-org/inbox%.org$')
  f.openVaultNote('nope')()
  T.match(T.lastMessage(), 'no note named nope')
end)

-- ---------------------------------------------------------------------------
--  pure/zettelkasten.lua: where the Markdown engine finds the vault, its dates
-- ---------------------------------------------------------------------------
T.test('zettelkasten: the vault is the Markdown vault of the settings, else the older setting, else the default', function()
  local z = require('pure.zettelkasten')
  T.eq(z.vaultPath(), vim.fs.normalize(T.vault(nil, 'vault-md')))
  local saved = vim.g.pure_vaults
  vim.g.pure_vaults = { org = saved.org }
  T.eq(z.vaultPath(), vim.fs.normalize(T.vault()), 'no md vault: the default one')
  vim.g.pure_vault = T.vault(nil, 'vault-md')
  T.eq(z.vaultPath(), vim.fs.normalize(T.vault(nil, 'vault-md')), 'the older setting before the default')
  vim.g.pure_vault = T.vault('nowhere')
  T.eq(z.vaultPath(), nil, 'a folder that does not exist is no vault')
  vim.g.pure_vault = nil
  vim.g.pure_vaults = saved
end)

T.test('zettelkasten: Moment.js formats of the templates, in English and Portuguese', function()
  local z = require('pure.zettelkasten')
  local t = os.time({ year = 2026, month = 9, day = 25, hour = 14, min = 5, sec = 0 })
  T.eq(z._formatMoment('YYYY-MM-DD', t), '2026-09-25')
  T.eq(z._formatMoment('YYYYMMDDHHmm', t), '202609251405')
  T.eq(z._formatMoment('HH:mm', t), '14:05')
  T.eq(z._formatMoment('dddd, D [de] MMMM', t), 'Friday, 25 de September')
  local saved = vim.g.pure_templates_locale
  vim.g.pure_templates_locale = 'pt'
  T.eq(z._formatMoment('dddd, D [de] MMMM', t), 'sexta-feira, 25 de setembro')
  vim.g.pure_templates_locale = saved
end)

T.test('zettelkasten: the periods (ISO week, the bounds of a month)', function()
  local z = require('pure.zettelkasten')
  local t = os.time({ year = 2026, month = 9, day = 25, hour = 12 })
  T.eq(os.date(z._periodic.Weekly.name, t), '2026-W39')
  T.eq(os.date(z._periodic.Daily.name, t), '2026-09-25')
  T.eq(os.date(z._periodic.Monthly.name, t), '2026-09')
  local first, last = z._bounds(z._periodic.Monthly, t)
  T.eq(os.date('%Y-%m-%d', first), '2026-09-01')
  T.eq(os.date('%Y-%m-%d', last), '2026-09-30')
  local wf, wl = z._bounds(z._periodic.Weekly, t)
  T.eq(os.date('%Y-%m-%d %a', wf), '2026-09-21 Mon')
  T.eq(os.date('%Y-%m-%d %a', wl), '2026-09-27 Sun')
end)

T.test('zettelkasten: a template renders title, date and time', function()
  local z = require('pure.zettelkasten')
  local t = os.time({ year = 2026, month = 9, day = 25, hour = 14, min = 5 })
  local out = z._render('# {{title}}\n{{date}} {{time}} {{date:YYYY}}', { title = 'My note', when = t })
  T.eq(out, '# My note\n2026-09-25 14:05 2026')
end)
