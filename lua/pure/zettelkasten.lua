--- Obsidian-compatible note templates.
---
--- Templates live in the vault and use the syntax of Obsidian's *core*
--- Templates plugin, so the same file works in both editors without Templater:
---
---   {{title}}            the note's title (its file name without extension)
---   {{date}}             current date, default YYYY-MM-DD
---   {{time}}             current time, default HH:mm
---   {{date:FORMAT}}      any Moment.js format, e.g. {{date:YYYYMMDDHHmm}}
---   {{time:FORMAT}}
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

--- Moment.js tokens, longest first so "MMMM" is not eaten by "MM".
local TOKENS = {
  { 'YYYY', '%Y' }, { 'YY', '%y' },
  { 'MMMM', '%B' }, { 'MMM', '%b' }, { 'MM', '%m' },
  { 'dddd', '%A' }, { 'ddd', '%a' },
  { 'DDDD', '%j' }, { 'DD', '%d' },
  { 'HH', '%H' }, { 'hh', '%I' },
  { 'mm', '%M' }, { 'ss', '%S' },
  { 'A', '%p' },
}

--- Translate a Moment.js format into one os.date understands.
--- Scanned left to right rather than with successive gsubs, so a replacement
--- can never be re-matched by a later token.
--- @param fmt string
--- @return string
local function momentToStrftime(fmt)
  local out, i = {}, 1
  while i <= #fmt do
    local matched = false
    for _, token in ipairs(TOKENS) do
      local from, to = token[1], token[2]
      if fmt:sub(i, i + #from - 1) == from then
        out[#out + 1] = to
        i = i + #from
        matched = true
        break
      end
    end
    if not matched then
      out[#out + 1] = fmt:sub(i, i)
      i = i + 1
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
      '&Yes\n&Not now\n&Never ask', 1)
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

--- Expand the template placeholders.
---
--- Every date comes from a single os.time() taken here, so a template using
--- both {{date}} and {{time}} cannot straddle a second boundary. The previous
--- version built its table of values when the module was *required*, which
--- meant {{time}} returned the moment Neovim started rather than the moment the
--- template was used.
--- @param content string
--- @param title string
--- @return string
local function render(content, title)
  local now = os.time()
  return (content:gsub('{{(%a+)(:?)([^}]*)}}', function(name, colon, fmt)
    local key = name:lower()
    if key == 'title' then
      return title
    elseif key == 'date' then
      return os.date(colon == ':' and momentToStrftime(fmt) or '%Y-%m-%d', now)
    elseif key == 'time' then
      return os.date(colon == ':' and momentToStrftime(fmt) or '%H:%M', now)
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
  local target_dir = root .. '/' .. folder:gsub('{{title}}', title)
  local target = target_dir .. '/' .. vim.fn.fnamemodify(path, ':t')

  if vim.fs.normalize(target) == vim.fs.normalize(path) then
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
  vim.notify('Moved to ' .. folder:gsub('{{title}}', title))
end

--- Pick a template, expand it at the cursor, and move the note if the template
--- has a destination.
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

    local file = io.open(dir .. '/' .. selected, 'r')
    if not file then
      return vim.notify('Could not read ' .. selected, vim.log.levels.ERROR)
    end
    local content = file:read('*a')
    file:close()

    local title = currentTitle()
    local lines = vim.split(render(content, title), '\n')
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, lines)

    local folder = destinations[selected:gsub('%.md$', '')]
    if folder then
      moveCurrentFile(folder)
    end
  end)
end

-- Exposed for tests.
M._render = render
M._momentToStrftime = momentToStrftime
M._destinations = destinations

return M
