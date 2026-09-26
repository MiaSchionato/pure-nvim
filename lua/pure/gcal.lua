-- =============================================================================
--  Google Calendar
-- =============================================================================
--  The connection pure/calendar.lua syncs through: authorization, access
--  tokens and the Calendar API v3, through curl.
--
--  Google has no personal token like Todoist: reading and writing your
--  calendars takes OAuth. Once:
--
--    1. console.cloud.google.com: a project, "Google Calendar API" enabled,
--       an OAuth consent screen (External; add yourself as a test user, then
--       "Publish app": while it is in "Testing" the authorization expires
--       every 7 days), and Credentials > Create > OAuth client ID >
--       "Desktop app".
--    2. In Neovim (asked on start, like the Todoist token, or :CalendarAuth):
--       paste the client ID and the client secret; the browser opens,
--       you allow access, done.
--
--  What is kept, in stdpath('data') (never in the repository):
--    google_calendar.json            client ID, client secret, refresh token
--    google_calendar_no_prompt       "never ask on start"
--  Secrets go to curl on stdin, so they never show in the process list.
--
--  Scopes: events (read and write) and the list of calendars (read).
-- =============================================================================

local M = {}

local data_dir = vim.fn.stdpath('data')
local creds_file = data_dir .. '/google_calendar.json'
local no_prompt_file = data_dir .. '/google_calendar_no_prompt'

-- Replaceable, for tests against a local fake.
local function authUrl() return vim.g.pure_calendar_auth_url or 'https://accounts.google.com/o/oauth2/v2/auth' end
local function tokenUrl() return vim.g.pure_calendar_token_url or 'https://oauth2.googleapis.com/token' end
local function apiUrl() return vim.g.pure_calendar_api_url or 'https://www.googleapis.com/calendar/v3' end

local SCOPES = 'https://www.googleapis.com/auth/calendar.events '
  .. 'https://www.googleapis.com/auth/calendar.calendarlist.readonly'

-- -----------------------------------------------------------------------------
--  Credentials
-- -----------------------------------------------------------------------------

local function readCreds()
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(creds_file), '\n')) end)
  return ok and type(data) == 'table' and data or nil
end

local function writeCreds(c)
  vim.fn.mkdir(data_dir, 'p')
  vim.fn.writefile({ vim.json.encode(c) }, creds_file)
  -- Only this user may read it (a no-op on Windows).
  pcall(vim.uv.fs_chmod, creds_file, 384) -- 0600
end

--- Whether Google Calendar is connected.
function M.connected()
  local c = readCreds()
  return c ~= nil and c.refresh_token ~= nil
end

-- -----------------------------------------------------------------------------
--  HTTP
-- -----------------------------------------------------------------------------

local function urlencode(s)
  return (tostring(s):gsub('[^%w%-_%.~]', function(ch) return ('%%%02X'):format(ch:byte()) end))
end

