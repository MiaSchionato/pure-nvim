--- Obsidian-compatible note templates.
---
--- Templates live in the vault and use the syntax of Obsidian's *core*
--- Templates plugin, so the same file works in both editors without Templater:
---
---   {{title}}            the note's title (its file name without extension)
---   {{date}}             current date, default YYYY-MM-DD
---   {{time}}             current time, default HH:mm
---   {{date:FORMAT}}      a Moment.js format, e.g. {{date:YYYYMMDDHHmm}},
---   {{time:FORMAT}}      {{date:dddd, D [de] MMMM}}; [text] is copied as is
---
--- Day and month names follow vim.g.pure_templates_locale: 'en' (default, as
--- Obsidian ships) or 'pt'. Set it to the language Obsidian itself uses, so a
--- template expands to the same text in both editors.
---
--- Templater's `tp.file.move(...)` has no equivalent in the core plugin, so the
--- destination folder is not written into the template at all: it lives in the
--- `destinations` table below, keyed by template name. That keeps the template
--- files clean and puts the routing in one place.
---
--- The vault path is asked for once and remembered, the same way the Todoist
--- token is. In order of precedence:
---
---   vim.g.pure_vault              set in the config, wins over everything
---   $OBSIDIAN_VAULT               environment
---   stdpath('data')/obsidian_vault   the answer to the question below
---
--- :ZettelVault asks again at any time.

local M = {}

local vault_file = vim.fn.stdpath('data') .. '/obsidian_vault'
local no_prompt_file = vim.fn.stdpath('data') .. '/obsidian_vault_no_prompt'

--- Templates that are a note *per period* rather than a note about something.
---
--- Picking one of these does not insert into the current buffer: it works out
--- which note the period maps to, creates it from the template if it is not
--- there yet, and opens it. Opening the same period twice just returns to the
--- note, so the template never runs over what you already wrote.
---
--- `name` is an os.date format; %G-W%V is the ISO week, which Windows' strftime
--- does support (checked: 2026-09-25 gives 2026-W39).
local periodic = {
  Daily   = { folder = '9-Archive/Periodic/Daily',   name = '%Y-%m-%d', step = 86400 },
  Weekly  = { folder = '9-Archive/Periodic/Weekly',  name = '%G-W%V',   step = 604800 },
  Monthly = { folder = '9-Archive/Periodic/Monthly', name = '%Y-%m',    step = nil },
}

--- Where the quote of the day and the note archive live, relative to the vault.
local QUOTES = '9-Archive/Periodic/Quotes.md'
local PERMANENT = '3-Zettelkasten/Permanent'

--- Short weekday names used by the diary file names.
local DIARY_WEEKDAY = { 'dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb' }

--- Folder each template sends its note to, relative to the vault root.
--- "{{title}}" is expanded, which is what puts a project in its own folder.
--- A template missing here simply leaves the note where it is.
local destinations = {
  Delete     = '0-Inbox/Trash',
  Literature = '3-Zettelkasten/Literature',
  MOC        = '4-Maps',
  Permanent  = '3-Zettelkasten/Permanent',
  Project    = '1-Projects/{{title}}',
  Tester     = '2-Areas/Audiovisual/YouTube/Tester channel',
  VideoIdeas = '2-Areas/Audiovisual/Ideas',
}

