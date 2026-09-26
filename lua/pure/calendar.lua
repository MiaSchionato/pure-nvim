-- =============================================================================
--  Calendar
-- =============================================================================
--  A month as a grid in a note, one box per day, like a wall calendar:
--
--    ```calendar
--    month: 2026-10          (default: the note's name if it is YYYY-MM,
--                             else the current month)
--    calendars: primary      (which calendars; primary by default)
--    exclude: recurring      (leave out what repeats: work, dailies...)
--    ```
--    <!-- calendar -->
--    ```
--    ┌──────────┬──────────┬ ... ┐
--    │   Seg    │   Ter    │     │
--    ╞══════════╪══════════╪ ... ╡
--    │ 05       │ 06       │     │   <- the day numbers of a week
--    │          │ 14:30    │     │   <- appointments, as many lines as needed
--    │          │ Dentista │     │
--    ├──────────┼──────────┼ ... ┤
--    ```
--    <!-- /calendar -->
--
--  The grid sits in a code block (so Obsidian keeps it monospaced and
--  aligned, and spelling and markdown syntax leave it alone); in Neovim
--  pure/mdview.lua hides the query, the markers and the ``` lines and draws
--  no code background, so only the grid shows.
--
--  In a day's box:
--    14:30 Dentista           an appointment (1 hour: vim.g.pure_calendar_duration)
--    14:30–16:00 Dentista     with its end
--    Feriado                  all day
--    @ Rua X, 10              the place of the appointment above
--      (two spaces)           continues the line above, when it is too long
--    Viagem →  /  ← Viagem    an event of several days (read only)
--
--  Editing: write anywhere in a box, as crooked as it comes out; :w reads
--  the grid back and redraws it aligned, wrapping long text onto the next
--  line of the same box. Rows are understood by their borders, and still
--  when one was deleted or a week separator is gone; a line it cannot place
--  is never dropped: it is kept under the grid, with a warning.
--
--  Inside the grid, keys work on the day under the cursor, not the line
--  (a line of the file crosses the whole week):
--    dd   delete the appointment under the cursor (only that day's)
--    o    a new line for the day under the cursor
--    cc   replace the appointment under the cursor (text, place and all)
--  Outside the grid they are the usual ones.
--
--  :CalendarRefresh  draws the grid of every block in the note that has none
--  :CalendarSync     syncs every grid with Google Calendar now
--  :CalendarAuth     connects Google Calendar (pure/gcal.lua)
--
--  Connected, the grid is two-way: see "Sync with Google Calendar" below.
--  Not connected, a block gets an empty month, a manual calendar tidied on
--  save (vim.g.pure_calendar_source = 'mock': a sample month, for tests).
-- =============================================================================

local M = {}

local api = vim.api
local dw = vim.fn.strdisplaywidth

local BEGIN, END = '<!-- calendar -->', '<!-- /calendar -->'
local ORPHANS = '<!-- calendar: lines that could not be placed; move them into a day -->'

local function width() return tonumber(vim.g.pure_calendar_cell_width) or 25 end
local function duration() return tonumber(vim.g.pure_calendar_duration) or 60 end

local names = {
  pt = { days = { 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom' }, today = '◀ hoje' },
  en = { days = { 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' }, today = '◀ today' },
}
local function locale() return names[vim.g.pure_calendar_locale or 'pt'] or names.pt end

-- -----------------------------------------------------------------------------
--  Text helpers (display width, not bytes: accents, box characters)
-- -----------------------------------------------------------------------------

local function chars(s) return vim.fn.split(s, [[\zs]]) end
local function pad(s, w) return s .. string.rep(' ', math.max(0, w - dw(s))) end
local function center(s, w)
  local left = math.floor((w - dw(s)) / 2)
  return string.rep(' ', left) .. s .. string.rep(' ', math.max(0, w - dw(s) - left))
end

--- The longest start of `s` at most `w` columns wide.
local function takeWidth(s, w)
  local out = ''
  for _, ch in ipairs(chars(s)) do
    if dw(out .. ch) > w then break end
    out = out .. ch
  end
  return out
end

--- Word-wrap `text` into lines of `w` columns; lines after the first start
--- with `prefix`. A word longer than a line is cut.
local function wrap(text, w, prefix)
  local lines, cur = {}, ''
  local function flush() table.insert(lines, cur); cur = prefix end
  for word in text:gmatch('%S+') do
    local sep = (cur == '' or cur == prefix) and '' or ' '
    if dw(cur .. sep .. word) <= w then
      cur = cur .. sep .. word
    else
      if cur ~= '' and cur ~= prefix then flush() end
      while dw(cur .. word) > w do
        local take = takeWidth(word, w - dw(cur))
        cur = cur .. take
        word = word:sub(#take + 1)
        flush()
      end
      cur = cur .. word
    end
  end
  if cur ~= '' and cur ~= prefix then table.insert(lines, cur) end
  return lines
end

-- -----------------------------------------------------------------------------
--  Dates
-- -----------------------------------------------------------------------------

--- The weeks of a month, Monday first: { { [1..7] = day or nil }, ... }.
local function monthWeeks(y, m)
  local t = os.date('*t', os.time({ year = y, month = m, day = 1, hour = 12 }))
  local ndays = os.date('*t', os.time({ year = y, month = m + 1, day = 0, hour = 12 })).day
  local col = (t.wday + 5) % 7 + 1 -- 1 = Monday
  local weeks, week = {}, {}
  for d = 1, ndays do
    week[col] = d
    if col == 7 then
      table.insert(weeks, week)
      week, col = {}, 1
    else
      col = col + 1
    end
  end
  if next(week) then table.insert(weeks, week) end
  return weeks
end

local function addMinutes(hhmm, minutes)
  local h, m = hhmm:match('(%d+):(%d+)')
  local total = tonumber(h) * 60 + tonumber(m) + minutes
  return ('%02d:%02d'):format(math.floor(total / 60) % 24, total % 60)
end

local function normTime(t)
  local h, m = t:match('^(%d%d?):(%d%d)$')
  return h and ('%02d:%s'):format(tonumber(h), m) or nil
end

-- -----------------------------------------------------------------------------
--  Appointments <-> lines of a box
-- -----------------------------------------------------------------------------

--- An appointment from the first line of its text.
local function newEntry(text)
  if text:match('^←') or text:match('→$') then return { ro = true, text = text } end
  -- The en dash is several bytes: it cannot go in a [set], so each dash is
  -- tried on its own.
  local s, e, rest = text:match('^(%d%d?:%d%d)%s*–%s*(%d%d?:%d%d)%s+(.+)$')
  if not s then s, e, rest = text:match('^(%d%d?:%d%d)%s*%-%s*(%d%d?:%d%d)%s+(.+)$') end
  if not s then s, rest = text:match('^(%d%d?:%d%d)%s+(.+)$') end
  if s and normTime(s) then
    s = normTime(s)
    return { start = s, stop = e and normTime(e) or addMinutes(s, duration()), title = rest }
  end
  return { title = text }
end

--- The lines an appointment takes in a box `w` columns wide.
local function entryLines(e, w)
  local text
  if e.ro then
    text = e.text
  elseif e.start then
    local range = e.stop ~= addMinutes(e.start, duration()) and ('–' .. e.stop) or ''
    text = e.start .. range .. ' ' .. e.title
  else
    text = e.title
  end
  local out = wrap(text, w, '  ')
  if e.loc and e.loc ~= '' then vim.list_extend(out, wrap('@ ' .. e.loc, w, '  ')) end
  return out
end

--- All day first (several-day ones first of all), then by time.
local function sortDay(list)
  table.sort(list, function(a, b)
    local ka = a.ro and '0' or (a.start and ('2' .. a.start) or '1')
    local kb = b.ro and '0' or (b.start and ('2' .. b.start) or '1')
    return ka < kb
  end)
end

-- -----------------------------------------------------------------------------
--  Drawing the grid
-- -----------------------------------------------------------------------------

--- The grid lines of month y-m, with `byDay[day] = { entries }`.
local function render(y, m, byDay)
  local w = width()
  local L = locale()
  local now = os.date('*t')
  local today = (now.year == y and now.month == m) and now.day or nil
  local function rule(l, mid, r, fill)
    local seg = fill:rep(w + 2)
    return l .. table.concat({ seg, seg, seg, seg, seg, seg, seg }, mid) .. r
  end
  local function row(cells)
    local out = {}
    for c = 1, 7 do out[c] = ' ' .. pad(cells[c] or '', w) .. ' ' end
    return '│' .. table.concat(out, '│') .. '│'
  end

  local out = { rule('┌', '┬', '┐', '─') }
  local header = {}
  for c = 1, 7 do header[c] = center(L.days[c], w) end
  table.insert(out, row(header))
  table.insert(out, rule('╞', '╪', '╡', '═'))

  local weeks = monthWeeks(y, m)
  for wi, week in ipairs(weeks) do
    local numbers, boxes, height = {}, {}, 0
    for c = 1, 7 do
      local d = week[c]
      if d then
        numbers[c] = ('%02d'):format(d) .. (d == today and ('  ' .. L.today) or '')
        local list = byDay[d] or {}
        sortDay(list)
        local lines = {}
        for _, e in ipairs(list) do vim.list_extend(lines, entryLines(e, w)) end
        boxes[c] = lines
        height = math.max(height, #lines)
      else
        boxes[c] = {}
      end
    end
    table.insert(out, row(numbers))
    -- One blank line more than the fullest day: room to write a new one.
    for i = 1, height + 1 do
      local cells = {}
      for c = 1, 7 do cells[c] = boxes[c][i] end
      table.insert(out, row(cells))
    end
    table.insert(out, wi < #weeks and rule('├', '┼', '┤', '─') or rule('└', '┴', '┘', '─'))
  end
  return out
end

-- -----------------------------------------------------------------------------
--  Reading the grid back
-- -----------------------------------------------------------------------------

local BORDERS = { '─', '═', '┼', '┬', '┴', '├', '┤', '┌', '┐', '└', '┘', '╞', '╪', '╡' }
local function isBorder(line)
  for _, b in ipairs(BORDERS) do line = line:gsub(b, '') end
  return line:match('^%s*$') ~= nil
end

--- The 7 boxes of a grid line, each without its padding space; nil when the
--- line has too few borders to tell. Borders are found by the '│' character,
--- so crooked text is fine; a deleted border is made up for by cutting the
--- merged text at a box's width, and a '│' typed inside a text is told from
--- a border by its distance to where one should be.
local function splitRow(line, w)
  local chs = chars(line)
  local seps, col, cols = {}, 0, {}
  for i, ch in ipairs(chs) do
    cols[i] = col
    if ch == '│' then table.insert(seps, i) end
    col = col + dw(ch)
  end
  if #seps < 1 then return nil end
  -- A line whose first or last border was deleted.
  if seps[1] ~= 1 and table.concat(chs, '', 1, seps[1] - 1):match('%S') then table.insert(seps, 1, 0) end
  if seps[#seps] ~= #chs and table.concat(chs, '', seps[#seps] + 1):match('%S') then table.insert(seps, #chs + 1) end
  if #seps < 2 then return nil end
  local function colOf(i) return i == 0 and -1 or (cols[i] or col) end
  local function seg(a, b) return table.concat(chs, '', a + 1, b - 1) end

  local cells = {}
  if #seps > 8 then
    -- Keep the borders nearest to where they belong, one box width apart.
    local chosen, from = { seps[1] }, 2
    for k = 1, 7 do
      local target = colOf(chosen[#chosen]) + w + 3
      local best, bi
      for j = from, #seps - (7 - k) do
        local d = math.abs(colOf(seps[j]) - target)
        if not best or d < best then best, bi = d, j end
      end
      table.insert(chosen, seps[bi])
      from = bi + 1
    end
    seps = chosen
  end
  for k = 1, #seps - 1 do
    local s = seg(seps[k], seps[k + 1])
    local n = #seps == 8 and 1 or math.max(1, math.floor((dw(s) + 1) / (w + 3) + 0.5))
    for j = 1, n do
      if j < n then
        local take = takeWidth(s, w + 2)
        table.insert(cells, take)
        s = s:sub(#take + 1)
      else
        table.insert(cells, s)
      end
    end
  end
  if #cells ~= 7 then return nil end
  for c = 1, 7 do cells[c] = cells[c]:gsub('^ ', ''):gsub('%s+$', '') end
  return cells
end

--- Whether `cells` is the row of the day numbers of `week`.
local function isNumberRow(cells, week)
  local seen = 0
  for c = 1, 7 do
    if week[c] then
      if tonumber(vim.trim(cells[c]):match('^(%d%d?)')) ~= week[c] then return false end
      seen = seen + 1
    end
  end
  return seen > 0
end

--- Read grid `lines` (month y-m) into { byDay, orphans, entries }. Each
--- entry remembers its day column and the lines (indexes into `lines`) it
--- spans, for the keys that act on the appointment under the cursor.
local function parse(lines, y, m)
  local w = width()
  local L = locale()
  local weeks = monthWeeks(y, m)
  local byDay, orphans, all = {}, {}, {}
  local wk, cur = 0, {}

  local function add(c, text, i)
    if text:match('^%s*$') then return end
    local d = weeks[wk][c]
    if not d then return table.insert(orphans, vim.trim(text)) end
    local e = cur[c]
    if text:match('^%s%s') and e then
      -- Continues the line above: the place, or the text.
      local more = vim.trim(text)
      if e.last == 'loc' then e.loc = e.loc .. ' ' .. more
      elseif e.ro then e.text = e.text .. ' ' .. more
      else e.title = e.title .. ' ' .. more end
      table.insert(e.rows, i)
    elseif text:match('^@') and e then
      e.loc, e.last = vim.trim(text:sub(2)), 'loc'
      table.insert(e.rows, i)
    else
      e = newEntry(vim.trim(text))
      e.day, e.col, e.rows, e.last = d, c, { i }, 'title'
      byDay[d] = byDay[d] or {}
      table.insert(byDay[d], e)
      table.insert(all, e)
      cur[c] = e
    end
  end

  for i, line in ipairs(lines) do
    if not isBorder(line) then
      local cells = splitRow(line, w)
      local is_header = cells and vim.trim(cells[1]) == L.days[1] and vim.trim(cells[7]) == L.days[7]
      if not cells then
        table.insert(orphans, vim.trim(line))
      elseif is_header then
        -- the weekday names
      elseif weeks[wk + 1] and isNumberRow(cells, weeks[wk + 1]) then
        -- A week starts here, separator line or not.
        wk, cur = wk + 1, {}
        for c = 1, 7 do
          if weeks[wk][c] then
            -- Text written after the number is an appointment of that day.
            local rest = vim.trim(cells[c]):gsub('^%d%d?', '', 1)
            rest = vim.trim((rest:gsub(vim.pesc(L.today), '', 1)))
            if rest ~= '' then add(c, rest, i) end
          end
        end
      elseif wk == 0 then
        for c = 1, 7 do
          if cells[c]:match('%S') then table.insert(orphans, vim.trim(cells[c])) end
        end
      else
        for c = 1, 7 do add(c, cells[c], i) end
      end
    end
  end
  return { byDay = byDay, orphans = orphans, entries = all }
end

-- -----------------------------------------------------------------------------
--  Blocks and regions in a note
-- -----------------------------------------------------------------------------

--- Every ```calendar block in `lines`: { first, last (0-based fence rows),
--- month = { y, m } or nil, region = { first, last, open, close } or nil }.
--- The region is the part the plugin writes: its markers, and the rows of
--- the grid's own ``` lines.
local function blocksIn(lines, name)
  local blocks, i = {}, 1
  while i <= #lines do
    if lines[i]:match('^%s*```%s*calendar%s*$') then
      local j = i + 1
      local conf = {}
      while j <= #lines and not lines[j]:match('^%s*```%s*$') do
        local k, v = lines[j]:match('^%s*([%w_]+)%s*:%s*(.-)%s*$')
        if k then conf[k:lower()] = v:gsub('^"(.*)"$', '%1') end
        j = j + 1
      end
      local b = { first = i - 1, last = j - 1, conf = conf }
      local month = conf.month or (name and name:match('^(%d%d%d%d%-%d%d)$')) or os.date('%Y-%m')
      if not month:find('{{', 1, true) then
        local y, m = month:match('^(%d%d%d%d)%-(%d%d)$')
        if y then b.month = { tonumber(y), tonumber(m) } end
      end
      -- The region right under the block.
      if vim.trim(lines[j + 1] or '') == BEGIN then
        local open, close, stop
        for r = j + 2, #lines do
          local t = vim.trim(lines[r])
          if t == END then stop = r break end
          if t == BEGIN or t:match('^```%s*calendar') then break end
          if t:match('^```') then
            if not open then open = r elseif not close then close = r end
          end
        end
        if stop and open and close then
          b.region = { first = j, last = stop - 1, open = open - 1, close = close - 1 }
        end
      end
      table.insert(blocks, b)
      i = j + 1
    else
      i = i + 1
    end
  end
  return blocks
