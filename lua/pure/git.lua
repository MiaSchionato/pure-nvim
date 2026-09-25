-- =============================================================================
--  Git
-- =============================================================================
--  Everyday git from inside Neovim, no plugins: git itself through
--  vim.system (no shell, so paths with spaces need no quoting on any OS).
--  Every command runs in the repository of the current file.
--
--  The status buffer (M.status) lists staged, unstaged and untracked files;
--  keys act on the file under the cursor:
--    a  stage        u  unstage       r  discard changes (asks first)
--    d  diff         <CR> open file   c  commit        p  push
--    R  refresh      q / <Esc> close
-- =============================================================================

local M = {}

-- -----------------------------------------------------------------------------
--  Running git
-- -----------------------------------------------------------------------------

--- Directory to run git from: the current file's, or the cwd for buffers
--- that are not files (the status buffer keeps its repository in b:pure_git_root).
local function startDir()
  if vim.b.pure_git_root then return vim.b.pure_git_root end
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= '' and vim.bo.buftype == '' then return vim.fs.dirname(name) end
  return vim.fn.getcwd()
end

--- Top level of the repository containing `dir`, or nil.
local function repoRoot(dir)
  local res = vim.system({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if res.code ~= 0 then return nil end
  return vim.fs.normalize(vim.trim(res.stdout))
end

--- Run `git <args>` in `root`; `cb(ok, output)` on the main loop.
--- Without a callback it reports the result as a notification.
local function git(root, args, cb)
  local cmd = vim.list_extend({ 'git', '-C', root }, args)
  vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
    local out = vim.trim((res.stdout or '') .. '\n' .. (res.stderr or ''))
    if cb then return cb(res.code == 0, out) end
    local level = res.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
    vim.notify('git ' .. args[1] .. (out ~= '' and (':\n' .. out) or ' done'), level)
  end))
end

