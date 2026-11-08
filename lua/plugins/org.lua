-- org.nvim set up like the Doom Emacs of the vault: the same agenda files,
-- the same TODO / idea keywords, the quick-capture templates (s t T l f j) and
-- org-roam (the `roam` extension of org.nvim) on the same vault. The Doom side
-- is C:\doom\config\config.el; the vault layout is the vault's CLAUDE.md.
vim.pack.add({ { src = 'https://github.com/xheisenbugx/org.nvim', name = 'org' } })

-- The vault folder: the one setting vim.g.pure_vault (configs.lua, loaded before this file).
local vault = require('pure.vault').dir() or '~'

-- Task states, then the idea stages of the garden (SEED > SPROUT > PLANT > TREE,
-- FLOWER; COMPOST is let go). Keys and logging marks as in Doom. A note can keep only
-- one set with a #+TODO: line of its own (org reads it, in Doom too): inbox.org and
-- garden/<year>.org have the garden's, tasks.org the tasks', so the state menu
-- (<leader>vt, t in the agenda) offers only those there. Notes without one have both.
local todo_keywords = {
  'TODO(t) NEXT(n) DOING(d) WAITING(w@) | DONE(x!) CANCELLED(c@)',
  'SEED(s) SPROUT(p) PLANT(l) TREE(r) FLOWER(f) | COMPOST(c)',
}

-- The Ethereal palette, as the Doom keyword faces.
local keyword_faces = {
  NEXT = ':foreground #7d82d9 :weight bold',
  DOING = ':foreground #a3bfd1 :weight bold',
  WAITING = ':foreground #faaaa9 :weight bold',
  CANCELLED = ':foreground #6d7db6',
  SEED = ':foreground #a3bfd1 :weight bold',
  SPROUT = ':foreground #9be0a8 :weight bold',
  PLANT = ':foreground #6fcf97 :weight bold',
  TREE = ':foreground #ffcead :weight bold',
  FLOWER = ':foreground #faaaa9 :weight bold',
  COMPOST = ':foreground #6d7db6',
}

local CREATED = ':PROPERTIES:\n:CREATED:  %U\n:END:'

-- Only `l` asks questions (the link and its title); the other templates open the capture buffer at once and the
-- text is written there (Mia, 2026-11-08). The questions show in the centre: a typed answer in the input float
-- (vim.ui.input, pure/fuzzyUtils.lua), through org.nvim's utils, which wait for it inside the capture's coroutine.
-- They are asked in the target function, which org.nvim calls before it opens the target file: Esc there cancels
-- the capture quietly (utils.abort) and leaves nothing behind. The template then only writes the answers.
local orgUtils = require('org.utils')

-- The size of every window of a capture: the fzf lists, the questions and the capture buffer itself
-- (createWindow's ratio). The same width, left edge and top row, so each one opens where the last one was;
-- a question is one line at that top edge. 0.8: the size of the other fzf lists. (Mia, 2026-11-08.)
local CAPTURE_RATIO = 0.8

--- A typed answer in the input float; Esc cancels the capture.
local function ask(prompt, default)
  local answer = orgUtils.input({ prompt = prompt, default = default, ratio = CAPTURE_RATIO })
  if answer == nil then orgUtils.abort() end
  return vim.trim(answer)
end

--- An answer as template text: org.nvim must not read a % in it as an escape (%a, %^{...}, %(...) ...).
--- Each % becomes a private-use character org.nvim leaves alone, and the template's hook (`restorePercent`,
--- run on the capture buffer once it is filled) turns it back. A backslash before the % would stay in the
--- text wherever org.nvim sees no escape ("100% done" became "100\% done").
local PERCENT = '\238\128\128' -- U+E000
local function literal(text) return (text:gsub('%%', PERCENT)) end
local function restorePercent(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = false
  for i, l in ipairs(lines) do
    if l:find(PERCENT, 1, true) then lines[i], changed = l:gsub(PERCENT, '%%'), true end
  end
  if changed then vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines) end
end

-- The answers of the running capture, from its target function to its template.
local answers = {}