end

local function noteName(buf)
  return vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ':t:r')
end

local function bufBlocks(buf)
  return blocksIn(api.nvim_buf_get_lines(buf, 0, -1, false), noteName(buf))
end

--- The lines of a whole region for these appointments and leftovers.
local function regionLines(b, byDay, orphans)
  local out = { BEGIN, '```' }
  vim.list_extend(out, render(b.month[1], b.month[2], byDay))
  table.insert(out, '```')
  if orphans and #orphans > 0 then
    table.insert(out, ORPHANS)
    vim.list_extend(out, orphans)
  end
  table.insert(out, END)
  return out
end

--- Read a block's region: its appointments and leftovers.
local function readRegion(buf, b)
  local lines = api.nvim_buf_get_lines(buf, b.region.open + 1, b.region.close, false)
  local parsed = parse(lines, b.month[1], b.month[2])
  -- Lines kept from before, under the grid, stay until moved into a day.
  for _, l in ipairs(api.nvim_buf_get_lines(buf, b.region.close + 1, b.region.last, false)) do
    if vim.trim(l) ~= ORPHANS and l:match('%S') then table.insert(parsed.orphans, l) end
  end
  return parsed
end

--- Redraw every grid in `buf` from what is written in it. Returns true when
--- something changed.
function M.format(buf)
  buf = buf or api.nvim_get_current_buf()
  local changed = false
  local blocks = bufBlocks(buf)
  for i = #blocks, 1, -1 do
    local b = blocks[i]
    if b.region and b.month then
      local parsed = readRegion(buf, b)
      local new = regionLines(b, parsed.byDay, parsed.orphans)
      local old = api.nvim_buf_get_lines(buf, b.region.first, b.region.last + 1, false)
      if not vim.deep_equal(old, new) then
        api.nvim_buf_set_lines(buf, b.region.first, b.region.last + 1, false, new)
        changed = true
      end
      if #parsed.orphans > 0 then
        vim.notify(('Calendar: %d line(s) could not be placed in a day; they are under the grid')
          :format(#parsed.orphans), vim.log.levels.WARN)
      end
    end
  end
  return changed
end

-- -----------------------------------------------------------------------------
--  Source of the appointments
-- -----------------------------------------------------------------------------

--- A made-up month, to try the grid before the Google sync exists.
local function mockMonth(y, m)
  local last = os.date('*t', os.time({ year = y, month = m + 1, day = 0, hour = 12 })).day
  local sample = {
    [2] = { { start = '19:00', stop = '20:00', title = 'Aniversário do João', loc = 'Bar do Zé' } },
    [6] = { { start = '14:30', stop = '15:30', title = 'Dentista' } },
    [12] = { { title = 'Feriado — N. Sra. Aparecida' } },
    [15] = { { start = '10:00', stop = '11:00', title = 'Entrega do projeto X' } },
    [17] = { { start = '20:00', stop = '23:00', title = 'Show — Tame Impala', loc = 'Allianz Parque' } },
    [22] = { { start = '09:00', stop = '09:30', title = 'Médico (check-up)' },
             { start = '18:30', stop = '19:30', title = 'Jantar com Ana' } },
    [24] = { { ro = true, text = 'Viagem a Ubatuba →' } },
    [25] = { { ro = true, text = '← Viagem a Ubatuba' } },
    [28] = { { start = '08:00', stop = '09:00', title = 'Voo SP → Rio' },
             { start = '19:00', stop = '20:00', title = 'Reunião do condomínio' } },
  }
  local byDay = {}
  for d, list in pairs(sample) do
    if d <= last then byDay[d] = vim.deepcopy(list) end
  end
  return byDay
end

-- -----------------------------------------------------------------------------
--  Sync with Google Calendar (pure/gcal.lua)
-- -----------------------------------------------------------------------------
--  Same way as the Todoist sync: the grid of each block is rewritten from
--  Google, and what was edited in the grid since the last sync is sent
--  first. What the last sync wrote is remembered in
--  stdpath('data')/calendar_sync.json, so an appointment that differs from
--  it was edited in the note:
--    new line in a day        -> created (in the block's first calendar)
--    text / time / place      -> changed
--    the same text in another day -> moved there
--    line gone                -> deleted
--  vim.g.pure_calendar_confirm: 'delete' (default) asks before deleting,
--  'all' before anything, 'never' never; Enter is No when deleting. Saying
--  no redraws the grid from Google, undoing those edits.
--
--  When: at start, every `interval` minutes (vim.g.pure_calendar_sync =
--  { interval = 15 }, false for never), when a note with a block is opened
--  or saved, and on :CalendarSync. Not: past months (they stay as they
--  were), templates, the trash, notes with unsaved changes.

local function gcal()
  local ok, g = pcall(require, 'pure.gcal')
  return ok and g or nil
end

local function connected()
  local g = gcal()
  return g ~= nil and g.connected()
end

--- Seconds east of UTC of the local time at `t` (daylight saving included).
local function utcOffset(t)
  local u = os.date('!*t', t)
  u.isdst = nil
  return os.difftime(t, os.time(u))
end

--- Local date and time as RFC 3339, with the offset in force then.
local function rfc3339(y, m, d, h, mi)
  local t = os.time({ year = y, month = m, day = d, hour = h or 0, min = mi or 0, sec = 0 })
  local off = utcOffset(t)
  local f = os.date('*t', t)
  return ('%04d-%02d-%02dT%02d:%02d:00%s%02d:%02d'):format(f.year, f.month, f.day, f.hour, f.min,
    off < 0 and '-' or '+', math.floor(math.abs(off) / 3600), math.floor(math.abs(off) % 3600 / 60))
end

--- An RFC 3339 date-time from Google, as local time fields.
local function fromRfc3339(s)
  local Y, Mo, D, h, mi, sec, tz = s:match('^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)[%.%d]*(.*)$')
  if not Y then return nil end
  local off = 0
  local sign, oh, om = tz:match('([+-])(%d%d):?(%d%d)')
  if sign then off = (tonumber(oh) * 60 + tonumber(om)) * 60 * (sign == '-' and -1 or 1) end
  -- These fields read as local time; shifting by the local offset makes
  -- them UTC, then the event's own offset makes the instant.
  local as_local = os.time({ year = Y, month = Mo, day = D, hour = h, min = mi, sec = sec })
  return os.date('*t', as_local + utcOffset(as_local) - off)
end

local function ymd(t) return ('%04d-%02d-%02d'):format(t.year, t.month, t.day) end

--- What an appointment says, to tell whether it was edited.
local function sig(e)
  return table.concat({ e.start or '', e.stop or '', e.title or '', e.loc or '' }, '\31')
end

--- The body Google wants for appointment `e` on y-m-d.
local function eventBody(e, y, m, d)
  local body = { summary = e.title, location = e.loc or '' }
  if e.start then
    local sh, sm = e.start:match('(%d+):(%d+)')
    local eh, em = e.stop:match('(%d+):(%d+)')
    sh, sm, eh, em = tonumber(sh), tonumber(sm), tonumber(eh), tonumber(em)
    -- An end before the start is the next day (22:00–01:00).
    local ed = (eh * 60 + em <= sh * 60 + sm) and d + 1 or d
    body.start = { dateTime = rfc3339(y, m, d, sh, sm) }
    body['end'] = { dateTime = rfc3339(y, m, ed, eh, em) }
  else
    body.start = { date = ymd({ year = y, month = m, day = d }) }
    body['end'] = { date = ymd(os.date('*t', os.time({ year = y, month = m, day = d + 1, hour = 12 }))) }
  end
  return body
end

--- Google events of one calendar as appointments of month y-m, into byDay.
local function toEntries(events, cal, y, m, skip_recurring, byDay)
  local function add(d, e)
    byDay[d] = byDay[d] or {}
    table.insert(byDay[d], e)
  end
  for _, ev in ipairs(events) do
    if ev.status ~= 'cancelled' and not (skip_recurring and ev.recurringEventId) then
      local title = (ev.summary and ev.summary ~= '') and ev.summary:gsub('%s+', ' ') or '(sem título)'
      local loc = ev.location and ev.location ~= '' and ev.location:gsub('%s+', ' ') or nil
      local start, stop = ev.start or {}, ev['end'] or {}
      if start.dateTime then
        local s = fromRfc3339(start.dateTime)
        local e = stop.dateTime and fromRfc3339(stop.dateTime)
        if s and s.year == y and s.month == m then
          local st = ('%02d:%02d'):format(s.hour, s.min)
          add(s.day, { id = ev.id, cal = cal, start = st, title = title, loc = loc,
            stop = e and ('%02d:%02d'):format(e.hour, e.min) or addMinutes(st, duration()) })
        end
      elseif start.date then
        local sy, sm, sd = start.date:match('(%d+)-(%d+)-(%d+)')
        local ey, em, ed = (stop.date or start.date):match('(%d+)-(%d+)-(%d+)')
        local first = os.time({ year = sy, month = sm, day = sd, hour = 12 })
        local last = os.time({ year = ey, month = em, day = ed, hour = 12 }) - 86400
        if last <= first then
          local t = os.date('*t', first)
          if t.year == y and t.month == m then add(t.day, { id = ev.id, cal = cal, title = title, loc = loc }) end
        else
          -- Several days: shown on each, read only.
          local t = first
          while t <= last + 3600 do
            local f = os.date('*t', t)
            if f.year == y and f.month == m then
              local text = (t == first) and (title .. ' →') or (t >= last) and ('← ' .. title) or ('← ' .. title .. ' →')
              add(f.day, { ro = true, text = text, id = ev.id })
            end
            t = t + 86400
          end
        end
      end
    end
  end
end

--- The calendars a block names (its first one gets new appointments).
local function blockCalendars(b)
  local list = {}
  for name in (b.conf.calendars or 'primary'):gmatch('[^,]+') do
    name = vim.trim(name)
    if name ~= '' then table.insert(list, name) end
  end
  return #list > 0 and list or { 'primary' }
end

--- Everything of month y-m in these calendars: `cb(err, byDay)`.
local function fetchMonth(names, y, m, skip_recurring, ids, cb)
  local g = gcal()
  local byDay, i = {}, 0
  local nm = os.date('*t', os.time({ year = y, month = m + 1, day = 1, hour = 12 }))
  local range = ('&timeMin=%s&timeMax=%s'):format(g.urlencode(rfc3339(y, m, 1, 0, 0)),
    g.urlencode(rfc3339(nm.year, nm.month, 1, 0, 0)))
  local function nextCal()
    i = i + 1
    if i > #names then return cb(nil, byDay) end
    local id = ids[names[i]:lower()]
    if not id then return cb(('no calendar named "%s"'):format(names[i])) end
    g.getAll('/calendars/' .. g.urlencode(id) .. '/events?singleEvents=true&orderBy=startTime&maxResults=2500' .. range,
      function(err, events)
        if err then return cb(('calendar "%s": %s'):format(names[i], err)) end
        toEntries(events, id, y, m, skip_recurring, byDay)
        nextCal()
      end)
  end
  nextCal()
end

-- The last sync's output, per region: { key = { { id, cal, day, sig, e } } }.
local baseline_file = vim.fn.stdpath('data') .. '/calendar_sync.json'
local baseline

local function loadBaseline()
  if baseline then return baseline end
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(baseline_file), '\n')) end)
  baseline = ok and type(data) == 'table' and data or {}
  return baseline
