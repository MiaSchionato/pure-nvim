-- =============================================================================
--  Test runner:  nvim -l tests/run.lua [filter]
-- =============================================================================
--  Runs every tests/spec/*_spec.lua (or those whose name holds `filter`), each
--  in its own headless Neovim that loads this whole configuration, the way it
--  starts for real, but sealed off from the machine it runs on:
--
--    HOME / USERPROFILE   a temporary folder: '~' in a setting never reaches the
--                         real home, the real vault or the real notes
--    XDG_CONFIG_HOME +    the configuration is this checkout (a worktree or the
--    NVIM_APPNAME         CI's checkout), not the installed one
--    XDG_DATA_HOME        tests/.cache/data: no tokens, no remembered vault; the
--                         plugins vim.pack installs are kept there between runs
--    XDG_STATE/CACHE      temporary
--    USERNAME / USER      'pure-test': org.nvim's session server listens on a pipe
--                         named after the user, so a test never takes the one
--                         the Neovim in use (and Flow's quick capture) talk to
--    PURE_TEST_SETTINGS   tests/settings.lua, run at the end of configs.lua: it
--                         points the vault settings at the fixture copies
--
--  Every spec gets fresh copies of tests/fixtures/ in its HOME. Secrets are never
--  read: pure.protonpass is replaced by a stub (no Todoist, no Calendar).
--  Exit code: 0 when every test passed.
-- =============================================================================

local script = vim.fs.normalize(vim.fn.fnamemodify(arg[0], ':p'))
local repo = vim.fs.dirname(vim.fs.dirname(script))
local filter = arg[1]

local function say(s) io.stdout:write(s .. '\n') end

local function copyTree(src, dst)
  vim.fn.mkdir(dst, 'p')
  for name, kind in vim.fs.dir(src) do
    local s, d = src .. '/' .. name, dst .. '/' .. name
    if kind == 'directory' then copyTree(s, d) else vim.uv.fs_copyfile(s, d) end
  end
end

local specs = {}
for name, kind in vim.fs.dir(repo .. '/tests/spec') do
  if kind == 'file' and name:match('_spec%.lua$') and (not filter or name:find(filter, 1, true)) then
    specs[#specs + 1] = name
  end
end
table.sort(specs)
if #specs == 0 then say('No spec matches ' .. tostring(filter)) os.exit(1) end

local data = repo .. '/tests/.cache/data'
vim.fn.mkdir(data, 'p')

say(vim.trim(vim.fn.system({ vim.v.progpath, '--version' })):match('^[^\n]*') .. '  (' .. vim.v.progpath .. ')')

local failed, passed = 0, 0
for _, name in ipairs(specs) do
  local tmp = vim.fs.normalize(vim.fn.tempname())
  local home = tmp .. '/home'
  vim.fn.mkdir(home, 'p')
  copyTree(repo .. '/tests/fixtures', home)
  local result = tmp .. '/result.txt'
  local env = {
    HOME = home, USERPROFILE = home,
    XDG_CONFIG_HOME = vim.fs.dirname(repo), NVIM_APPNAME = vim.fs.basename(repo),
    XDG_DATA_HOME = data, XDG_STATE_HOME = tmp .. '/state', XDG_CACHE_HOME = tmp .. '/cache',
    USERNAME = 'pure-test', USER = 'pure-test',
    PURE_TEST_SETTINGS = repo .. '/tests/settings.lua',
    PURE_TEST_HOME = home, PURE_TEST_RESULT = result,
    PURE_TEST_SPEC = repo .. '/tests/spec/' .. name,
  }
  local cmd = { vim.v.progpath, '--headless',
    '--cmd', 'lua dofile(vim.env.XDG_CONFIG_HOME .. "/" .. vim.env.NVIM_APPNAME .. "/tests/stubs.lua")',
    '-c', 'lua dofile(vim.env.XDG_CONFIG_HOME .. "/" .. vim.env.NVIM_APPNAME .. "/tests/helper.lua").main()' }
  local start = vim.uv.hrtime()
  local res = vim.system(cmd, { env = env, text = true, timeout = 180000 }):wait()
  local secs = (vim.uv.hrtime() - start) / 1e9
  local ok, lines = pcall(vim.fn.readfile, result)
  if not ok or #lines == 0 then
    failed = failed + 1
    say(('FAIL %s: no result (exit %s, %.1fs)\n%s%s'):format(name, tostring(res.code), secs,
      res.stdout or '', res.stderr or ''))
  else
    for _, l in ipairs(lines) do
      say(l)
      if l:match('^ok ') then passed = passed + 1 elseif l:match('^not ok ') then failed = failed + 1 end
    end
    say(('-- %s: %.1fs'):format(name, secs))
  end
  vim.fn.delete(tmp, 'rf')
end

say(('\n%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
