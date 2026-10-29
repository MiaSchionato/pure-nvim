-- org.nvim set up like the Doom Emacs of the Flora vault: the same agenda files,
-- the same TODO / idea keywords, the quick-capture templates (s t T l f j) and
-- org-roam (the `roam` extension of org.nvim) on the same vault. The Doom side
-- is C:\doom\config\config.el; the vault layout is Flora/CLAUDE.md.
vim.pack.add({ { src = 'https://github.com/xheisenbugx/org.nvim', name = 'org' } })

local vault = '~/Flora'

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

-- Task template: asks for a date first; Enter leaves the task without one.
-- The answer is read like org's own date prompt (today, +3d, fri, 2026-11-02).
local function task_template()
  local answer = vim.trim(vim.fn.input('When? (Enter = no date; today, +3d, fri, 2026-11-02): '))
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

-- Source file: sources/<kind>.org, the kind asked for; created with a title.
local SOURCE_KINDS = { 'books', 'articles', 'videos', 'courses', 'podcasts', 'other' }
local function source_target()
  local choices = { 'Source:' }
  for i, kind in ipairs(SOURCE_KINDS) do choices[#choices + 1] = i .. '. ' .. kind end
  local kind = SOURCE_KINDS[vim.fn.inputlist(choices)] or 'other'
  local path = 'sources/' .. kind .. '.org'
  local full = vim.fn.expand(vault) .. '/' .. path
  if vim.fn.filereadable(full) == 0 then
    vim.fn.writefile({ '#+TITLE: ' .. kind:sub(1, 1):upper() .. kind:sub(2), '' }, full)
  end
  return path
end

require('org').setup({
  org_directory = vault,
  default_notes_file = vault .. '/inbox.org',

  -- The agenda reads tasks, the inbox (it may hold dated things) and every
  -- file of projects/, like `my/garden-agenda-files` in Doom.
  agenda_files = { vault .. '/tasks.org', vault .. '/inbox.org', vault .. '/projects/**/*.org' },

  todo_keywords = todo_keywords,
  ui = { todo_keyword_faces = keyword_faces },

  capture = {
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
        template = '* [[%^{Link|%x}][%^{Title}]]\n' .. CREATED .. '\n%?',
        target = 'inbox.org',
        empty_lines = 1,
      },
      f = {
        description = 'Source',
        template = '* %^{Title}\n:PROPERTIES:\n:CREATED:  %U\n:AUTHOR:   %^{Author}\n'
          .. ':STATUS:   %^{Status|to-read|reading|done}\n:END:\n%?',
        target = source_target,
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