end

local function saveBaseline()
  if baseline then pcall(vim.fn.writefile, { vim.json.encode(baseline) }, baseline_file) end
end

local function regionKey(path, b)
  return table.concat({ vim.fs.normalize(path), ('%04d-%02d'):format(b.month[1], b.month[2]),
    table.concat(blockCalendars(b), ','), b.conf.exclude or '' }, '\n')
end

--- What was edited in a region since the last sync, added to `ops`.
local function regionOps(parsed, b, key, ops)
  local old = loadBaseline()[key]
  if not old then return end -- first sync of this grid: nothing to send
  local y, m = b.month[1], b.month[2]
  local cur = {}
  for d, list in pairs(parsed.byDay) do
    for _, e in ipairs(list) do
      if not e.ro then table.insert(cur, { day = d, e = e, sig = sig(e) }) end
    end
  end
  table.sort(cur, function(a, c) return a.day < c.day end)
  local used = {}
  local matched = {}
  local function match(pred)
    for ci, c in ipairs(cur) do
      if not matched[ci] then
        for oi, o in ipairs(old) do
          if not used[oi] and pred(c, o) then
            used[oi], matched[ci] = true, o
            break
          end
        end
      end
    end
  end
  match(function(c, o) return o.day == c.day and o.sig == c.sig end)           -- unchanged
  match(function(c, o) return o.sig == c.sig end)                              -- moved
  match(function(c, o) return o.day == c.day end)                              -- edited
  for ci, c in ipairs(cur) do
    local o = matched[ci]
    local label = ('%02d %s'):format(c.day, entryLines(c.e, 200)[1])
    if not o then
      table.insert(ops.create, { cal = blockCalendars(b)[1], body = eventBody(c.e, y, m, c.day), label = label })
    elseif o.day ~= c.day or o.sig ~= c.sig then
      table.insert(ops.update, { cal = o.cal, id = o.id, body = eventBody(c.e, y, m, c.day), label = label })
    end
  end
  for oi, o in ipairs(old) do
    if not used[oi] then table.insert(ops.delete, { cal = o.cal, id = o.id, label = ('%02d %s'):format(o.day, o.label or '') }) end
  end