local function urldecode(s)
  return (s:gsub('%+', ' '):gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

local function form(t)
  local parts = {}
  for k, v in pairs(t) do table.insert(parts, urlencode(k) .. '=' .. urlencode(v)) end
  table.sort(parts)
  return table.concat(parts, '&')
end
M.form, M.urlencode = form, urlencode

--- curl `args`; `cb(err, data)` on the main loop with the decoded JSON.
local function curl(args, stdin, cb)
  local cmd = vim.list_extend({ 'curl', '-sS', '-w', '\n%{http_code}' }, args)
  local ok, err = pcall(vim.system, cmd, { stdin = stdin, text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then return cb('curl failed: ' .. vim.trim(res.stderr or '')) end
    local body, status = res.stdout:match('^(.*)\n(%d+)$')
    status = tonumber(status)
    if not status or status >= 300 then
      return cb(('Google %s -> HTTP %s %s'):format(args[#args] and args[#args]:match('^[^?]+') or '',
        tostring(status), vim.trim(body or '')), nil, status)
    end
    if not body or body == '' then return cb(nil, nil) end
    local decoded, data = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
    if not decoded then return cb('Invalid JSON from Google: ' .. tostring(data)) end
    cb(nil, data)
  end))
  if not ok then cb('Could not run curl: ' .. tostring(err)) end
end

--- POST to the token endpoint; the form (with the secrets) goes on stdin.
local function tokenRequest(fields, cb)
  curl({ '-X', 'POST', '-H', 'Content-Type: application/x-www-form-urlencoded', '--data-binary', '@-', tokenUrl() },
    form(fields), cb)
end

local access = { token = nil, expires = 0 }

--- A valid access token, refreshed when it is about to expire.
function M.accessToken(cb)
  if access.token and os.time() < access.expires - 60 then return cb(nil, access.token) end
  local c = readCreds()
  if not (c and c.refresh_token) then return cb('Google Calendar is not connected: run :CalendarAuth') end
  tokenRequest({
    client_id = c.client_id, client_secret = c.client_secret,
    refresh_token = c.refresh_token, grant_type = 'refresh_token',
  }, function(err, data)
    if err then
      if err:find('invalid_grant', 1, true) then
        err = 'The Google authorization expired or was revoked: run :CalendarAuth'
          .. ' (an app left in "Testing" expires every 7 days)'
      end
      return cb(err)
    end
    access.token, access.expires = data.access_token, os.time() + (tonumber(data.expires_in) or 3600)
    cb(nil, access.token)
  end)
end

--- Call the Calendar API; `body` is sent as JSON. `cb(err, data, status)`.
function M.request(method, path, body, cb)
  M.accessToken(function(err, token)
    if err then return cb(err) end
    local args = { '-X', method, '-H', '@-' }
    if body then vim.list_extend(args, { '-H', 'Content-Type: application/json', '--data-binary', vim.json.encode(body) }) end
    table.insert(args, apiUrl() .. path)
    curl(args, 'Authorization: Bearer ' .. token .. '\n', cb)
  end)
end

--- GET every page of a list endpoint; `cb(err, items)`.
function M.getAll(path, cb)
  local items = {}
  local function page(tokenArg)
    local sep = path:find('?', 1, true) and '&' or '?'
    M.request('GET', path .. (tokenArg and (sep .. 'pageToken=' .. urlencode(tokenArg)) or ''), nil, function(err, data)
      if err then return cb(err) end
      vim.list_extend(items, data and data.items or {})
      if data and data.nextPageToken then return page(data.nextPageToken) end
      cb(nil, items)
    end)
  end
  page(nil)
end

-- -----------------------------------------------------------------------------
--  Authorization (once)
-- -----------------------------------------------------------------------------

local function page(ok)
  local msg = ok and 'Neovim is connected to Google Calendar. You can close this tab.'
    or 'Authorization failed or was denied. Go back to Neovim.'
  return 'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n'
    .. '<!doctype html><html><body style="font-family:sans-serif;margin:3em"><h2>' .. msg .. '</h2></body></html>'
end

--- Ask for the client ID and secret, open the browser to allow access, and
--- keep the refresh token Google gives back. The browser is sent back to a
--- one-off server on 127.0.0.1 (Google's "loopback" flow for desktop apps).
function M.auth(done)
  local c = readCreds() or {}
  local ok, id = pcall(vim.fn.input, 'Google OAuth client ID (empty to cancel): ', c.client_id or '')
  id = ok and vim.trim(id) or ''
  if id == '' then return vim.notify('Google Calendar: not connected') end
  local ok2, secret = pcall(vim.fn.inputsecret, 'Client secret: ')
  secret = ok2 and vim.trim(secret) or ''
  if secret == '' then return vim.notify('Google Calendar: not connected') end

  local server = vim.uv.new_tcp()
  server:bind('127.0.0.1', 0)
  local port = server:getsockname().port
  local redirect = ('http://127.0.0.1:%d'):format(port)
  local finished = false
  local function finish() if not finished then finished = true; pcall(function() server:close() end) end end

  server:listen(4, function()
    local client = vim.uv.new_tcp()
    server:accept(client)
    local req = ''
    client:read_start(function(_, chunk)
      if not chunk then return client:close() end
      req = req .. chunk
      if not req:find('\r\n\r\n', 1, true) or finished then return end
      local target = req:match('^GET (%S+)') or ''
      local code = target:match('[?&]code=([^&]+)')
      if not code and not target:find('[?&]error=') then
        -- favicon or another stray request: not the redirect.
        return client:write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n', function() client:close() end)
      end
      client:write(page(code ~= nil), function() client:close() end)
      finish()
      vim.schedule(function()
        if not code then return vim.notify('Google Calendar: authorization denied', vim.log.levels.WARN) end
        tokenRequest({
          code = urldecode(code), client_id = id, client_secret = secret,
          redirect_uri = redirect, grant_type = 'authorization_code',
        }, function(err, data)
          if err or not (data and data.refresh_token) then
            return vim.notify('Google Calendar: could not finish the authorization: '
              .. (err or 'no refresh token'), vim.log.levels.ERROR)
          end
          writeCreds({ client_id = id, client_secret = secret, refresh_token = data.refresh_token })
          access.token, access.expires = data.access_token, os.time() + (tonumber(data.expires_in) or 3600)
          os.remove(no_prompt_file)
          vim.notify('Google Calendar connected')
          if done then done() end
        end)
      end)
    end)
  end)
  -- Five minutes to allow access in the browser.
  vim.defer_fn(function()
    if not finished then
      finish()
      vim.notify('Google Calendar: gave up waiting for the browser; run :CalendarAuth again', vim.log.levels.WARN)
    end
  end, 5 * 60 * 1000)

  local url = authUrl() .. '?' .. form({
    client_id = id, redirect_uri = redirect, response_type = 'code', scope = SCOPES,
    access_type = 'offline', prompt = 'consent',
  })
  -- On Windows vim.ui.open runs `cmd.exe /c start <url>`, and cmd.exe cuts
  -- the URL at its first '&' (a command separator there): the browser got
  -- a broken link, or did not open. rundll32 hands it to the default
  -- browser untouched.
  if vim.fn.has('win32') == 1 then
    pcall(vim.ui.open, url, { cmd = { 'rundll32.exe', 'url.dll,FileProtocolHandler' } })
  else
    pcall(vim.ui.open, url)
  end
  -- Also on the clipboard, to paste into a browser by hand if none opened.
  pcall(vim.fn.setreg, '+', url)
  vim.notify('Allow access in the browser that just opened. If none did, paste the link'
    .. ' (it is on the clipboard) into a browser:\n' .. url)
end

--- On the first start with a UI and no connection, offer to connect, with
--- the option never to be asked again (like the Todoist token).
local function askOnStartup()
  if M.connected() or vim.uv.fs_stat(no_prompt_file) or #vim.api.nvim_list_uis() == 0 then return end
  vim.schedule(function()
    local choice = vim.fn.confirm(
      'Google Calendar is not connected (for ```calendar blocks).\n'
        .. 'Connect now? You need an OAuth client ID and secret: see <leader>fh "pure calendar".',
      '&Yes\n&Later\nNe&ver ask', 1)
    if choice == 1 then
      M.auth(function() pcall(function() require('pure.calendar').sync() end) end)
    elseif choice == 3 then
      vim.fn.mkdir(data_dir, 'p')
      vim.fn.writefile({ 'Delete this file to be asked again, or run :CalendarAuth' }, no_prompt_file)
      vim.notify('Will not ask again. Run :CalendarAuth to connect Google Calendar.')
    end
  end)
end

vim.api.nvim_create_autocmd('VimEnter', {
  group = vim.api.nvim_create_augroup('PureGcal', { clear = true }),
  once = true,
  callback = askOnStartup,
})
if vim.v.vim_did_enter == 1 then askOnStartup() end

vim.api.nvim_create_user_command('CalendarAuth', function()
  M.auth(function() pcall(function() require('pure.calendar').sync() end) end)
end, { desc = 'Connect Google Calendar (OAuth, once)' })

return M
