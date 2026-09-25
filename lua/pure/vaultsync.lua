--- :VaultSync: commit, pull, then push the Obsidian vault.
---
--- Why a command instead of typing the git commands: the vault's remote is
--- encrypted with git-remote-gcrypt, and every push gcrypt makes is a forced
--- push (a long-standing bug it warns about on each push). A normal git push is
--- refused when the remote holds commits you have not pulled; a gcrypt push
--- replaces them. Pushing from the PC before pulling what the Mac sent would
--- drop the Mac's notes from the remote. So the order is fixed here instead of
--- left to memory: save, commit, pull, and push only after the pull worked.
---
--- The pull merges (--no-rebase) whatever pull.rebase says. A merge conflict
--- leaves the vault in one state that a single commit resolves, so after the
--- conflict markers are fixed, :VaultSync finishes the job by itself. A rebase
--- can stop once per commit and has to be continued by hand.
---
--- git runs in the background, so Neovim stays usable while ssh and gpg work.
--- gpg asks for its passphrase in a window of its own (pinentry).

local M = {}

local running = false

local function notify(msg, level)
  vim.notify('Vault: ' .. msg, level)
end

--- Run git in `dir` and wait for it. Only callable inside the sync coroutine.
--- @param dir string
--- @param args string[]
--- @return vim.SystemCompleted
local function git(dir, args)
  local co = coroutine.running()
  vim.system(vim.list_extend({ 'git', '-C', dir }, args), {
    text = true,
    -- Never wait for a username or password on a terminal nobody is looking at.
    env = { GIT_TERMINAL_PROMPT = '0' },
  }, function(result)
    vim.schedule(function() coroutine.resume(co, result) end)
  end)
  return coroutine.yield()
end

--- The NUL-separated paths git prints with -z.
--- @param text string|nil
--- @return string[]
local function paths(text)
  return vim.split(text or '', '\0', { trimempty = true })
end