end

--- Remember what a region now holds.
local function remember(key, byDay)
  local list = {}
  for d, entries in pairs(byDay) do
    for _, e in ipairs(entries) do
      if not e.ro and e.id then
        table.insert(list, { id = e.id, cal = e.cal, day = d, sig = sig(e), label = entryLines(e, 200)[1] })
      end
    end
  end
  loadBaseline()[key] = list
end

--- Whether a note may be synced: never the templates or the trash.
local function syncable(path)
  local ok, zet = pcall(require, 'pure.zettelkasten')
  local vault = ok and zet.vaultPath() or nil
  if not vault then return true end
  local function key(p)
    p = vim.fs.normalize(p)
    return vim.fn.has('win32') == 1 and p:lower() or p
  end
  local note = key(path)
  for _, folder in ipairs({ zet.templatesPath and zet.templatesPath() or (vault .. '/Templates'),
    vault .. '/' .. ((zet._destinations or {}).Delete or '0-Inbox/Trash') }) do
    local f = key(folder)
    if note:sub(1, #f + 1) == f .. '/' then return false end
  end
  return true
end

local function bufferOf(path)
  path = vim.fs.normalize(path)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and vim.fs.normalize(api.nvim_buf_get_name(buf)) == path then return buf end
  end
end

--- A note's lines (and its buffer, and whether its lines end in CRLF); nil
--- while it has unsaved changes.
local function noteLines(path)
  local buf = bufferOf(path)
  if buf then
    if vim.bo[buf].modified then return nil end
    return api.nvim_buf_get_lines(buf, 0, -1, false), buf, false
  end
  local ok, lines = pcall(vim.fn.readfile, path, 'b')
  if not ok then return nil end
  local cr = 0
  for i, l in ipairs(lines) do
    if l:sub(-1) == '\r' then cr, lines[i] = cr + 1, l:sub(1, -2) end
  end
  return lines, nil, cr > (#lines - 1) / 2
end

--- A region's appointments and leftovers, from a note's lines.
local function regionFrom(lines, b)
  local parsed = parse(vim.list_slice(lines, b.region.open + 2, b.region.close), b.month[1], b.month[2])
  for i = b.region.close + 2, b.region.last do
    local l = lines[i]
    if l and vim.trim(l) ~= ORPHANS and l:match('%S') then table.insert(parsed.orphans, l) end
  end
  return parsed
end

local function pastMonth(b)
  local now = os.date('*t')
  return b.month[1] * 12 + b.month[2] < now.year * 12 + now.month
end

--- Write the synced grids into one note.
local function writeNote(path, fetched)
  local lines, buf, crlf = noteLines(path)
  if not lines then return end
  local blocks = blocksIn(lines, vim.fn.fnamemodify(path, ':t:r'))
  local changed = false
  for i = #blocks, 1, -1 do
    local b = blocks[i]
    local byDay = b.month and fetched[regionKey(path, b)]
    if byDay then
      remember(regionKey(path, b), byDay)
      local orphans = b.region and regionFrom(lines, b).orphans or nil
      local new = regionLines(b, vim.deepcopy(byDay), orphans)
      local s, e = b.last + 1, b.last + 1
      if b.region then s, e = b.region.first, b.region.last + 1 end
      if not vim.deep_equal(vim.list_slice(lines, s + 1, e), new) then
        for _ = s + 1, e do table.remove(lines, s + 1) end
        for k, l in ipairs(new) do table.insert(lines, s + k, l) end
        changed = true
      end
    end
  end
  if not changed then return end
  if buf then
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    -- noautocmd: this write must not start another sync.
    api.nvim_buf_call(buf, function() vim.cmd('silent noautocmd update') end)
  else
    if crlf then
      for k, l in ipairs(lines) do
        if not (k == #lines and l == '') then lines[k] = l .. '\r' end
      end
    end
    vim.fn.writefile(lines, path, 'b')
  end
end

--- The notes to sync: `paths`, or every note of the vault with a block plus
--- the open ones that have one. `cb(paths)`.
local function notesToSync(paths, cb)
  if paths then return cb(paths) end
  local found, seen = {}, {}
  local function add(p)
    p = vim.fs.normalize(p)
    if not seen[p] then seen[p] = true; table.insert(found, p) end
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local name = api.nvim_buf_get_name(buf)
    if api.nvim_buf_is_loaded(buf) and name:match('%.md$') and #bufBlocks(buf) > 0 then add(name) end
  end
  local ok, zet = pcall(require, 'pure.zettelkasten')
  local vault = ok and zet.vaultPath() or nil
  if not vault then return cb(found) end
  local started = pcall(vim.system, { 'rg', '-l', '--glob', '*.md', '-e', [[^\s*```\s*calendar\s*$]], vault },
    { text = true }, vim.schedule_wrap(function(res)
      for p in (res.stdout or ''):gmatch('[^\r\n]+') do add(p) end
      cb(found)
    end))
  if not started then cb(found) end
end

local syncing, pending = false, nil

--- Sync the notes at `paths` (all of them when nil).
function M.sync(paths)
  if not connected() then return end
  if syncing then
    pending = (pending == true or not paths) and true or vim.list_extend(pending or {}, paths)
    return
  end
  syncing = true
  local function finish(err)
    syncing = false
    if err then vim.notify('Calendar sync: ' .. err, vim.log.levels.WARN) end
    if pending then
      local again = pending ~= true and pending or nil
      pending = nil
      M.sync(again)
    end
  end

  notesToSync(paths, function(files)
    local ok, err = pcall(function()
      -- The grids to fetch, and what was edited in them.
      local wanted, notes = {}, {}
      local ops = { create = {}, update = {}, delete = {} }
      for _, path in ipairs(files) do
        local lines = syncable(path) and noteLines(path)
        if lines then
          local any = false
          for _, b in ipairs(blocksIn(lines, vim.fn.fnamemodify(path, ':t:r'))) do
            if b.month and not pastMonth(b) then
              local key = regionKey(path, b)
              wanted[key] = { b = b }
              any = true
              if b.region then regionOps(regionFrom(lines, b), b, key, ops) end
            end
          end
          if any then table.insert(notes, path) end
        end
      end
      if #notes == 0 then return finish() end

      local g = gcal()
      local errors, fetched = {}, {}
      local keys = vim.tbl_keys(wanted)
      local ids = {}

      local function write()
        for _, path in ipairs(notes) do
          local wok, werr = pcall(writeNote, path, fetched)
          if not wok then table.insert(errors, path .. ': ' .. tostring(werr)) end
        end
        saveBaseline()
        finish(#errors > 0 and table.concat(errors, '\n') or nil)
      end
      local function fetchNext(i)
        if i > #keys then return write() end
        local b = wanted[keys[i]].b
        fetchMonth(blockCalendars(b), b.month[1], b.month[2], (b.conf.exclude or ''):find('recurring') ~= nil, ids,
          function(ferr, byDay)
            if ferr then table.insert(errors, ferr) else fetched[keys[i]] = byDay end
            fetchNext(i + 1)
          end)
      end
      local function send()
        local calls = {}
        local function call(method, cal, id, body, what)
          table.insert(calls, function(done)
            local path = '/calendars/' .. g.urlencode(cal) .. '/events' .. (id and ('/' .. g.urlencode(id)) or '')
            g.request(method, path, body, function(cerr, _, status)
              -- Already gone in Google: nothing to report.
              if cerr and status ~= 404 and status ~= 410 then table.insert(errors, what .. ': ' .. cerr) end
              done()
            end)
          end)
        end
        for _, c in ipairs(ops.create) do call('POST', c.cal, nil, c.body, 'create "' .. c.label .. '"') end
        for _, u in ipairs(ops.update) do call('PATCH', u.cal, u.id, u.body, 'change "' .. u.label .. '"') end
        for _, d in ipairs(ops.delete) do call('DELETE', d.cal, d.id, nil, 'delete "' .. d.label .. '"') end
        local function nextCall(i)
          if i > #calls then return fetchNext(1) end
          calls[i](function() nextCall(i + 1) end)
        end
        nextCall(1)
      end

      -- Calendar names to ids first: the fetch needs them whatever is
      -- answered below (without them a named calendar came back empty).
      g.getAll('/users/me/calendarList', function(lerr, list)
        if lerr then return finish(lerr) end
        for _, c in ipairs(list or {}) do
          ids[(c.summary or ''):lower()] = c.id
          ids[(c.id or ''):lower()] = c.id
          if c.primary then ids.primary = c.id end
        end
        ids.primary = ids.primary or 'primary'
        -- Created appointments go to the block's first calendar, by id.
        for _, c in ipairs(ops.create) do c.cal = ids[c.cal:lower()] or c.cal end

        local total = #ops.create + #ops.update + #ops.delete
        if total == 0 then return fetchNext(1) end
        local mode = vim.g.pure_calendar_confirm or 'delete'
        local ask = #api.nvim_list_uis() > 0 and ((mode == 'all') or (mode == 'delete' and #ops.delete > 0))
        if ask then
          local lines = {}
          for _, c in ipairs(ops.create) do table.insert(lines, '+ ' .. c.label) end
          for _, u in ipairs(ops.update) do table.insert(lines, '~ ' .. u.label) end
          for _, d in ipairs(ops.delete) do table.insert(lines, '✗ ' .. d.label) end
          -- Enter is No when something would be deleted.
          local choice = vim.fn.confirm('Send these calendar edits to Google?\n' .. table.concat(lines, '\n'),
            '&Yes\n&No', #ops.delete > 0 and 2 or 1)
          -- No: the grid is redrawn from Google, undoing those edits.
          if choice ~= 1 then return fetchNext(1) end
        end
        send()
      end)
    end)
    if not ok then finish(tostring(err)) end
  end)
end

--- Draw the grid of every block of `buf` that has none yet: from Google
--- when connected, else an empty month to fill by hand (a sample month with
--- vim.g.pure_calendar_source = 'mock', to try it).
function M.refresh(buf)
  buf = (buf and buf ~= 0) and buf or api.nvim_get_current_buf()
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then return end
  -- Never a template (a grid drawn there would be copied into every note
  -- made from it) or the trash, connected or not.
  local name = api.nvim_buf_get_name(buf)
  if name ~= '' and not syncable(name) then return end
  if connected() then
    if name ~= '' and #bufBlocks(buf) > 0 then M.sync({ name }) end
    return
  end
  local blocks = bufBlocks(buf)
  for i = #blocks, 1, -1 do
    local b = blocks[i]
    if b.month and not b.region then
      local byDay = vim.g.pure_calendar_source == 'mock' and mockMonth(b.month[1], b.month[2]) or {}
      api.nvim_buf_set_lines(buf, b.last + 1, b.last + 1, false, regionLines(b, byDay))
    end
  end
end

-- -----------------------------------------------------------------------------
--  For pure/mdview.lua
-- -----------------------------------------------------------------------------

--- Rows mdview hides: the query and the markers and the grid's ``` lines
--- (shown again while the cursor is on them).
function M.hiddenBlocks(buf)
  local ranges = {}
  for _, b in ipairs(bufBlocks(buf)) do
    local r = b.region
    if r then
      table.insert(ranges, { b.first, r.open })
      table.insert(ranges, { r.close, r.close })
      if r.last > r.close then
        -- The end marker; leftover lines stay visible.
        local lines = api.nvim_buf_get_lines(buf, r.close + 1, r.last + 1, false)
        local has_orphans = #lines > 1
        if has_orphans then
          table.insert(ranges, { r.close + 1, r.close + 1 })
        end
        table.insert(ranges, { r.last, r.last })
      end
    end
  end
  return ranges
end

--- Whether a fenced code block starting at `row` is a calendar grid (drawn
--- without the code background).
function M.isGrid(buf, row)
  return row > 0 and vim.trim(api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or '') == BEGIN
end

-- -----------------------------------------------------------------------------
--  Keys that work on the day under the cursor
-- -----------------------------------------------------------------------------

--- The block whose grid holds 0-based `row`, and that row's index in it.
local function gridAt(buf, row)
  for _, b in ipairs(bufBlocks(buf)) do
    local r = b.region
    if r and b.month and row > r.open and row < r.close then return b, row - r.open end
  end
end

--- The day column (1..7) under the cursor.
local function columnAt()
  local col = vim.fn.virtcol('.') - 1
  return math.max(1, math.min(7, math.floor(col / (width() + 3)) + 1))
end

--- The usual `keys`, with the count and register that were typed.
local function feed(keys)
  local cb = vim.o.clipboard
  local default = cb:find('unnamedplus') and '+' or cb:find('unnamed') and '*' or '"'
  local reg = vim.v.register ~= default and ('"' .. vim.v.register) or ''
  api.nvim_feedkeys(reg .. vim.v.count1 .. keys, 'n', false)
end

local function redraw(buf, b, byDay, orphans)
  local new = regionLines(b, byDay, orphans)
  api.nvim_buf_set_lines(buf, b.region.first, b.region.last + 1, false, new)
end

--- dd: delete only the appointment of the day under the cursor.
local function deleteEntry()
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local b, idx = gridAt(buf, row)
  if not b then return feed('dd') end
  local parsed = readRegion(buf, b)
  local c = columnAt()
  for _, e in ipairs(parsed.entries) do
    if e.col == c and vim.tbl_contains(e.rows, idx) then
      local list = parsed.byDay[e.day]
      for k, x in ipairs(list) do
        if x == e then table.remove(list, k) break end
      end
      local cursor = api.nvim_win_get_cursor(0)
      redraw(buf, b, parsed.byDay, parsed.orphans)
      pcall(api.nvim_win_set_cursor, 0, cursor)
      return
    end
  end
end

--- A blank grid line inserted at 0-based `at`, with the cursor in box `c`,
--- in insert mode. Insert, not replace: text longer than the box pushes the
--- borders right instead of writing over them into the next days, and :w
--- wraps it back inside the box.
local function blankLineAt(buf, at, c)
  local w = width()
  api.nvim_buf_set_lines(buf, at, at, false, { '│' .. string.rep(string.rep(' ', w + 2) .. '│', 7) })
  api.nvim_win_set_cursor(0, { at + 1, (c - 1) * (w + 2 + #'│') + #'│' + 1 })
  vim.cmd('startinsert')
end

--- o: a new line for the day under the cursor.
local function openLine()
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local b = gridAt(buf, row)
  if not b then return feed('o') end
  -- On a week's bottom border the new line belongs to the week above it.
  local at = isBorder(api.nvim_get_current_line()) and row or row + 1
  blankLineAt(buf, at, columnAt())
end

--- cc: replace the appointment under the cursor (with the lines it wraps
--- onto and its place) by a new line for the same day.
local function changeEntry()
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local b, idx = gridAt(buf, row)
  if not b then return feed('cc') end
  local parsed = readRegion(buf, b)
  local c = columnAt()
  local found
  for _, e in ipairs(parsed.entries) do
    if e.col == c and vim.tbl_contains(e.rows, idx) then found = e break end
  end
  if found then
    local list = parsed.byDay[found.day]
    for k, x in ipairs(list) do
      if x == found then table.remove(list, k) break end
    end
    redraw(buf, b, parsed.byDay, parsed.orphans)
  end
  -- The new line goes right under the day numbers of that week.
  local blocks = bufBlocks(buf)
  for _, nb in ipairs(blocks) do
    if nb.region and nb.first == b.first then b = nb end
  end
  local lines = api.nvim_buf_get_lines(buf, b.region.open + 1, b.region.close, false)
  local weeks = monthWeeks(b.month[1], b.month[2])
  local target = found and found.day
  local at = row + 1
  if target then
    for i, line in ipairs(lines) do
      local cells = splitRow(line, width())
      for _, week in ipairs(weeks) do
        -- lines[i] is buffer row open + i: the new line goes under it.
        if week[c] == target and cells and isNumberRow(cells, week) then at = b.region.open + i + 1 end
      end
    end
  end
  blankLineAt(buf, at, c)
end

-- -----------------------------------------------------------------------------
--  Setup
-- -----------------------------------------------------------------------------

local group = api.nvim_create_augroup('PureCalendar', { clear = true })

api.nvim_create_autocmd('BufWritePre', {
  group = group,
  pattern = { '*.md', '*.markdown' },
  callback = function(args)
    local view = vim.fn.winsaveview()
    if M.format(args.buf) then vim.fn.winrestview(view) end
  end,
})

api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  pattern = { '*.md', '*.markdown' },
  callback = function(args) M.refresh(args.buf) end,
})

-- Typing in the grid: no automatic line breaks. Notes have a 'textwidth'
-- (110) and a grid line is ~200 columns, so typing there split the line in
-- two, and the halves could no longer be placed in a day.
api.nvim_create_autocmd('InsertEnter', {
  group = group,
  pattern = { '*.md', '*.markdown' },
  callback = function(args)
    local row = api.nvim_win_get_cursor(0)[1] - 1
    if not gridAt(args.buf, row) then return end
    local tw = vim.bo[args.buf].textwidth
    vim.bo[args.buf].textwidth = 0
    api.nvim_create_autocmd('InsertLeave', {
      group = group,
      buffer = args.buf,
      once = true,
      callback = function() vim.bo[args.buf].textwidth = tw end,
    })
  end,
})

api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'markdown',
  callback = function(args)
    if vim.bo[args.buf].buftype ~= '' then return end
    local opts = { buffer = args.buf }
    vim.keymap.set('n', 'dd', deleteEntry, vim.tbl_extend('force', opts, { desc = 'Calendar: delete the day\'s appointment (else dd)' }))
    vim.keymap.set('n', 'o', openLine, vim.tbl_extend('force', opts, { desc = 'Calendar: new line for the day (else o)' }))
    vim.keymap.set('n', 'cc', changeEntry, vim.tbl_extend('force', opts, { desc = 'Calendar: replace the day\'s appointment (else cc)' }))
  end,
})

api.nvim_create_autocmd('BufWritePost', {
  group = group,
  pattern = { '*.md', '*.markdown' },
  callback = function(args)
    if connected() and #bufBlocks(args.buf) > 0 then M.sync({ api.nvim_buf_get_name(args.buf) }) end
  end,
})

do
  local timer
  local function start()
    local conf = vim.g.pure_calendar_sync
    if conf == false or timer then return end
    local minutes = type(conf) == 'table' and tonumber(conf.interval) or 15
    timer = vim.uv.new_timer()
    timer:start(4000, minutes * 60 * 1000, vim.schedule_wrap(function() M.sync() end))
  end
  api.nvim_create_autocmd('VimEnter', { group = group, callback = start })
  if vim.v.vim_did_enter == 1 then start() end
end

api.nvim_create_user_command('CalendarSync', function() M.sync() end, {
  desc = 'Sync every ```calendar grid with Google Calendar now',
})

api.nvim_create_user_command('CalendarRefresh', function()
  M.refresh()
  M.format()
end, { desc = 'Draw and tidy the ```calendar grids of this note' })

-- For tests.
M._render, M._parse, M._splitRow, M._monthWeeks = render, parse, splitRow, monthWeeks

return M
