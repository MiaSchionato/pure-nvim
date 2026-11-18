-- =============================================================================
--  The test helpers, inside the headless Neovim of one spec (tests/run.lua)
-- =============================================================================
--  A spec is a file of tests/spec/ that calls, through the global T:
--
--    T.test(name, fn)        a test; fn fails by raising an error (T.eq, T.ok...)
--    T.eq(got, want, what)   equal (tables compared deeply)
--    T.ok(value, what)       truthy
--    T.match(text, pattern)  a Lua pattern found in text
--    T.vault(rel)            the path of a file of the fixture vault
--    T.read(rel)             its lines
--    T.write(rel, lines)     write it
--    T.edit(rel, row)        open it (cursor on row) and wait for org.nvim to know it
--    T.answers{...}          what vim.fn.confirm / vim.ui.input / vim.ui.select answer
--    T.wait(fn, ms)          wait until fn() is true
--
--  Before each test the fixture vault is copied again from tests/fixtures/ and
--  every buffer is wiped, so tests do not depend on each other.
-- =============================================================================

local H = {}
local tests = {}
local repo = vim.env.XDG_CONFIG_HOME .. '/' .. vim.env.NVIM_APPNAME
local home = vim.env.PURE_TEST_HOME

local function fmt(v) return vim.inspect(v, { newline = ' ', indent = '' }) end

function H.test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

function H.eq(got, want, what)
  if not vim.deep_equal(got, want) then
    error(('%s\n    got:  %s\n    want: %s'):format(what or 'not equal', fmt(got), fmt(want)), 2)
  end
end

function H.ok(v, what) if not v then error((what or 'expected a true value') .. ', got ' .. fmt(v), 2) end end

function H.match(text, pattern, what)
  if type(text) ~= 'string' or not text:find(pattern) then
    error(('%s\n    text:    %s\n    pattern: %s'):format(what or 'no match', fmt(text), pattern), 2)
  end
end

function H.vault(rel, name) return home .. '/' .. (name or 'vault-org') .. (rel and ('/' .. rel) or '') end

function H.exists(rel, name) return vim.uv.fs_stat(H.vault(rel, name)) ~= nil end

function H.read(rel, name) return vim.fn.readfile(H.vault(rel, name)) end

function H.write(rel, lines, name)
  local path = H.vault(rel, name)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(lines, path)
end

function H.wait(fn, ms) return vim.wait(ms or 5000, fn, 20) end

--- Open a note of the vault with the cursor on `row`; for an org note, wait until org.nvim has parsed it.
function H.edit(rel, row, name)
  vim.cmd('edit ' .. vim.fn.fnameescape(H.vault(rel, name)))
  if row then vim.api.nvim_win_set_cursor(0, { row, 0 }) end
  if vim.bo.filetype == 'org' then
    H.wait(function()
      return pcall(function() return require('org.files').get_buffer(0):headline_at(1) or true end)
    end)
  end
end

--- The first row of `rel` whose line matches `pattern`.
function H.row(rel, pattern, name)
  for i, l in ipairs(H.read(rel, name)) do if l:find(pattern) then return i end end
  error('no line of ' .. rel .. ' matches ' .. pattern, 2)
end

-- Answers to the questions a command asks, set per test.
local answers = {}
function H.answers(a) answers = a or {} end

vim.fn.confirm = function() return answers.confirm or 2 end
vim.ui.input = function(_, cb) cb(answers.input) end
vim.ui.select = function(items, _, cb)
  local pick = answers.select
  if type(pick) == 'function' then pick = pick(items) end
  local index
  if pick ~= nil then for i, it in ipairs(items) do if it == pick then index = i break end end end
  cb(pick, index)
end

-- Messages are collected (a test can look at them) instead of drawn.
H.messages = {}
vim.notify = function(msg, level) H.messages[#H.messages + 1] = { msg = msg, level = level } end
function H.lastMessage() local m = H.messages[#H.messages] return m and m.msg end

local function copyTree(src, dst)
  vim.fn.mkdir(dst, 'p')
  for name, kind in vim.fs.dir(src) do
    local s, d = src .. '/' .. name, dst .. '/' .. name
    if kind == 'directory' then copyTree(s, d) else vim.uv.fs_copyfile(s, d) end
  end
end

local function reset()
  vim.cmd('silent! %bwipeout!')
  for name in vim.fs.dir(repo .. '/tests/fixtures') do
    vim.fn.delete(home .. '/' .. name, 'rf')
  end
  copyTree(repo .. '/tests/fixtures', home)
  answers = {}
  H.messages = {}
end

function H.main()
  _G.T = H
  -- What the configuration left for later (vim.schedule, as the insert mode keys) runs first.
  vim.wait(200, function() return false end)
  -- The vault's Obsidian is never started from a test (pure/vault/obsidian.lua): a stub that is always open,
  -- which a spec may replace.
  local okO, obsidian = pcall(require, 'pure.vault.obsidian')
  local function noObsidian()
    if not okO then return end
    obsidian.sys = { running = function() return true end, open = function() end, close = function() end }
    obsidian.pending = {}
  end
  noObsidian()
  local out = {}
  local ok, err = xpcall(dofile, debug.traceback, vim.env.PURE_TEST_SPEC)
  if not ok then
    out[#out + 1] = 'not ok - loading the spec'
    for l in tostring(err):gmatch('[^\n]+') do out[#out + 1] = '  # ' .. l end
  end
  for _, t in ipairs(tests) do
    reset()
    local started = vim.uv.hrtime()
    local passed, msg = xpcall(t.fn, debug.traceback)
    local secs = (vim.uv.hrtime() - started) / 1e9
    out[#out + 1] = (passed and 'ok - ' or 'not ok - ') .. t.name .. (secs > 2 and ('  (%.1fs)'):format(secs) or '')
    if not passed then
      for l in tostring(msg):gmatch('[^\n]+') do
        if not l:find('tests/helper.lua', 1, true) and not l:find('[C]: in function', 1, true) then
          out[#out + 1] = '  # ' .. l
        end
      end
    end
  end
  vim.fn.writefile(out, vim.env.PURE_TEST_RESULT)
  noObsidian() -- before VimLeavePre, which would ask Obsidian to fix what is pending
  vim.cmd('qa!')
end

return H
