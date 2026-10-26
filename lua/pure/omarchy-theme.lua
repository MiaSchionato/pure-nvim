-- =============================================================================
--  Follow the Omarchy theme (`lua/pure/omarchy-theme.lua`)
-- =============================================================================
--  "omarchy" is an entry of the <leader>fc list. Picking it means: always use
--  the colorscheme that goes with the current Omarchy theme, now and on every
--  start, and again when the theme changes while Neovim is open (checked when
--  the terminal gets focus back).
--
--  The colorscheme of an Omarchy theme is read from the theme's own neovim.lua
--  (`colorscheme = "..."`, a LazyVim spec: the same file Omarchy gives LazyVim).
--  Themes without one are matched by name. The plugin is installed with
--  vim.pack when it is missing (vim.pack asks before cloning).
--
--  The choice (a colorscheme name, or "omarchy") is saved in
--  stdpath('data')/colorscheme. ShaDa used to carry it, but it is only written
--  on a clean exit and the last instance to exit overwrote the others.
-- =============================================================================

local M = {}

M.NAME = 'omarchy'
M.LABEL = 'omarchy (follows the Omarchy theme)'

local store = vim.fn.stdpath('data') .. '/colorscheme'

-- Colorschemes that differ from the Omarchy theme name when the theme ships no
-- neovim.lua (or names a colorscheme this config does not have).
local ALIASES = {
  ['tokyo-night'] = 'tokyonight-night',
  ['rose-pine'] = 'rose-pine-dawn',
  ['catppuccin'] = 'catppuccin',
}

--- The saved choice, or nil.
function M.saved()
  local ok, lines = pcall(vim.fn.readfile, store)
  local value = ok and lines[1] and vim.trim(lines[1]) or ''
  return value ~= '' and value or nil
end

function M.save(value)
  pcall(vim.fn.writefile, { value }, store)
end

--- Name of the current Omarchy theme as the folder is called ("tokyo-night"), or nil.
function M.current()
  if vim.fn.executable('omarchy') ~= 1 then return nil end
  local res = vim.system({ 'omarchy', 'theme', 'current' }, { text = true }):wait(2000)
  local name = res.code == 0 and vim.trim(res.stdout or '') or ''
  if name == '' then return nil end
  return (name:lower():gsub('%s+', '-'))
end

local function themeDir(name)
  local res = vim.system({ 'omarchy', 'theme', 'dir', name }, { text = true }):wait(2000)
  local dir = res.code == 0 and vim.trim(res.stdout or '') or ''
  return dir ~= '' and dir or nil
end

--- What the theme's neovim.lua names: the colorscheme and the plugin repos
--- (without LazyVim itself), in file order.
local function readSpec(dir)
  local path = dir and (dir .. '/neovim.lua')
  if not (path and vim.uv.fs_stat(path)) then return nil, {} end
  local text = table.concat(vim.fn.readfile(path), '\n')
  local repos = {}
  for repo in text:gmatch('"([%w_.-]+/[%w_.-]+)"') do
    if not repo:find('^LazyVim/') then table.insert(repos, repo) end
  end
  return text:match('colorscheme%s*=%s*"([^"]+)"'), repos
end

local function exists(scheme)
  return scheme ~= nil and #vim.fn.getcompletion(scheme, 'color') > 0
    and vim.tbl_contains(vim.fn.getcompletion(scheme, 'color'), scheme)
end

--- The colorscheme for the Omarchy theme `name`, installing its plugin when
--- needed. Returns the name, or nil and a reason.
function M.colorschemeFor(name)
  local scheme, repos = readSpec(themeDir(name))
  scheme = scheme or ALIASES[name] or name

  if not exists(scheme) and #repos > 0 then
    local specs = {}
    for _, repo in ipairs(repos) do
      table.insert(specs, { src = 'https://github.com/' .. repo })
    end
    pcall(vim.pack.add, specs)
  end
  if exists(scheme) then return scheme end
  -- LazyVim's "catppuccin-nvim" and similar: try the part before the last dash.
  local base = scheme:match('^(.-)%-[%w]+$')
  if exists(base) then return base end
  return nil, ('no colorscheme "%s" for the Omarchy theme "%s"'):format(scheme, name)
end

local applied -- the Omarchy theme the current colorscheme was chosen for

--- The colorscheme for the current Omarchy theme, without applying it. Returns
--- the name, or nil and a reason.
function M.resolved()
  local name = M.current()
  if not name then return nil, 'cannot read the current theme (is `omarchy` on PATH?)' end
  local scheme, err = M.colorschemeFor(name)
  if scheme then applied = name end
  return scheme, err
end

--- Apply the colorscheme of the current Omarchy theme. Returns true on success.
function M.apply()
  local scheme, err = M.resolved()
  if not scheme then
    vim.notify('Omarchy theme: ' .. err, vim.log.levels.WARN)
    return false
  end
  if vim.g.colors_name ~= scheme then
    pcall(vim.cmd.colorscheme, scheme)
  end
  return true
end

--- True while the saved choice is "omarchy".
function M.following()
  return M.saved() == M.NAME
end

-- Follow theme changes made while Neovim is open (omarchy theme set …).
vim.api.nvim_create_autocmd('FocusGained', {
  group = vim.api.nvim_create_augroup('PureOmarchyTheme', { clear = true }),
  callback = function()
    if M.following() and M.current() ~= applied then M.apply() end
  end,
})

return M
