-- org.nvim set up like the Doom Emacs of the vault: the same agenda files,
-- the same TODO / idea keywords, the quick-capture templates (s t T l f j) and
-- org-roam (the `roam` extension of org.nvim) on the same vault. The Doom side
-- is C:\doom\config\config.el; the vault layout is the vault's CLAUDE.md.
vim.pack.add({ { src = 'https://github.com/xheisenbugx/org.nvim', name = 'org' } })

-- The vault folder: the one setting vim.g.pure_vault (configs.lua, loaded before this file).
local vault = require('pure.vault').dir() or '~'

-- Task states, then the idea stages of the garden (SEED > SPROUT > PLANT > TREE,
-- FLOWER; COMPOST is let go). Keys and logging marks as in Doom.
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

-- The questions of the templates below all show in the centre (Mia, 2026-11-08): a typed answer in the
-- input float, a choice in the fzf list (vim.ui.input / vim.ui.select, pure/fuzzyUtils.lua), through
-- org.nvim's utils, which wait for them inside the capture's coroutine. The questions of `l` and `f` are
-- asked in their target function, which org.nvim calls before it opens the target file: Esc there cancels
-- the capture quietly (utils.abort) and leaves nothing behind. The template then only writes the answers.
local orgUtils = require('org.utils')

--- A typed answer in the input float; Esc cancels the capture.
local function ask(prompt, default)
  local answer = orgUtils.input({ prompt = prompt, default = default })
  if answer == nil then orgUtils.abort() end
  return vim.trim(answer)
end

--- A choice from `items` in the fzf list; Esc cancels the capture.
local function choose(prompt, items)
  local choice = orgUtils.select(items, { prompt = prompt })
  if choice == nil then orgUtils.abort() end
  return choice
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

-- Task template: asks for a date first; Enter (or Esc) leaves the task without one.
-- The answer is read like org's own date prompt (today, +3d, fri, 2026-11-02).
local function task_template()
  local answer = vim.trim(orgUtils.input({ prompt = 'When? (Enter = no date; today, +3d, fri, 2026-11-02): ' }) or '')
  local planning = ''
  if answer ~= '' then
    local d = require('org.date').read_date(answer)
    if d then
      d.active = true
      planning = 'SCHEDULED: ' .. d:to_string() .. '\n'
    else
      vim.notify('Could not read the date "' .. answer .. '"; the task has no date', vim.log.levels.WARN)
    end
  end
  return '* TODO %?\n' .. planning .. CREATED
end

-- Link: the address (the clipboard by default) and a title, asked before the inbox is opened.
local function link_target()
  local clip = vim.trim((vim.fn.getreg('+') or ''):match('[^\r\n]*') or '')
  answers.link = { url = ask('Link: ', clip), title = ask('Title: ') }
  return 'inbox.org'
end

local function link_template()
  local a = answers.link or {}
  return '* [[' .. literal(a.url or '') .. '][' .. literal(a.title or '') .. ']]\n' .. CREATED .. '\n%?'
end

-- Source file: sources/<kind>.org, the kind picked in the fzf list (it was a numbered list); created with a
-- title. Then the title, the author and the status, before the file is opened.
local SOURCE_KINDS = { 'books', 'articles', 'videos', 'courses', 'podcasts', 'other' }
local SOURCE_STATUS = { 'to-read', 'reading', 'done' }
local function source_target()
  local kind = choose('Source', SOURCE_KINDS)
  answers.source = { title = ask('Title: '), author = ask('Author: '), status = choose('Status', SOURCE_STATUS) }
  local path = 'sources/' .. kind .. '.org'
  local full = vim.fn.expand(vault) .. '/' .. path
  if vim.fn.filereadable(full) == 0 then
    vim.fn.writefile({ '#+TITLE: ' .. kind:sub(1, 1):upper() .. kind:sub(2), '' }, full)
  end
  return path
end

local function source_template()
  local a = answers.source or {}
  return '* ' .. literal(a.title or '') .. '\n:PROPERTIES:\n:CREATED:  %U\n:AUTHOR:   ' .. literal(a.author or '')
    .. '\n:STATUS:   ' .. (a.status or '') .. '\n:END:\n%?'
end

require('org').setup({
  org_directory = vault,
  default_notes_file = vault .. '/inbox.org',

  -- org.nvim's keys live under <leader>m (its default is <leader>o, the Toggles group); Manim is <leader>M.
  mappings = { prefix = '<leader>m' },

  -- The agenda reads tasks, the inbox (it may hold dated things) and every
  -- file of projects/, like `my/garden-agenda-files` in Doom.
  agenda_files = { vault .. '/tasks.org', vault .. '/inbox.org', vault .. '/projects/**/*.org' },

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
        template = task_template,
        target = 'tasks.org',
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
        target = source_target,
        hook = restorePercent,
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
-- entry and closes the window, <C-c><C-k> aborts. (Mia, 2026-11-08.)
local CAPTURE_RATIO = 0.6
local orgUi = require('org.ui')
local openBufferWindow = orgUi.open_buffer_window
orgUi.open_buffer_window = function(buf, mode, opts)
  if mode ~= 'pure_float' then return openBufferWindow(buf, mode, opts) end
  local title = opts and opts.title and (' ' .. opts.title .. ' ') or ' '
  local win = require('configs.functions').createWindow(title, CAPTURE_RATIO, { buf = buf })
  -- org.nvim writes its hint into the winbar right after this returns: clear it once it has.
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then vim.wo[win].winbar = '' end
  end)
  return win
end

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
