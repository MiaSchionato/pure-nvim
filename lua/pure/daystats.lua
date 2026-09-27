-- =============================================================================
--  Day stats
-- =============================================================================
--  The measured picture of one day, as plain text, for Claude actions that
--  ask for it (`context: daystats`, see claude.lua): screen time, the apps
--  used and the projects open in the editing apps (ActivityWatch), focus per
--  task from a focus log in the vault, and the sleep window.
--
--  Only totals, except the window titles of the work apps below, which are
--  read to name the project (a Premiere .prproj, an After Effects .aep…).
--  A day runs from vim.g.pure_daystats_day_start to the same hour the next
--  day, so a night past midnight still belongs to its day.
--
--    require('pure.daystats').text()              today
--    require('pure.daystats').text('2026-09-26')  another day
--
--    vim.g.pure_daystats_aw = 'http://127.0.0.1:5600'   ActivityWatch server
--    vim.g.pure_daystats_day_start = 5                  hour the day starts
--    vim.g.pure_daystats_focus_log = nil   vault-relative path of the focus
--        log; its lines: `- YYYY-MM-DD HH:MM:SS · event · task [project] · detail`
--    vim.g.pure_daystats_sleep = nil       { after = 60, before = { 60, 120 } }:
--        asleep up to `after` minutes after the PC closed, awake `before`
--        minutes before its first use. Without it, only the two times.
--    vim.g.pure_daystats_work_apps = nil   { ['app.exe'] = 'Name' }, instead
--        of the editing apps below
-- =============================================================================

local M = {}

local WORK_APPS = {
  ['Adobe Premiere Pro.exe'] = 'Premiere', ['AfterFX.exe'] = 'After Effects',
  ['Resolve.exe'] = 'Resolve', ['Photoshop.exe'] = 'Photoshop',
  ['Illustrator.exe'] = 'Illustrator', ['Adobe Media Encoder.exe'] = 'Media Encoder',
}
local PROJECT_FILES = { 'prproj', 'aep', 'drp', 'psd', 'ai' }

-- -----------------------------------------------------------------------------
--  Helpers
-- -----------------------------------------------------------------------------

local function duration(seconds)
  local total = math.floor(seconds / 60 + 0.5)
  if total >= 60 then return ('%dh%02d'):format(math.floor(total / 60), total % 60) end
  return total .. ' min'
end

local function clock(epoch) return os.date('%H:%M', epoch) end

--- Seconds east of UTC at `epoch` (daylight saving included).
local function utcOffset(epoch)
  local here, utc = os.date('*t', epoch), os.date('!*t', epoch)
  utc.isdst = here.isdst
  return os.difftime(os.time(here), os.time(utc))
end

--- ActivityWatch timestamps are UTC: "2026-09-26T10:48:07.451000+00:00".
local function parseUtc(stamp)
  local y, mo, d, h, mi, s = stamp:match('^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)')
  local frac = tonumber('0' .. (stamp:match('^%d+%-%d+%-%d+T%d+:%d+:%d+(%.%d+)') or '')) or 0
  local asLocal = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  return asLocal + utcOffset(asLocal) + frac
end

local function isoUtc(epoch) return os.date('!%Y-%m-%dT%H:%M:%SZ', epoch) end

local function get(url)
  local res = vim.system({ 'curl', '-s', '--max-time', '60', url }, { text = true }):wait()
  if res.code ~= 0 then error('ActivityWatch is not answering') end
  return vim.json.decode(res.stdout)
end

local function sorted(counts)
  local list = {}
  for k, v in pairs(counts) do table.insert(list, { k, v }) end
  table.sort(list, function(x, y) return x[2] > y[2] end)
  return list
end

-- -----------------------------------------------------------------------------
--  ActivityWatch
-- -----------------------------------------------------------------------------

local buckets -- name prefix -> bucket id, found once per report

