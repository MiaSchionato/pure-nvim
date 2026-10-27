-- =============================================================================
--  Proton Pass
-- =============================================================================
--  Reads secrets from Proton Pass through `pass-cli`, so the Todoist token
--  and the Google Calendar credentials need not live on disk.
--
--  Each secret is one field of one item, set in configs/configs.lua:
--    todoist    the API token
--    calendar   the JSON {"client_id","client_secret","refresh_token"}
--
--  Needs `pass-cli` logged in (`pass-cli login`). When it is missing, logged
--  out or the item does not exist, get() returns nil and the callers fall back
--  to their local files.
--
--  Settings (all optional):
--    vim.g.pure_protonpass        false to turn it off (default true)
--    vim.g.pure_protonpass_vault  vault name (default 'Personal')
--    vim.g.pure_protonpass_items  { todoist = { title = , field = , vault = },
--                                   calendar = { ... } }; each key falls back
--                                   to the default below
-- =============================================================================

local M = {}

local cache = {} -- title -> { value = string|nil, time = os.time() }
local RETRY = 60 -- seconds before asking again after a failure

local function enabled()
  return vim.g.pure_protonpass ~= false and vim.fn.executable('pass-cli') == 1
end

local DEFAULTS = {
  todoist = { title = 'nvim-todoist', field = 'note' },
  calendar = { title = 'nvim-google-calendar', field = 'note' },
}

--- Where secret `name` lives: { vault, title, field }.
local function spec(name)
  local user = (vim.g.pure_protonpass_items or {})[name] or {}
  local d = DEFAULTS[name] or {}
  return {
    vault = user.vault or vim.g.pure_protonpass_vault or 'Personal',
    title = user.title or d.title or name,
    field = user.field or d.field or 'note',
  }
end

local pending = {} -- name -> running vim.system job (see prefetch)
local waiters = {} -- callbacks of on_ready, run once nothing is pending

--- Store the outcome of a read. Idempotent: the first finisher (the job's own
--- callback or a get() that waited on it) wins, the other is a no-op.
local function finish(name, res)
  if not pending[name] then return end
  pending[name] = nil
  local value = res.code == 0 and vim.trim(res.stdout or '') or ''
  cache[name] = { value = value ~= '' and value or nil, time = os.time() }
  if next(pending) == nil then
    local cbs = waiters
    waiters = {}
    for _, cb in ipairs(cbs) do vim.schedule(cb) end
  end
end

local function start(name)
  local s = spec(name)
  pending[name] = true -- set first: the job's callback may run before vim.system returns
  pending[name] = vim.system({ 'pass-cli', 'item', 'view', '--vault-name', s.vault, '--item-title', s.title,
    '--field', s.field }, { text = true }, vim.schedule_wrap(function(res) finish(name, res) end))
end

--- Read the secrets in the background, in parallel, so the first get() finds
--- them in memory instead of waiting on pass-cli (about half a second each).
function M.prefetch(names)
  if not enabled() then return end
  for _, name in ipairs(names or vim.tbl_keys(DEFAULTS)) do
    local hit = cache[name]
    if not pending[name] and not (hit and (hit.value or os.time() - hit.time < RETRY)) then start(name) end
  end
end

--- Run `cb` (on the main loop) once no background read is pending; right away
--- when none is.
function M.on_ready(cb)
  if next(pending) == nil then return vim.schedule(cb) end
  table.insert(waiters, cb)
end

--- The value of secret `name` ('todoist' or 'calendar'), or nil. Kept in memory
--- for the session: pass-cli takes a moment, and callers ask on every request.
--- Waits for a background read of it when one is running.
function M.get(name)
  if not enabled() then return nil end
  local hit = cache[name]
  if hit and (hit.value or os.time() - hit.time < RETRY) then return hit.value end
  if not pending[name] then start(name) end
  finish(name, pending[name]:wait(10000))
  return cache[name] and cache[name].value
end

--- Replace the value of secret `name`. Returns true on success.
function M.set(name, value)
  if not enabled() then return false end
  local s = spec(name)
  local res = vim.system({ 'pass-cli', 'item', 'update', '--vault-name', s.vault, '--item-title', s.title,
    '--field', s.field .. '=' .. value }, { text = true }):wait(10000)
  if res.code == 0 then cache[name] = { value = value, time = os.time() } end
  return res.code == 0
end

--- Forget what was read (after changing the item by hand).
function M.reset() cache = {} end

return M
