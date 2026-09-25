-- =============================================================================
-- Automatic Recursive Module Loader
-- =============================================================================
-- Loads every .lua file under 'lua/' as a module.

require('pure.fuzzyUtils').setup()
-- Before the loader, so vim.notify calls made while the modules below load
-- already reach the notification window (the loader order is alphabetical).
require('pure.notify')

-- stdpath() may return either separator depending on how XDG_CONFIG_HOME was
-- set, so normalise to '/' once and build the glob without a trailing slash.
-- The old code did stdpath() .. "/lua/" and then appended "/**/*.lua", which
-- produced a double slash ('lua//configs/...'). Stripping the prefix then left
-- a leading '/', so every module was required as '.configs.autocmds' instead of
-- 'configs.autocmds'. Lua resolves that name too, so nothing errored -- it just
-- cached each module under a bogus key, and any normal require() of the same
-- file loaded and executed a SECOND copy.
local lua_root = vim.fs.normalize(vim.fn.stdpath('config')) .. '/lua'
local files_to_load = vim.fn.glob(lua_root .. '/**/*.lua', true, true)

local failures = {}

for _, file_path in ipairs(files_to_load) do
  -- Strip the 'lua/' prefix by plain length, never with gsub: the config path
  -- can contain '-', '.' or '~', which gsub would treat as pattern magic.
  local relative_path = vim.fs.normalize(file_path):sub(#lua_root + 2)

  -- 'configs/keymaps.lua' -> 'configs.keymaps'
  local module_name = relative_path:gsub('%.lua$', ''):gsub('/', '.')

  local ok, err = pcall(require, module_name)
  if not ok then
    table.insert(failures, module_name .. ': ' .. tostring(err))
  end
end

-- Reported after startup so the message survives the intro screen, instead of
-- being swallowed the way the old notify() call was.
if #failures > 0 then
  vim.schedule(function()
    vim.notify('Failed to load ' .. #failures .. ' module(s):\n'
      .. table.concat(failures, '\n'), vim.log.levels.ERROR)
  end)
end