-- Task: no question; the buffer has an empty SCHEDULED: line to fill in by hand, in words ("today",
-- "tomorrow", "fri", "+3d", "2026-11-20", or hoje / amanhã / oggi / domani...) or as a timestamp. When the
-- entry is stored, the words become a timestamp, and a line left empty is dropped (an empty SCHEDULED: is not a
-- date for org, only a stray line). See the store filter below.
local TASK_TEMPLATE = '* TODO %?\nSCHEDULED: \n' .. CREATED

-- Link: the address (the clipboard by default) and a title, asked before the inbox is opened. The capture
-- buffer then opens in Normal mode (the template has no %? cursor), only to check what was typed.
local function link_target()
  local clip = vim.trim((vim.fn.getreg('+') or ''):match('[^\r\n]*') or '')
  answers.link = { url = ask('Link: ', clip), title = ask('Title: ') }
  return 'inbox.org'
end

local function link_template()
  local a = answers.link or {}
  return '* [[' .. literal(a.url or '') .. '][' .. literal(a.title or '') .. ']]\n' .. CREATED
end

-- Source: no question; the buffer has every property of a source, empty, to fill in (the render hides the
-- empty ones). :TYPE: says where the entry goes when it is stored: `:TYPE: Books` sends it to the note
-- sources/books.org (any case: books, Books, BOOKS), whose columnview table then lists it; no :TYPE:, or a type
-- with no note of that name in sources/, sends it to the inbox. No note is made: make it, then move the entry
-- with <leader>vm. TYPE is in no table (no #+COLUMNS lists it). The empty properties stay in the entry.
local SOURCE_PROPERTIES = { 'TYPE', 'AUTHOR', 'STATUS', 'GENRE', 'LANGUAGE', 'BY', 'WHERE', 'RATING', 'NOTES' }
local function source_template()
  local lines = { '* %?', ':PROPERTIES:' }
  for _, key in ipairs(SOURCE_PROPERTIES) do
    lines[#lines + 1] = (':%s:'):format(key) .. string.rep(' ', 9 - #key) -- every one empty, STATUS too (Mia)
  end
  vim.list_extend(lines, { ':CREATED:  %U', ':END:' })
  return table.concat(lines, '\n')
end

-- What a store filter does with the entry of a capture, before org.nvim stores it (org.capture.store_filters:
-- `fun(tpl, lines, ctx)` returns the lines and, to send the entry elsewhere, a target). The templates opt in with
-- two fields of this config: `route_by_type` (f) and `read_planning` (t).

-- Words of the planning lines in Portuguese and Italian, read as org.nvim's English ones.
local DATE_WORDS = { hoje = 'today', ['amanhã'] = 'tomorrow', amanha = 'tomorrow', ontem = 'yesterday', agora = 'now',
  oggi = 'today', domani = 'tomorrow', ieri = 'yesterday', ora = 'now' }

--- The SCHEDULED: / DEADLINE: lines of `lines` in words become timestamps; an empty one is dropped.
local function readPlanning(lines)
  local out = {}
  for _, l in ipairs(lines) do
    local key, text = l:match('^%s*(SCHEDULED):%s*(.-)%s*$')
    if not key then key, text = l:match('^%s*(DEADLINE):%s*(.-)%s*$') end
    if not key or text:match('^[<%[]') then
      out[#out + 1] = l
    elseif text ~= '' then
      local d = require('org.date').read_date(DATE_WORDS[vim.fn.tolower(text)] or text)
      if d then
        d.active = true
        out[#out + 1] = key .. ': ' .. d:to_string()
      else
        vim.notify(('Could not read the date "%s": the %s line is kept as it was'):format(text, key), vim.log.levels.WARN)
        out[#out + 1] = l
      end
    end -- an empty one is left out
  end
  return out
end

require('org.capture').store_filters.pure_vault = function(tpl, lines)
  if tpl.read_planning then lines = readPlanning(lines) end
  if tpl.route_by_type then
    local type
    for _, l in ipairs(lines) do
      type = l:match('^%s*:[Tt][Yy][Pp][Ee]:%s*(.-)%s*$')
      if type then break end
    end
    local rel = type and type ~= '' and require('pure.vault').sourceFile(type)
    if rel then return lines, { target = rel } end
    if type and type ~= '' then
      vim.notify(('No note sources/%s.org: the entry goes to the inbox'):format(vim.fn.tolower(type)), vim.log.levels.WARN)
    end
  end
  return lines
end

-- The names of the source properties in org.nvim's completion of property names (after a ":" at the start of a
-- line in a drawer), in capitals like the template writes them. Property names are not case sensitive for org
-- (Author and AUTHOR are the same property), but one spelling keeps the notes alike.
do
  local names = require('org.completion').properties
  for _, key in ipairs(SOURCE_PROPERTIES) do
    if not vim.tbl_contains(names, key) then names[#names + 1] = key end
  end
end

require('org').setup({
  org_directory = vault,
  default_notes_file = vault .. '/inbox.org',

  -- org.nvim's keys live under <leader>m (its default is <leader>o, the Toggles group); Manim is <leader>M.
  mappings = { prefix = '<leader>m' },

  -- The agenda reads tasks, the inbox (it may hold dated things) and every
  -- file of projects/, like `my/garden-agenda-files` in Doom.
  agenda_files = { vault .. '/tasks.org', vault .. '/inbox.org', vault .. '/projects/**/*.org' },

  -- The agenda opens floating, in this config's window like the capture (see the window opener below the
  -- setup). Default: 'split'. (Mia, 2026-11-08.)
  agenda = { window = 'float' },

  todo_keywords = todo_keywords,

  -- Align every table when a note is opened (Emacs: #+STARTUP: align); by default
  -- org.nvim aligns only when a table is edited. Tables written by scripts show up straight.
  startup_align_all_tables = true,

  -- org.nvim draws nothing over the text (links, stars, checkboxes...): the
  -- rendering is pure/render-org.lua's, so it can be toggled and follows the
  -- terminal (<leader>om). Its syntax colours stay.
  ui = {
    todo_keyword_faces = keyword_faces,
    conceal_links = false,
    hide_emphasis_markers = false,
    hide_leading_stars = false,
    bullets = false,
    checkboxes = false,
    indent_mode = false,
    pretty_entities = false,
    num = false,
  },

  capture = {
    -- The capture buffer opens in this config's floating window (see 'pure_float'
    -- below the setup), not in a split. :w (or <C-c><C-c>) stores the entry and
    -- closes it. Default: 'split'.
    window = 'pure_float',
    templates = {
      s = {
        description = 'Seed',
        template = '* SEED %?\n' .. CREATED,
        target = 'inbox.org',
        empty_lines = 1,
      },
      t = {
        description = 'Task',
        template = TASK_TEMPLATE,
        target = 'tasks.org',
        read_planning = true,
        empty_lines = 1,
      },
      T = {
        description = 'Task + deadline',
        template = '* TODO %?\nDEADLINE: %^t\n' .. CREATED,
        target = 'tasks.org',
        empty_lines = 1,
      },
      l = {
        description = 'Link',
        template = link_template,
        target = link_target,
        hook = restorePercent,
        empty_lines = 1,
      },
      f = {
        description = 'Source',
        template = source_template,
        target = 'inbox.org',
        route_by_type = true,
        empty_lines = 1,
      },
      j = {
        description = 'Journal',
        template = '* %<%H:%M> %?',
        target = function() return 'journal/' .. os.date('%Y') .. '.org' end,
        datetree = true,
      },
    },
  },

  extensions = {
    roam = {
      directory = vault,
      -- The journal has no nodes, as in the custom Emacs config.
      exclude = { 'journal/' },
      -- Daily notes live in the year's journal file, one entry per day in its date tree.
      dailies = {
        directory = 'journal/',
        capture_templates = {
          d = {
            description = 'default',
            type = 'entry',
            template = '* %<%H:%M> %?',
            target = '%<%Y>.org',
            datetree = true,
          },
        },
      },
    },
  },
})

-- The capture window ('pure_float', set as capture.window above): this config's centred floating window
-- (configs/functions.lua createWindow), the same as the terminals and the link view, instead of org.nvim's
-- split. org.nvim's own window modes are strings only, so its window opener is wrapped and the new mode
-- handled here; every other mode goes to the original. org.nvim's key hint bar (" Capture: finish <C-c><C-c>
-- refile <C-c><C-w> abort <C-c><C-k>  (:w finishes)") is left out. The keys stay: :w or <C-c><C-c> stores the
-- entry and closes the window, <C-c><C-k> aborts. Its size is CAPTURE_RATIO (above), the size of the capture's
-- questions. (Mia, 2026-11-08.)
-- The agenda (agenda.window = 'float' above) asks org.nvim's own float, titled "Org Agenda": that one window is
-- opened here too, at the same size and place as the capture, so both look alike. Its winbar is left alone (the
-- agenda's column view writes its titles there).
local orgUi = require('org.ui')
local openBufferWindow = orgUi.open_buffer_window
orgUi.open_buffer_window = function(buf, mode, opts)
  local agenda = mode == 'float' and opts ~= nil and opts.title == 'Org Agenda'
  if mode ~= 'pure_float' and not agenda then return openBufferWindow(buf, mode, opts) end
  local title = opts and opts.title and (' ' .. opts.title .. ' ') or ' '
  local win = require('configs.functions').createWindow(title, CAPTURE_RATIO, { buf = buf })
  if not agenda then
    -- org.nvim writes the capture's hint into the winbar right after this returns: clear it once it has.
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) then vim.wo[win].winbar = '' end
    end)
  end
  return win
end

-- Dynamic blocks (#+BEGIN: ... #+END:, e.g. the columnview table of sources/books.org) are made again each time
-- a note of the vault that holds one is saved, so a table follows its headings without C-c C-c. A write hook of
-- org.nvim (org.write_hooks), not a BufWritePre: org.nvim writes the target of a capture, a refile or an archive
-- with :noautocmd, and its write hooks run for those saves and for :w alike. Silent (org.nvim's own update_all
-- says "Updated N dynamic block(s)" every time). Notes outside the vault are left alone, as in Emacs.
-- (Mia, 2026-11-08.)
local function inVaultFile(path)
  local dir = require('pure.vault').dir()
  if not dir or path == '' then return false end
  local p, d = vim.fs.normalize(path), vim.fs.normalize(dir)
  if vim.fn.has('win32') == 1 then p, d = p:lower(), d:lower() end
  return p:sub(1, #d + 1) == d .. '/'
end
require('org.write_hooks').register('pure-dynamic-blocks', {
  filetype = 'org',
  pre = function(bufnr)
    if not inVaultFile(vim.api.nvim_buf_get_name(bufnr)) then return end
    local starts = {}
    for i, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if l:match('^%s*#%+[Bb][Ee][Gg][Ii][Nn]:%s') then starts[#starts + 1] = i end
    end
    if #starts == 0 then return end
    local dblock = require('org.dblock')
    for k = #starts, 1, -1 do -- bottom to top, so the lines above stay where they are
      local block = dblock.find_at(bufnr, starts[k])
      if block then pcall(dblock.update_block, bufnr, block) end
    end
  end,
})

-- In a table <Tab> / <S-Tab> go to the next / previous cell, but while the completion menu is open they pick the
-- next / previous suggestion, as everywhere else. org.nvim's action steps aside (an action that returns false is
-- "not handled") and its key falls back to the global <Tab> / <S-Tab> of configs/keymaps.lua, which know the menu.
-- The lookup is wrapped here, not the actions, so org.nvim's table editor is still loaded only when it is used.
local actions = require('org.actions')
local original_get = actions.get
local YIELDS_TO_MENU = { insert_tab = true, table_prev_field = true }
actions.get = function(name)
  local fn, action = original_get(name)
  if fn and YIELDS_TO_MENU[name] then
    return function(...)
      if vim.fn.pumvisible() == 1 then return false end
      return fn(...)
    end, action
  end
  return fn, action
end