--- Day and month names per locale. os.date's %A / %B always gave English
--- (the C locale), whatever language Obsidian renders the same template in.
local locales = {
  en = {
    months = { 'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December' },
    months_short = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' },
    days = { 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday' },
    days_short = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' },
    days_min = { 'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa' },
    ordinal = function(n)
      local last2, last = n % 100, n % 10
      local suffix = (last2 >= 11 and last2 <= 13) and 'th'
        or ({ 'st', 'nd', 'rd' })[last] or 'th'
      return n .. suffix
    end,
  },
  -- As Moment's pt / pt-br locales write them: lower case.
  pt = {
    months = { 'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
      'agosto', 'setembro', 'outubro', 'novembro', 'dezembro' },
    months_short = { 'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez' },
    days = { 'domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado' },
    days_short = { 'dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb' },
    days_min = { 'do', '2ª', '3ª', '4ª', '5ª', '6ª', 'sá' },
    ordinal = function(n) return n .. 'º' end,
  },
}

--- Moment.js tokens, longest first within each letter so "MMMM" is not eaten
--- by "MM", "Do" is tried before "D", and so on.
local TOKENS = {
  'YYYY', 'YY',
  'MMMM', 'MMM', 'MM', 'M',
  'Do', 'DDDD', 'DDD', 'DD', 'D',
  'dddd', 'ddd', 'dd', 'd',
  'HH', 'H', 'hh', 'h',
  'mm', 'm', 'ss', 's',
  'A', 'a',
}

--- Format `time` with a Moment.js format string, as Obsidian does.
---
--- Formatted directly rather than translated to an os.date format: strftime
--- has no unpadded day, month or hour (Moment's D, M, H, h) and no ordinals,
--- which the translation used to leave as literal letters. Text in [brackets]
--- is copied without formatting, as in Moment. Scanned left to right, so a
--- value can never be re-matched by a later token.
--- @param fmt string
--- @param time integer
--- @return string
local function formatMoment(fmt, time)
  local t = os.date('*t', time)
  local L = locales[vim.g.pure_templates_locale or 'en'] or locales.en
  local h12 = t.hour % 12 == 0 and 12 or t.hour % 12
  local value = {
    YYYY = ('%04d'):format(t.year), YY = ('%02d'):format(t.year % 100),
    MMMM = L.months[t.month], MMM = L.months_short[t.month],
    MM = ('%02d'):format(t.month), M = tostring(t.month),
    Do = L.ordinal(t.day), DDDD = ('%03d'):format(t.yday), DDD = tostring(t.yday),
    DD = ('%02d'):format(t.day), D = tostring(t.day),
    dddd = L.days[t.wday], ddd = L.days_short[t.wday], dd = L.days_min[t.wday], d = tostring(t.wday - 1),
    HH = ('%02d'):format(t.hour), H = tostring(t.hour), hh = ('%02d'):format(h12), h = tostring(h12),
    mm = ('%02d'):format(t.min), m = tostring(t.min), ss = ('%02d'):format(t.sec), s = tostring(t.sec),
    A = t.hour < 12 and 'AM' or 'PM', a = t.hour < 12 and 'am' or 'pm',
  }

  local out, i = {}, 1
  while i <= #fmt do
    local literal = fmt:match('^%[([^%]]*)%]', i)
    if literal then
      out[#out + 1] = literal
      i = i + #literal + 2
    else
      local matched
      for _, token in ipairs(TOKENS) do
        if fmt:sub(i, i + #token - 1) == token then
          matched = token
          break
        end
      end
      if matched then
        out[#out + 1] = value[matched]
        i = i + #matched
      else
        out[#out + 1] = fmt:sub(i, i)
        i = i + 1
      end
    end
  end
  return table.concat(out)
end

--- Configured vault path, or nil when it has never been answered.
--- @return string|nil
local function vaultPath()
  local configured = vim.g.pure_vault
  if configured and configured ~= '' then
    return vim.fs.normalize(vim.fn.expand(configured))
  end

  local env = vim.env.OBSIDIAN_VAULT
  if env and env ~= '' then
    return vim.fs.normalize(vim.fn.expand(env))
  end

  local f = io.open(vault_file, 'r')
  if not f then return nil end
  local saved = vim.trim(f:read('*l') or '')
  f:close()
  -- An empty file counts as unanswered, so the question comes up again.
  return saved ~= '' and vim.fs.normalize(vim.fn.expand(saved)) or nil
end

local function templatesPath()
  local root = vaultPath()
  return root and (root .. '/' .. (vim.g.pure_templates or 'Templates')) or nil
end

--- Ask for the vault folder and remember it.
---
--- The answer is checked before saving: a path that is not a directory, or that
--- has no Templates folder, is almost certainly a typo, and finding that out
--- now beats finding out on the first <leader>nz.
function M.setVault()
  local ok, input = pcall(vim.fn.input, {
    prompt = 'Obsidian vault folder (empty to cancel): ',
    default = vaultPath() or vim.fn.expand('~/'),
    completion = 'dir',
  })
  input = ok and vim.trim(input or '') or ''
  if input == '' then
    return vim.notify('Vault not changed')
  end

  local path = vim.fs.normalize(vim.fn.expand(input))
  if vim.fn.isdirectory(path) == 0 then
    return vim.notify('Not a folder: ' .. path .. '\nNothing saved.', vim.log.levels.WARN)
  end

  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  local f, err = io.open(vault_file, 'w')
  if not f then
    return vim.notify('Could not write ' .. vault_file .. ': ' .. tostring(err), vim.log.levels.ERROR)
  end
  f:write(path, '\n')
  f:close()
  os.remove(no_prompt_file)

  if vim.g.pure_vault and vim.g.pure_vault ~= '' then
    vim.notify('Saved, but vim.g.pure_vault is set and takes precedence', vim.log.levels.WARN)
  end
  -- plugins/obsidian.lua and the <leader>em / fa / nm keys follow the vault.
  vim.api.nvim_exec_autocmds('User', { pattern = 'PureVaultChanged', data = { vault = vaultPath() } })

  local templates = path .. '/' .. (vim.g.pure_templates or 'Templates')
  if vim.fn.isdirectory(templates) == 0 then
    vim.notify('Vault saved, but there is no Templates folder in it yet:\n  ' .. templates,
      vim.log.levels.WARN)
  else
    local n = #vim.tbl_filter(function(name) return name:match('%.md$') end, vim.fn.readdir(templates))
    vim.notify(('Vault saved: %s (%d templates)'):format(path, n))
  end
end

--- Offer to set the vault once, on the first start that has a UI.
--- Declining writes a marker so the question is not repeated; :ZettelVault
--- still works afterwards.
function M.maybeAskVault()
  if vaultPath() or vim.uv.fs_stat(no_prompt_file) or #vim.api.nvim_list_uis() == 0 then
    return
  end
  vim.schedule(function()
    local choice = vim.fn.confirm(
      'No Obsidian vault configured. Set it now?\n(templates come from <vault>/Templates)',
      '&Yes\n&Later\nNe&ver ask', 1)
    if choice == 1 then
      M.setVault()
    elseif choice == 3 then
      local f = io.open(no_prompt_file, 'w')
      if f then
        f:write('Delete this file to be asked again, or run :ZettelVault\n')
        f:close()
      end
      vim.notify('Will not ask again. Run :ZettelVault when you want to set it.')
    end
  end)
end

vim.api.nvim_create_user_command('ZettelVault', M.setVault,
  { desc = 'Set the Obsidian vault folder used for templates' })

--- Title of the current note: the file name without extension.
local function currentTitle()
  local name = vim.fn.expand('%:t:r')
  return name ~= '' and name or 'Untitled'
end

--- One line of Quotes.md, picked by the day of the year so it is stable for a
--- given day and cycles through the file.
--- @param when integer
--- @return string
local function quoteOfTheDay(when)
  local root = vaultPath()
  if not root then return '' end
  local file = io.open(root .. '/' .. QUOTES, 'r')
  if not file then return '' end

  local quotes = {}
  for line in file:lines() do
    if line:sub(1, 2) == '- ' then
      quotes[#quotes + 1] = line:sub(3)
    end
  end
  file:close()
  if #quotes == 0 then return '' end

  return quotes[(tonumber(os.date('%j', when)) % #quotes) + 1]
end

--- One of your own permanent notes, resurfaced by the day of the year.
--- @param when integer
--- @return string
local function resurfacedNote(when)
  local root = vaultPath()
  if not root then return '' end

  local notes = vim.fn.globpath(root .. '/' .. PERMANENT, '*.md', false, true)
  if #notes == 0 then
    return 'Write your first permanent note and it will show up here.'
  end
  table.sort(notes)

  local pick = notes[(tonumber(os.date('%j', when)) % #notes) + 1]
  return '[[' .. vim.fn.fnamemodify(pick, ':t:r') .. ']]'
end

--- Expand the template placeholders.
---
--- Every date comes from a single timestamp, so a template using both {{date}}
--- and {{time}} cannot straddle a second boundary. The previous version built
--- its table of values when the module was *required*, which meant {{time}}
--- returned the moment Neovim started rather than the moment of use.
---
--- `ctx.when` is the note's own date, which for a periodic note is the day it
--- covers rather than today. That is what makes reopening an old daily render
--- its own neighbours instead of this week's.
--- @param content string
--- @param ctx table
--- @return string
local function render(content, ctx)
  local when = ctx.when or os.time()
  local period = ctx.periodic

  return (content:gsub('{{([%a_]+)(:?)([^}]*)}}', function(name, colon, fmt)
    local key = name:lower()

    if key == 'title' then
      return ctx.title
    elseif key == 'date' then
      return formatMoment(colon == ':' and fmt or 'YYYY-MM-DD', when)
    elseif key == 'time' then
      return formatMoment(colon == ':' and fmt or 'HH:mm', when)
    elseif key == 'week' then
      return os.date('%G-W%V', when)
    elseif key == 'month' then
      return os.date('%Y-%m', when)
    elseif key == 'quote' then
      return quoteOfTheDay(when)
    elseif key == 'idea' then
      return resurfacedNote(when)
    elseif key == 'diary' then
      -- Matches the diary file names: "2026-09-25, sex"
      return os.date('%Y-%m-%d', when) .. ', ' .. DIARY_WEEKDAY[tonumber(os.date('%w', when)) + 1]
    elseif key == 'prev' or key == 'next' then
      -- Only meaningful inside a periodic note, where a step is defined.
      if not (period and period.step) then return '' end
      local delta = key == 'prev' and -period.step or period.step
      return os.date(period.name, when + delta)
    end

    return nil -- unknown placeholder: leave it untouched
  end))
end

--- Move the current file into `folder` (relative to the vault).
---
--- Writes first, renames, then reopens at the new path and drops the stale
--- buffer, otherwise Neovim keeps editing a name that no longer exists.
--- @param folder string
local function moveCurrentFile(folder)
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' then
    return vim.notify('Save the note before applying a template that moves it',
      vim.log.levels.WARN)
  end

  local root = vaultPath()
  if not root then return end -- insertTemplate checks first; this is a guard

  local title = currentTitle()
  -- Replaced through a function: as a plain replacement string, a '%' in the
  -- title is gsub syntax, and "100% focus" became the folder "100 focus".
  local folder_name = folder:gsub('{{title}}', function() return title end)
  local target_dir = root .. '/' .. folder_name
  local target = target_dir .. '/' .. vim.fn.fnamemodify(path, ':t')

  -- Case-blind on Windows, where the same file can be spelled C:/ or c:/.
  local a, b = vim.fs.normalize(target), vim.fs.normalize(path)
  if vim.fn.has('win32') == 1 then a, b = a:lower(), b:lower() end
  if a == b then
    return -- already there
  end
  if vim.uv.fs_stat(target) then
    return vim.notify('Not moving: a note already exists at ' .. target,
      vim.log.levels.WARN)
  end

  vim.fn.mkdir(target_dir, 'p')
  vim.cmd('silent write')

  local old = vim.api.nvim_get_current_buf()
  local ok, err = os.rename(path, target)
  if not ok then
    return vim.notify('Could not move the note: ' .. tostring(err), vim.log.levels.ERROR)
  end

  vim.cmd('edit ' .. vim.fn.fnameescape(target))
  if vim.api.nvim_buf_is_valid(old) and vim.api.nvim_get_current_buf() ~= old then
    vim.api.nvim_buf_delete(old, { force = true })
  end
  vim.notify('Moved to ' .. folder_name)
end

--- Open the note for a period, creating it from `template` when missing.
---
--- Unlike the other templates this does not touch the current buffer: the note
--- is a file whose name comes from the date, so it is written straight to disk
--- and opened. An existing note is opened untouched.
--- @param template string  template file name, e.g. "Daily.md"
--- @param period table     entry from `periodic`
--- @param when integer     timestamp of the period to open
local function openPeriodic(template, period, when)
  local root = vaultPath()
  if not root then return end

  local dir = root .. '/' .. period.folder
  local path = dir .. '/' .. os.date(period.name, when) .. '.md'

  if vim.uv.fs_stat(path) then
    return vim.cmd('edit ' .. vim.fn.fnameescape(path))
  end

  local file = io.open(templatesPath() .. '/' .. template, 'r')
  if not file then
    return vim.notify('Could not read ' .. template, vim.log.levels.ERROR)
  end
  local content = file:read('*a')
  file:close()

  vim.fn.mkdir(dir, 'p')
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(render(content, {
    title = os.date(period.name, when),
    when = when,
    periodic = period,
  }), '\n'))
  vim.cmd('silent write')
  vim.notify('Created ' .. period.folder .. '/' .. os.date(period.name, when))
end

--- Open today's daily note, or another day with an offset in days.
--- @param offset integer|nil
function M.openDaily(offset)
  local period = periodic.Daily
  openPeriodic('Daily.md', period, os.time() + (offset or 0) * 86400)
end

--- Pick a template, expand it at the cursor, and move the note if the template
--- has a destination. Periodic templates open their own note instead.
function M.insertTemplate()
  local dir = templatesPath()
  if not dir then
    vim.notify('No Obsidian vault configured yet', vim.log.levels.WARN)
    return M.setVault()
  end
  if vim.fn.isdirectory(dir) == 0 then
    return vim.notify('Templates folder not found: ' .. dir
      .. '\nRun :ZettelVault to point at another vault.', vim.log.levels.ERROR)
  end

  local files = vim.tbl_filter(function(name)
    return name:match('%.md$') ~= nil
  end, vim.fn.readdir(dir))

  if #files == 0 then
    return vim.notify('No templates in ' .. dir, vim.log.levels.WARN)
  end

  vim.ui.select(files, { prompt = 'Template' }, function(selected)
    if not selected then return end

    local name = selected:gsub('%.md$', '')

    -- A periodic template addresses a note of its own, so it opens that note
    -- rather than expanding into whatever buffer happens to be focused.
    local period = periodic[name]
    if period then
      return openPeriodic(selected, period, os.time())
    end

    local file = io.open(dir .. '/' .. selected, 'r')
    if not file then
      return vim.notify('Could not read ' .. selected, vim.log.levels.ERROR)
    end
    local content = file:read('*a')
    file:close()

    local lines = vim.split(render(content, { title = currentTitle() }), '\n')
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, lines)

    local folder = destinations[name]
    if folder then
      moveCurrentFile(folder)
    end
  end)
end

-- Also used by plugins/obsidian.lua and configs/keymaps.lua, so the vault is
-- configured in one place.
M.vaultPath = vaultPath

-- Offer to set the vault on the first start with a UI (maybeAskVault itself
-- returns at once when one is set, declined, or there is no UI).
vim.api.nvim_create_autocmd('VimEnter', {
  group = vim.api.nvim_create_augroup('PureZettelVault', { clear = true }),
  once = true,
  callback = M.maybeAskVault,
})

-- Exposed for tests.
M._render = render
M._formatMoment = formatMoment
M._destinations = destinations

return M
