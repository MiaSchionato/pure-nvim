-- =============================================================================
-- Windows: run :shell through Git bash
-- =============================================================================
-- pure/fuzzyUtils.lua builds POSIX pipelines ("ls .. | fzf", "cat .. | fzf",
-- "fd .. | fzf"). Neovim on Windows defaults to cmd.exe, where none of that
-- exists, so every fuzzy picker silently returns nothing.
-- Guarded to win32 - macOS and Linux are untouched.
if vim.fn.has("win32") == 1 then
  -- Neovim does not quote 'shell' when it contains spaces, so
  -- "C:\Program Files\Git\bin\bash.exe" fails outright (shell_error -1).
  -- The 8.3 form has no spaces and works; :8 does not resolve here, so map it.
  local function shortened(p)
    return (p:gsub("Program Files %(x86%)", "PROGRA~2"):gsub("Program Files", "PROGRA~1"))
  end
  local cands = {}
  local roots = { vim.env.ProgramFiles, vim.env["ProgramFiles(x86)"], [[C:\Program Files]] }
  for _, root in ipairs(roots) do
    if root and root ~= "" then
      local p = root .. [[\Git\bin\bash.exe]]
      if vim.uv.fs_stat(p) then
        table.insert(cands, shortened(p))
        table.insert(cands, p)
      end
    end
  end
  local ep = vim.fn.exepath("bash")
  if ep ~= "" then table.insert(cands, shortened(ep)) end

  local saved = {
    vim.o.shell, vim.o.shellcmdflag, vim.o.shellquote, vim.o.shellxquote, vim.o.shellslash,
  }
  local ok = false
  for _, sh in ipairs(cands) do
    vim.o.shell = sh
    vim.o.shellcmdflag = "-c"
    vim.o.shellquote = ""
    vim.o.shellxquote = ""
    vim.o.shellslash = true
    local out = vim.fn.system("echo nvimshellok")
    if vim.v.shell_error == 0 and out:match("nvimshellok") then
      ok = true
      break
    end
  end
  if not ok then
    vim.o.shell, vim.o.shellcmdflag, vim.o.shellquote, vim.o.shellxquote, vim.o.shellslash =
      saved[1], saved[2], saved[3], saved[4], saved[5]
  end
end

-- =============================================================================
-- Windows: start in the user's home, not next to nvim.exe
-- =============================================================================
-- The Start menu / desktop shortcut launches Neovim with no "Start in"
-- directory, so the working directory becomes wherever the executable lives
-- (C:\Program Files\Neovim\bin) or a Windows system folder. That is never a
-- useful cwd: the explorer, the fuzzy pickers and :find all default to it.
--
-- Only those launcher directories are redirected. Running `nvim` from a project
-- directory in a terminal keeps that directory, and passing a file or folder
-- argument is left alone entirely.
if vim.fn.has("win32") == 1 and vim.fn.argc() == 0 then
  local function norm(path)
    return (vim.fs.normalize(path):gsub("/+$", "")):lower()
  end

  local cwd = norm(vim.fn.getcwd())
  local system_root = vim.env.SystemRoot or [[C:\Windows]]

  -- Directories a launcher drops us into, never one chosen on purpose.
  local launcher_dirs = {
    norm(vim.fs.dirname(vim.v.progpath)),   -- ...\Neovim\bin
    norm(system_root),
    norm(system_root .. [[\System32]]),
  }

  local redirect = false
  for _, dir in ipairs(launcher_dirs) do
    if cwd == dir then
      redirect = true
      break
    end
  end

  -- Also catch GUI front-ends installed under Program Files: nothing worth
  -- editing lives there, and it is not writable without elevation.
  for _, var in ipairs({ "ProgramFiles", "ProgramFiles(x86)" }) do
    local root = vim.env[var]
    if not redirect and root and root ~= "" then
      local prefix = norm(root) .. "/"
      if cwd:sub(1, #prefix) == prefix then
        redirect = true
      end
    end
  end

  if redirect then
    local home = vim.env.USERPROFILE or vim.uv.os_homedir()
    if home and home ~= "" and vim.fn.isdirectory(home) == 1 then
      vim.fn.chdir(home)
    end
  end
end

-- =============================================================================
-- Automatic Recursive Module Loader
-- =============================================================================
-- Loads every .lua file under 'lua/' as a module.

require('pure.fuzzyUtils').setup()

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