local function events(prefix, from, to)
  local server = (vim.g.pure_daystats_aw or 'http://127.0.0.1:5600') .. '/api/0'
  if not buckets then
    buckets = {}
    for id in pairs(get(server .. '/buckets/')) do buckets[id:match('^(.-)_') or id] = id end
  end
  local id = buckets[prefix] or error('ActivityWatch has no ' .. prefix .. ' bucket')
  return get(('%s/buckets/%s/events?start=%s&end=%s&limit=300000'):format(server, id, isoUtc(from), isoUtc(to)))
end

--- Merged "not-afk" intervals within [from, to). The AFK bucket repeats
--- events, so they are merged, never summed as they come.
local function active(from, to)
  local raw = {}
  for _, e in ipairs(events('aw-watcher-afk', from, to)) do
    if e.data.status == 'not-afk' then
      local a = parseUtc(e.timestamp)
      local b = math.min(a + e.duration, to)
      a = math.max(a, from)
      if b > a then table.insert(raw, { a, b }) end
    end
  end
  table.sort(raw, function(x, y) return x[1] < y[1] end)
  local merged = {}
  for _, iv in ipairs(raw) do
    local last = merged[#merged]
    if last and iv[1] <= last[2] then last[2] = math.max(last[2], iv[2]) else table.insert(merged, iv) end
  end
  return merged
end

local function overlap(intervals, a, b)
  local total = 0
  for _, iv in ipairs(intervals) do
    if iv[2] > a and iv[1] < b then total = total + math.min(b, iv[2]) - math.max(a, iv[1]) end
  end
  return total
end

local function screen(out, from, to)
  table.insert(out, '## Screen (ActivityWatch)')
  local act = active(from, to)
  if #act == 0 then return table.insert(out, 'No PC activity in this day.') end
  local total = 0
  for _, iv in ipairs(act) do total = total + iv[2] - iv[1] end
  table.insert(out, ('Active: %s, from %s to %s'):format(duration(total), clock(act[1][1]), clock(act[#act][2])))

  local work_apps = vim.g.pure_daystats_work_apps or WORK_APPS
  local apps, projects, design = {}, {}, 0
  for _, e in ipairs(events('aw-watcher-window', from, to)) do
    local a = parseUtc(e.timestamp)
    local seconds = overlap(act, a, a + e.duration)
    if seconds > 0 then
      local app, title = e.data.app or '?', e.data.title or ''
      apps[app] = (apps[app] or 0) + seconds
      if app == 'claude.exe' and title == 'Design' then design = design + seconds end
      if work_apps[app] then
        for _, ext in ipairs(PROJECT_FILES) do
          local name = title:match('([^\\/]+)%.' .. ext)
          if name then
            local key = work_apps[app] .. ': ' .. name
            projects[key] = (projects[key] or 0) + seconds
            break
          end
        end
      end
    end
  end
  local top, working = {}, 0
  for i, item in ipairs(sorted(apps)) do
    if i <= 8 then table.insert(top, item[1] .. ' ' .. duration(item[2])) end
    if work_apps[item[1]] then working = working + item[2] end
  end
  table.insert(out, 'Top apps: ' .. table.concat(top, ', '))
  table.insert(out, ('Work apps: %s. Claude Design: %s'):format(duration(working), duration(design)))
  for _, item in ipairs(sorted(projects)) do
    table.insert(out, ('  project %s: %s'):format(item[1], duration(item[2])))
  end
end

local function sleep(out, from)
  table.insert(out, '## Sleep window')
  local before, after = active(from - 86400, from), active(from, from + 86400)
  if #before == 0 or #after == 0 then return table.insert(out, 'Not enough ActivityWatch data.') end
  local closed, first = before[#before][2], after[1][1]
  table.insert(out, ('PC closed at %s; first activity at %s.'):format(os.date('%d/%m %H:%M', closed),
    os.date('%d/%m %H:%M', first)))
  local rule = vim.g.pure_daystats_sleep
  if rule then
    local b = rule.before or { 60, 120 }
    table.insert(out, ('Estimate: asleep by %s-%s, awake since %s-%s.'):format(clock(closed),
      clock(closed + (rule.after or 60) * 60), clock(first - b[2] * 60), clock(first - b[1] * 60)))
  end
end

-- -----------------------------------------------------------------------------
--  Focus log
-- -----------------------------------------------------------------------------

local function seconds(text)
  local total = 0
  for part in text:gmatch('%d+') do total = total * 60 + tonumber(part) end
  return total
end

--- The sessions of the focus log. A session starts with "started" (or
--- "already running…") and ends with "completed" or "ended, not completed".
local function logSessions(path)
  local sessions, current = {}, nil
  for _, line in ipairs(vim.fn.readfile(path)) do
    local stamp, event, task, detail = line:match('^%- (%S+ %S+) · (.-) · (.*) · (.-)$')
    if stamp then
      local y, mo, d, h, mi, s = stamp:match('(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)')
      local at = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
      local focus = detail:match('focus (%d+:[%d:]+)')
      if event == 'started' or event:match('^already running') then
        local title, project = task:match('^(.-) %[([^%]]+)%]$')
        current = { task = task, title = title or task, project = project or 'no project', start = at,
          late = event ~= 'started', status = 'open', focus = focus and seconds(focus) or 0,
          paused = detail:find('paused', 1, true) ~= nil, pauses = 0 }
        table.insert(sessions, current)
      elseif current and task == current.task then
        if focus then current.focus = seconds(focus) end
        if event == 'paused' then
          current.paused, current.pauses = true, current.pauses + 1
        elseif event == 'resumed' then
          current.paused = false
        elseif event == 'completed' or event == 'ended, not completed' then
          current.status, current = event, nil
        end
      end
    end
  end
  return sessions
end

local function focus(out, from, to)
  local rel = vim.g.pure_daystats_focus_log
  if not rel then return end
  table.insert(out, '## Focus (focus log)')
  local ok, zet = pcall(require, 'pure.zettelkasten')
  local vault = ok and zet.vaultPath and zet.vaultPath()
  local path = vault and (vault .. '/' .. rel) or vim.fn.expand(rel)
  if vim.fn.filereadable(path) == 0 then return table.insert(out, 'Focus log not found: ' .. rel) end
  local totals, any = {}, false
  for _, s in ipairs(logSessions(path)) do
    if s.start >= from and s.start < to then
      any = true
      totals[s.project] = (totals[s.project] or 0) + s.focus
      local state = s.status ~= 'open' and s.status or (s.paused and 'open, paused' or 'open, running')
      local began = (s.late and 'already running when first logged at %s' or 'started %s'):format(clock(s.start))
      table.insert(out, ('- %s [%s] %s: focus %s, %s, %d pause(s)'):format(s.title, s.project, began,
        duration(s.focus), state, s.pauses))
    end
  end
  if not any then return table.insert(out, 'No session in this day.') end
  local parts = {}
  for _, item in ipairs(sorted(totals)) do table.insert(parts, item[1] .. ' ' .. duration(item[2])) end
  table.insert(out, 'Focus by project: ' .. table.concat(parts, ', '))
end

-- -----------------------------------------------------------------------------
--  The report
-- -----------------------------------------------------------------------------

--- The measured day `date` ("YYYY-MM-DD", default today) as text.
function M.text(date)
  buckets = nil
  local start_hour = vim.g.pure_daystats_day_start or 5
  local now = os.time()
  local y, mo, d
  if date then
    y, mo, d = date:match('^(%d+)%-(%d+)%-(%d+)$')
  else
    local t = os.date('*t', now - start_hour * 3600)
    y, mo, d = t.year, t.month, t.day
  end
  local from = os.time({ year = y, month = mo, day = d, hour = start_hour })
  local out = { ('# Measured day %s (now %s)'):format(os.date('%Y-%m-%d', from), os.date('%Y-%m-%d %H:%M', now)) }
  for _, section in ipairs({
    function() focus(out, from, from + 86400) end,
    function() screen(out, from, math.min(from + 86400, now)) end,
    function() sleep(out, from) end,
  }) do
    local ok, err = pcall(section)
    -- One missing source must not hide the others.
    if not ok then table.insert(out, '(unavailable: ' .. tostring(err) .. ')') end
    table.insert(out, '')
  end
  return vim.trim(table.concat(out, '\n'))
end

return M
