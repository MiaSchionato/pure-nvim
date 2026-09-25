-- =============================================================================
--  Update
-- =============================================================================
--  One key to bring this machine up to date: the configuration's own git
--  repository first, then the plugins.
--
--    :PureUpdate        (u on the dashboard)
--
--  1. git fetch in the config folder (stdpath('config')), in the background.
--     Works for a clone of main / windows and for the single-file branch.
--  2. New commits upstream: lists them and asks; yes pulls with --ff-only.
--     Commits made here and not pushed yet, or a pull that would overwrite
--     local changes: nothing is touched, and the message says why.
--  3. After a pull: offers to restart Neovim (:restart), so the new
--     configuration is what runs; press u again then for the plugins (a new
--     configuration may list different ones). Declining updates them now.
--  4. Otherwise: the plugins, silently. vim.pack.update() is run by a
--     separate headless Neovim with force = true: no report buffer to
--     confirm, no progress messages, and the editor is not blocked while it
--     downloads (vim.pack waits for every plugin before returning). One
--     notification at the end names the plugins that changed. Not in the
--     portable one-file build, which has no plugins.
--
--  Every question defaults to Yes: Enter answers it.
-- =============================================================================

local M = {}

--- Run git in the config folder; `cb(ok, output)` on the main loop.
local function git(args, cb)
  local cmd = vim.list_extend({ 'git', '-C', vim.fn.stdpath('config') }, args)
  local ok = pcall(vim.system, cmd, { text = true }, vim.schedule_wrap(function(res)
    local out = res.code == 0 and res.stdout or res.stderr
    cb(res.code == 0, vim.trim(out or ''))
  end))
  if not ok then cb(false, 'git is not installed') end
end

-- Run by the headless Neovim: update every installed plugin and print the
-- names of those whose revision changed.
local update_script = [[
local before = {}
for _, p in ipairs(vim.pack.get(nil, { info = false })) do before[p.spec.name] = p.rev end
vim.pack.update(nil, { force = true })
local changed = {}
for _, p in ipairs(vim.pack.get(nil, { info = false })) do
  if before[p.spec.name] ~= p.rev then table.insert(changed, p.spec.name) end
end
io.stdout:write(table.concat(changed, ', '))
]]

local updating = false

--- Update the plugins in the background (see 4. above).
local function plugins()
  if vim.g.pure_portable or not (vim.pack and vim.pack.update) or updating then return end
  updating = true
  local cmd = { vim.v.progpath, '--headless', '-u', 'NONE', '-c', 'lua ' .. update_script, '-c', 'qa!' }
  local ok = pcall(vim.system, cmd, { text = true }, vim.schedule_wrap(function(res)
    updating = false
    local changed = vim.trim(res.stdout or '')
    if res.code ~= 0 then
      vim.notify('Plugin update failed: ' .. vim.trim(res.stderr or ''), vim.log.levels.WARN)
    elseif changed ~= '' then
      vim.notify('Plugins updated: ' .. changed .. '. Restart Neovim to use them.')
    else
      vim.notify('Plugins up to date')
    end
  end))
  if not ok then updating = false end
end

--- Whether :restart can bring the open files back. It saves the session to
--- the temp folder and sources it on the new Neovim through a Lua string
--- built from fnameescape(): with a space in that path ("C:/Users/Mia
--- Schionato/...") the escaped "\ " is an invalid Lua escape, and the new
--- Neovim starts with "E5107: invalid escape sequence" in UIEnter. Checked
--- on Neovim 0.12.5; the same folder its runtime (vim/_core/server.lua) uses.
local function sessionRestartWorks()
  local dir = vim.fs.abspath(vim.fs.dirname(vim.fs.dirname(vim.fn.tempname())))
  return vim.fn.fnameescape(dir) == dir
end

--- After a pull: restart now, or say that the new configuration needs one.
local function offerRestart(count)
  local msg = ('Configuration updated (%d new commit%s).'):format(count, count == 1 and '' or 's')
  if vim.fn.exists(':restart') == 2 and #vim.api.nvim_list_uis() > 0 then
    local keep = sessionRestartWorks()
    local question = keep and 'Restart Neovim now to load it?'
      or 'Restart Neovim now to load it? (open files are not reopened)'
    if vim.fn.confirm(msg .. '\n' .. question, '&Yes\n&No', 1) == 1 then
      -- restart! skips the session, and with it the broken path above.
      return vim.cmd(keep and 'restart' or 'restart!')
    end
  end
  vim.notify(msg .. ' Restart Neovim to load it.')
  plugins()
end

--- Pull the configuration if upstream has new commits, then the plugins.
function M.run()
  git({ 'rev-parse', '--is-inside-work-tree' }, function(is_repo)
    if not is_repo then
      vim.notify('The config folder is not a git repository: updating plugins only')
      return plugins()
    end
    git({ 'rev-parse', '--abbrev-ref', '@{upstream}' }, function(has_upstream, upstream)
      if not has_upstream then
        vim.notify('This branch has no upstream to pull from: updating plugins only')
        return plugins()
      end
      vim.notify('Checking ' .. upstream .. '…')
      git({ 'fetch', '--quiet' }, function(fetched, err)
        if not fetched then
          vim.notify('git fetch failed: ' .. err, vim.log.levels.WARN)
          return plugins()
        end
        git({ 'rev-list', '--left-right', '--count', 'HEAD...@{upstream}' }, function(_, counts)
          local ahead, behind = counts:match('(%d+)%s+(%d+)')
          ahead, behind = tonumber(ahead) or 0, tonumber(behind) or 0

          if behind == 0 then
            vim.notify(ahead > 0
              and ('Configuration up to date; %d local commit(s) not pushed yet'):format(ahead)
              or 'Configuration up to date')
            return plugins()
          end
          if ahead > 0 then
            -- --ff-only would refuse anyway; say why instead of failing.
            vim.notify(('This machine has %d commit(s) not pushed and %s has %d new: '
              .. 'pull by hand (git pull) to merge them'):format(ahead, upstream, behind), vim.log.levels.WARN)
            return plugins()
          end

          git({ 'log', '--oneline', '--no-decorate', '-15', 'HEAD..@{upstream}' }, function(_, log)
            local more = behind > 15 and ('\n… and %d more'):format(behind - 15) or ''
            local choice = #vim.api.nvim_list_uis() == 0 and 1 or vim.fn.confirm(
              ('%d new commit(s) on %s:\n%s%s\n\nPull them?'):format(behind, upstream, log, more), '&Yes\n&No', 1)
            if choice ~= 1 then return plugins() end

            git({ 'pull', '--ff-only', '--quiet' }, function(pulled, perr)
              if not pulled then
                -- Usually local edits to a file the pull changes.
                vim.notify('git pull failed, nothing was changed:\n' .. perr, vim.log.levels.WARN)
                return plugins()
              end
              offerRestart(behind)
            end)
          end)
        end)
      end)
    end)
  end)
end

vim.api.nvim_create_user_command('PureUpdate', M.run, {
  desc = 'Pull new commits of the configuration, then update the plugins',
})

return M