--- @param path string
--- @param dir string
--- @return boolean
local function isInside(path, dir)
  local p, d = vim.fs.normalize(path), vim.fs.normalize(dir)
  if vim.fn.has('win32') == 1 then p, d = p:lower(), d:lower() end
  return p:sub(1, #d + 1) == d .. '/'
end

--- Files git marks as conflicted that still hold conflict markers. One whose
--- markers are gone counts as fixed: the next `git add` marks it resolved.
--- @param dir string
--- @return string[]
local function unresolved(dir)
  local left = {}
  for _, file in ipairs(paths(git(dir, { 'diff', '--name-only', '-z', '--diff-filter=U' }).stdout)) do
    local fh = io.open(dir .. '/' .. file, 'r')
    local text = fh and fh:read('*a') or ''
    if fh then fh:close() end
    if text:find('^<<<<<<< ') or text:find('\n<<<<<<< ') or text:find('\n>>>>>>> ') then
      left[#left + 1] = file
    end
  end
  return left
end

--- @param dir string
--- @param res vim.SystemCompleted
--- @return string
local function output(res)
  local text = vim.trim(res.stderr or '')
  return text ~= '' and text or vim.trim(res.stdout or '')
end

--- @param dir string
local function run(dir)
  -- The branch has to track a remote: that is where the notes go.
  local upstream = vim.trim(git(dir, { 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}' }).stdout or '')
  if upstream == '' then
    return notify('this branch tracks no remote. Push it once with: git push -u <remote> <branch>',
      vim.log.levels.WARN)
  end

  -- A rebase started by hand has to be finished by hand: a commit made now
  -- would land in the middle of it.
  for _, state in ipairs({ 'rebase-merge', 'rebase-apply' }) do
    local path = vim.trim(git(dir, { 'rev-parse', '--git-path', state }).stdout or '')
    if vim.fn.isabsolutepath(path) == 0 then path = dir .. '/' .. path end
    if path ~= '' and vim.uv.fs_stat(path) then
      return notify('a rebase is in progress. Finish it first (git rebase --continue, or --abort)',
        vim.log.levels.WARN)
    end
  end

  -- Conflicts from the last sync come first: `git add -A` would otherwise
  -- commit the conflict markers as if they were notes.
  local left = unresolved(dir)
  if #left > 0 then
    return notify('fix the conflict markers first, then :VaultSync again:\n  ' .. table.concat(left, '\n  '),
      vim.log.levels.WARN)
  end

  -- Notes of the vault still being edited here go in too.
  local saved = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].modified and vim.bo[buf].buftype == '' and name ~= '' and isInside(name, dir) then
      vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
      saved = saved + 1
    end
  end

  -- Commit. A merge left open by a conflict keeps git's own message.
  git(dir, { 'add', '-A' })
  local merging = git(dir, { 'rev-parse', '-q', '--verify', 'MERGE_HEAD' }).code == 0
  local staged = #paths(git(dir, { 'diff', '--cached', '--name-only', '-z' }).stdout)
  if merging or staged > 0 then
    local res = git(dir, merging and { 'commit', '--no-edit' } or {
      'commit', '-m', ('Sync from %s, %s'):format(vim.uv.os_gethostname(), os.date('%Y-%m-%d %H:%M')),
    })
    if res.code ~= 0 then
      return notify('commit failed, nothing was pushed:\n' .. output(res), vim.log.levels.ERROR)
    end
  end

  -- Pull before any push: see the top of this file.
  local before = vim.trim(git(dir, { 'rev-parse', 'HEAD' }).stdout or '')
  local pull = git(dir, { 'pull', '--no-rebase', '--no-edit' })
  vim.cmd.checktime() -- reload the open notes the pull changed
  if pull.code ~= 0 then
    local conflicts = unresolved(dir)
    if #conflicts > 0 then
      return notify(('the same lines changed on both machines. Fix the conflict markers in:\n  %s\n'
        .. 'then :VaultSync again. Nothing was pushed.'):format(table.concat(conflicts, '\n  ')),
        vim.log.levels.WARN)
    end
    return notify('pull failed, nothing was pushed:\n' .. output(pull), vim.log.levels.ERROR)
  end
  local pulled = tonumber(vim.trim(git(dir, { 'rev-list', '--count', before .. '..' .. upstream }).stdout)) or 0

  -- Push only when the remote is missing something.
  local ahead = tonumber(vim.trim(git(dir, { 'rev-list', '--count', upstream .. '..HEAD' }).stdout)) or 0
  if ahead > 0 then
    local push = git(dir, { 'push' })
    if push.code ~= 0 then
      return notify('push failed:\n' .. output(push), vim.log.levels.ERROR)
    end
  end

  local done = {}
  if saved > 0 then done[#done + 1] = ('saved %d note%s'):format(saved, saved == 1 and '' or 's') end
  if staged > 0 then done[#done + 1] = ('committed %d file%s'):format(staged, staged == 1 and '' or 's') end
  if pulled > 0 then done[#done + 1] = ('pulled %d commit%s'):format(pulled, pulled == 1 and '' or 's') end
  if ahead > 0 then done[#done + 1] = 'pushed to ' .. upstream end
  notify(#done > 0 and table.concat(done, ', ') or 'already in sync')
end

--- Save, commit, pull and push the vault, in that order.
function M.sync()
  if running then return notify('a sync is already running') end
  local dir = require('pure.zettelkasten').vaultPath()
  if not dir then
    return notify('no vault set, see :ZettelVault', vim.log.levels.WARN)
  end

  running = true
  notify('syncing…')
  coroutine.wrap(function()
    local ok, err = pcall(run, dir)
    running = false
    if not ok then notify(tostring(err), vim.log.levels.ERROR) end
  end)()
end

vim.api.nvim_create_user_command('VaultSync', M.sync,
  { desc = 'Save, commit, pull, then push the Obsidian vault' })

-- Exposed for tests.
M._busy = function() return running end

return M