--- The repository root and the current file relative to it, or nil + a message.
local function currentFile()
  local root = repoRoot(startDir())
  if not root then return nil, 'Not inside a git repository' end
  local name = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  if name == '' or vim.bo.buftype ~= '' then return nil, 'No file in this buffer' end
  -- Plain prefix strip: the path may contain '-', '.' or spaces. Case-blind
  -- on Windows, where git may print C:/ for a buffer named c:/ (same file).
  local prefix = name:sub(1, #root + 1)
  local same = vim.fn.has('win32') == 1 and prefix:lower() == (root .. '/'):lower() or prefix == root .. '/'
  if not same then return nil, 'File is outside ' .. root end
  return root, name:sub(#root + 2)
end

--- Reload buffers whose files git just changed (restore, pull, switch).
local function reloadBuffers()
  vim.cmd('checktime')
end

-- -----------------------------------------------------------------------------
--  Single-file and repository commands
-- -----------------------------------------------------------------------------

function M.addFile()
  local root, file = currentFile()
  if not root then return vim.notify(file, vim.log.levels.WARN) end
  git(root, { 'add', '--', file }, function(ok, out)
    vim.notify(ok and ('Staged ' .. file) or out, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end)
end

function M.addAll()
  local root = repoRoot(startDir())
  if not root then return vim.notify('Not inside a git repository', vim.log.levels.WARN) end
  git(root, { 'add', '-A' }, function(ok, out)
    vim.notify(ok and 'Staged all changes' or out, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end)
end

function M.unstageFile()
  local root, file = currentFile()
  if not root then return vim.notify(file, vim.log.levels.WARN) end
  git(root, { 'restore', '--staged', '--', file }, function(ok, out)
    vim.notify(ok and ('Unstaged ' .. file) or out, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end)
end

--- Discard the working-tree changes of `file`. Asks first: they are gone for
--- good, git keeps no copy of uncommitted edits.
local function restore(root, file, done)
  if vim.fn.confirm('Discard all uncommitted changes to ' .. file .. '?', '&Discard\n&Cancel', 2) ~= 1 then
    return
  end
  git(root, { 'restore', '--', file }, function(ok, out)
    vim.notify(ok and ('Restored ' .. file) or out, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    reloadBuffers()
    if done then done() end
  end)
end

function M.restoreFile()
  local root, file = currentFile()
  if not root then return vim.notify(file, vim.log.levels.WARN) end
  restore(root, file)
end

--- Commit what is staged, asking for the message.
function M.commit(done)
  local root = repoRoot(startDir())
  if not root then return vim.notify('Not inside a git repository', vim.log.levels.WARN) end
  local ok, msg = pcall(vim.fn.input, 'Commit message: ')
  if not ok or vim.trim(msg) == '' then return vim.notify('Commit cancelled') end
  git(root, { 'commit', '-m', msg }, function(success, out)
    -- First line is enough: "[branch abc123] message".
    vim.notify(success and out:match('^[^\n]*') or out, success and vim.log.levels.INFO or vim.log.levels.ERROR)
    if done then done() end
  end)
end

function M.push()
  local root = repoRoot(startDir())
  if not root then return vim.notify('Not inside a git repository', vim.log.levels.WARN) end
  vim.notify('git push…')
  git(root, { 'push' })
end

function M.pull()
  local root = repoRoot(startDir())
  if not root then return vim.notify('Not inside a git repository', vim.log.levels.WARN) end
  vim.notify('git pull…')
  git(root, { 'pull' }, function(ok, out)
    vim.notify('git pull:\n' .. out, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    reloadBuffers()
  end)
end

--- Who last changed the cursor line, when, and in which commit.
function M.blameLine()
  local root, file = currentFile()
  if not root then return vim.notify(file, vim.log.levels.WARN) end
  local lnum = vim.fn.line('.')
  git(root, { 'blame', '-L', lnum .. ',' .. lnum, '--porcelain', '--', file }, function(ok, out)
    if not ok then return vim.notify(out, vim.log.levels.ERROR) end
    local sha = out:match('^(%x+)')
    if sha and sha:match('^0+$') then return vim.notify('Line ' .. lnum .. ': not committed yet') end
    local author = out:match('\nauthor (.-)\n') or '?'
    local time = tonumber(out:match('\nauthor%-time (%d+)')) or 0
    local summary = out:match('\nsummary (.-)\n') or ''
    vim.notify(('%s  %s, %s\n%s'):format(sha and sha:sub(1, 7) or '?', author, os.date('%Y-%m-%d', time), summary))
  end)
end

--- Pick a local branch and switch to it.
function M.switchBranch()
  local root = repoRoot(startDir())
  if not root then return vim.notify('Not inside a git repository', vim.log.levels.WARN) end
  git(root, { 'branch', '--format=%(refname:short)' }, function(ok, out)
    if not ok then return vim.notify(out, vim.log.levels.ERROR) end
    local branches = vim.split(out, '\n', { trimempty = true })
    vim.ui.select(branches, { prompt = 'Switch to branch' }, function(branch)
      if not branch then return end
      git(root, { 'switch', branch }, function(sok, sout)
        -- git refuses when local edits would be overwritten; its message says which.
        vim.notify(sok and ('On ' .. branch) or sout, sok and vim.log.levels.INFO or vim.log.levels.ERROR)
        reloadBuffers()
      end)
    end)
  end)
end

-- -----------------------------------------------------------------------------
--  Status buffer
-- -----------------------------------------------------------------------------

local status = { buf = nil, root = nil, rows = {} } -- rows: line number -> { file, section }

--- Parse `git status --porcelain=v1 -b` into the branch line and three lists.
local function parseStatus(out)
  local branch, staged, changed, untracked = '', {}, {}, {}
  for _, line in ipairs(vim.split(out, '\n', { trimempty = true })) do
    if line:sub(1, 2) == '##' then
      branch = line:sub(4)
    else
      local x, y, path = line:sub(1, 1), line:sub(2, 2), line:sub(4)
      -- A rename reads "old -> new"; the new name is the file that exists.
      path = path:match('%-> (.+)$') or path
      path = path:match('^"(.*)"$') or path
      if x == '?' then
        table.insert(untracked, { code = '??', file = path })
      else
        if x ~= ' ' then table.insert(staged, { code = x, file = path }) end
        if y ~= ' ' then table.insert(changed, { code = y, file = path }) end
      end
    end
  end
  return branch, staged, changed, untracked
end

local function refresh()
  if not (status.buf and vim.api.nvim_buf_is_valid(status.buf)) then return end
  git(status.root, { 'status', '--porcelain=v1', '-b' }, function(ok, out)
    if not vim.api.nvim_buf_is_valid(status.buf) then return end
    local lines, rows = {}, {}
    if not ok then
      lines = { '# Git', '', out }
    else
      local branch, staged, changed, untracked = parseStatus(out)
      lines = { '# Git — ' .. branch, '' }
      local function section(title, list, kind)
        if #list == 0 then return end
        table.insert(lines, '## ' .. title)
        for _, e in ipairs(list) do
          table.insert(lines, e.code .. '  ' .. e.file)
          rows[#lines] = { file = e.file, section = kind }
        end
        table.insert(lines, '')
      end
      section('Staged', staged, 'staged')
      section('Changes', changed, 'changed')
      section('Untracked', untracked, 'untracked')
      if #staged + #changed + #untracked == 0 then table.insert(lines, 'Nothing to commit, working tree clean.') end
      table.insert(lines, 'a stage · u unstage · r discard · d diff · <CR> open · c commit · p push · R refresh · q close')
    end
    status.rows = rows
    vim.bo[status.buf].modifiable = true
    vim.api.nvim_buf_set_lines(status.buf, 0, -1, false, lines)
    vim.bo[status.buf].modifiable = false
  end)
end

local function entry()
  return status.rows[vim.fn.line('.')]
end

--- Run `git <args> -- <file>` for the entry under the cursor, then refresh.
local function onEntry(args, fn)
  return function()
    local e = entry()
    if not e then return end
    if fn then return fn(e) end
    git(status.root, vim.list_extend(vim.deepcopy(args), { '--', e.file }), function(ok, out)
      if not ok then vim.notify(out, vim.log.levels.ERROR) end
      refresh()
    end)
  end
end

--- Diff of one entry in a split: staged changes for staged entries, working
--- changes otherwise; an untracked file is shown whole.
local function showDiff(e)
  local args = e.section == 'staged' and { 'diff', '--cached', '--', e.file }
    or e.section == 'untracked' and { 'diff', '--no-index', '--', '/dev/null', e.file }
    or { 'diff', '--', e.file }
  git(status.root, args, function(_, out)
    -- --no-index exits 1 when the files differ, which is always here.
    vim.cmd('botright new')
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(out, '\n'))
    vim.bo[buf].filetype = 'diff'
    vim.bo[buf].modifiable = false
    vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf })
  end)
end

function M.status()
  local root = repoRoot(startDir())
  if not root then return vim.notify('Not inside a git repository', vim.log.levels.WARN) end
  status.root = root

  if not (status.buf and vim.api.nvim_buf_is_valid(status.buf)) then
    local buf = vim.api.nvim_create_buf(false, true)
    status.buf = buf
    vim.bo[buf].bufhidden = 'hide'
    pcall(vim.api.nvim_buf_set_name, buf, 'git://status')
    vim.b[buf].pure_mdview = true -- let mdview draw the ## headings
    vim.bo[buf].filetype = 'markdown'

    local map = function(lhs, fn, desc) vim.keymap.set('n', lhs, fn, { buffer = buf, desc = desc }) end
    map('a', onEntry({ 'add' }), 'Stage file')
    map('u', onEntry({ 'restore', '--staged' }), 'Unstage file')
    map('r', onEntry(nil, function(e)
      if e.section == 'untracked' then
        return vim.notify('Untracked file: delete it yourself if you mean to', vim.log.levels.WARN)
      end
      restore(status.root, e.file, refresh)
    end), 'Discard changes')
    map('d', onEntry(nil, showDiff), 'Show diff')
    map('<CR>', onEntry(nil, function(e)
      vim.cmd('wincmd p')
      vim.cmd('edit ' .. vim.fn.fnameescape(status.root .. '/' .. e.file))
    end), 'Open file')
    map('c', function() M.commit(refresh) end, 'Commit')
    map('p', M.push, 'Push')
    map('R', refresh, 'Refresh')
    map('q', '<cmd>close<cr>', 'Close')
    map('<Esc>', '<cmd>close<cr>', 'Close')
  end
  vim.b[status.buf].pure_git_root = root

  local win = vim.fn.bufwinid(status.buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd('botright split')
    vim.api.nvim_win_set_buf(0, status.buf)
  end
  vim.wo.spell = false
  refresh()
end

return M
