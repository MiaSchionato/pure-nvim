-- =============================================================================
--  Key hints  (a pure Lua take on which-key)
-- =============================================================================
--  Press <leader> and wait: a window at the bottom lists every key that can
--  come next, with the mapping's description, and names the groups
--  (<leader>f -> Find). Keep typing and it narrows down.
--
--  How it works: <leader> is a buffer-local <nowait> mapping (the "trigger"),
--  so it fires at once. It then reads the next keys itself with getcharstr(),
--  opening the window when nothing is typed for a while. Once the keys name
--  exactly one mapping, the trigger is removed for a moment and the keys are
--  typed again, so the real mapping runs just as if the hint window had never
--  been there. Typed quickly, nothing is shown and nothing is slower.
--
--  While it waits:  <BS> one key back   <Esc> cancel
--                   <CR> run the mapping typed so far, when a longer one
--                        shares its keys
--
--  Settings (configs.lua / keymaps.lua):
--    vim.g.pure_keyhint_delay     ms before the window shows (default 1000)
--    vim.g.pure_keyhint_groups    { ['<leader>f'] = 'Find', ... }
--    vim.g.pure_keyhint_triggers  { { 'n', '<leader>' }, { 'x', '<leader>' } }
--    vim.g.pure_keyhint = false   turns it off
-- =============================================================================

local M = {}
local api = vim.api

local ESC, BS, CR = vim.keycode('<Esc>'), vim.keycode('<BS>'), vim.keycode('<CR>')
local ns = api.nvim_create_namespace('pure_keyhint')

-- Linked, so the window follows the colorscheme.
local function setHighlights()
  local links = {
    PureHintKey = 'Function',
    PureHintGroup = 'Keyword',
    PureHintDesc = 'NormalFloat',
    PureHintSep = 'Comment',
  }
  for name, target in pairs(links) do
    api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

local function triggers()
  return vim.g.pure_keyhint_triggers or { { 'n', '<leader>' }, { 'x', '<leader>' } }
end

--- The first key of raw key bytes: one character, or a 3-byte special key
--- (<BS>, <F1>, ...), with its modifier prefix if it has one (<M-x>).
local function firstKey(s)
  if s:byte(1) == 0x80 then
    if s:byte(2) == 0xfc then return s:sub(1, 3) .. firstKey(s:sub(4)) end
    return s:sub(1, 3)
  end
  return vim.fn.strcharpart(s, 0, 1)
end

--- Truncate to a display width, ending in '…' when cut.
local function fit(s, width)
  if vim.fn.strdisplaywidth(s) <= width then return s end
  local out = ''
  for _, ch in ipairs(vim.fn.split(s, [[\zs]])) do
    if vim.fn.strdisplaywidth(out .. ch) >= width then break end
    out = out .. ch
  end
  return out .. '…'
end

--- Every mapping of `mode` whose keys start with `prefix` (or are `prefix`),
--- by raw keys, leaving out the bare trigger. Buffer-local ones are read
--- last, so they win over a global one, as they do when typed.
local function mappingsFrom(mode, prefix, trigger)
  local found = {}
  local function add(list)
    for _, m in ipairs(list) do
      local raw = m.lhsraw or vim.keycode(m.lhs)
      if raw ~= trigger and raw:sub(1, #prefix) == prefix then found[raw] = m end
    end
  end
  add(api.nvim_get_keymap(mode))
  add(api.nvim_buf_get_keymap(0, mode))
  return found
end

--- Group names from vim.g.pure_keyhint_groups, keyed by raw keys.
local function groupNames()
  local names = {}
  for keys, name in pairs(vim.g.pure_keyhint_groups or {}) do
    names[vim.keycode(keys)] = name
  end
  return names
end

-- -----------------------------------------------------------------------------
--  Window
-- -----------------------------------------------------------------------------

--- One entry per key that can follow `keys`: a mapping or a group of them.
local function entries(maps, keys)
  local by_key = {}
  for raw, m in pairs(maps) do
    if raw ~= keys then
      local k = firstKey(raw:sub(#keys + 1))
      local e = by_key[k] or { key = k, label = vim.fn.keytrans(k), count = 0 }
      e.count = e.count + 1
      if raw == keys .. k then e.map = m end
      e.any = m
      by_key[k] = e
    end
  end

  local names = groupNames()
  local list = {}
  for k, e in pairs(by_key) do
    if e.count == 1 and e.map then
      e.desc = e.map.desc or e.map.rhs or 'Lua function'
    else
      e.group = true
      -- Unnamed: a lone mapping lends its description, else the count.
      e.desc = '+' .. (names[keys .. k]
        or (e.count == 1 and e.any.desc) or (e.count .. ' keymaps'))
    end
    table.insert(list, e)
  end
  -- Alphabetical, lowercase before uppercase (a A b B ...).
  table.sort(list, function(a, b)
    local la, lb = a.label:lower(), b.label:lower()
    if la ~= lb then return la < lb end
    return a.label > b.label
  end)
  return list
end

local view = { buf = nil, win = nil }

local function close()
  if view.win and api.nvim_win_is_valid(view.win) then api.nvim_win_close(view.win, true) end
  view.win = nil
end

--- Draw the hints for `keys` in columns across the bottom of the screen.
local function show(maps, keys)
  local list = entries(maps, keys)
  local width = math.max(20, vim.o.columns - 2) -- minus the border

  local key_w, cell_w = 1, 10
  for _, e in ipairs(list) do key_w = math.max(key_w, vim.fn.strdisplaywidth(e.label)) end
  for _, e in ipairs(list) do
    cell_w = math.max(cell_w, key_w + 3 + vim.fn.strdisplaywidth(e.desc))
  end
  cell_w = math.min(cell_w, 40, width)
  local gap = 3
  local ncols = math.max(1, math.floor((width + gap) / (cell_w + gap)))
  local max_rows = math.max(1, math.floor(vim.o.lines * 0.4))
  local nrows = math.min(math.ceil(#list / ncols), max_rows)

  -- Column by column, so each column reads down in order.
  local lines, marks = {}, {}
  for r = 1, nrows do
    local line = ''
    for c = 0, ncols - 1 do
      local e = list[c * nrows + r]
      if e then
        if c > 0 then line = line .. string.rep(' ', gap) end
        local label = e.label .. string.rep(' ', key_w - vim.fn.strdisplaywidth(e.label))
        local desc = fit(e.desc, cell_w - key_w - 3)
        local cell = label .. ' → ' .. desc
        local start = #line
        table.insert(marks, { r - 1, start, start + #label, 'PureHintKey' })
        table.insert(marks, { r - 1, start + #label, start + #label + #' → ', 'PureHintSep' })
        table.insert(marks, { r - 1, start + #label + #' → ', start + #cell,
          e.group and 'PureHintGroup' or 'PureHintDesc' })
        line = line .. cell .. string.rep(' ', cell_w - vim.fn.strdisplaywidth(cell))
      end
    end
    lines[r] = ' ' .. line
  end
  if #list > nrows * ncols then
    lines[nrows] = lines[nrows]:gsub('%s*$', '') .. '  …'
  end

  if not (view.buf and api.nvim_buf_is_valid(view.buf)) then
    view.buf = api.nvim_create_buf(false, true)
    vim.bo[view.buf].bufhidden = 'hide'
  end
  api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    -- +1: every line starts with one space of padding.
    api.nvim_buf_set_extmark(view.buf, ns, m[1], m[2] + 1, { end_col = m[3] + 1, hl_group = m[4] })
  end

  local name = groupNames()[keys]
  local title = ' ' .. vim.fn.keytrans(keys) .. (name and ('  ' .. name) or '') .. ' '
  local statusline = vim.o.laststatus > 0 and 1 or 0
  local config = {
    relative = 'editor',
    row = math.max(0, vim.o.lines - vim.o.cmdheight - statusline - nrows - 2),
    col = 0,
    width = width,
    height = nrows,
    title = title,
    title_pos = 'left',
    style = 'minimal',
    focusable = false,
    zindex = 250,
  }
  if view.win and api.nvim_win_is_valid(view.win) then
    api.nvim_win_set_config(view.win, config)
  else
    config.noautocmd = true
    view.win = api.nvim_open_win(view.buf, false, config)
  end
  vim.cmd.redraw()
end

-- -----------------------------------------------------------------------------
--  Triggers
-- -----------------------------------------------------------------------------

local query

local function mapTriggers(buf)
  if vim.g.pure_keyhint == false or not api.nvim_buf_is_valid(buf) then return end
  for _, t in ipairs(triggers()) do
    vim.keymap.set(t[1], t[2], function() query(t[1], t[2]) end,
      { buffer = buf, nowait = true, desc = 'Key hints' })
  end
end

local function unmapTriggers(buf, mode)
  for _, t in ipairs(triggers()) do
    if t[1] == mode then pcall(vim.keymap.del, mode, t[2], { buffer = buf }) end
  end
end

--- The register v:register holds when none was typed.
local function defaultRegister()
  local cb = vim.o.clipboard
  if cb:find('unnamedplus') then return '+' end
  if cb:find('unnamed') then return '*' end
  return '"'
end

--- Type `keys` again with the trigger out of the way, so the real mapping
--- runs. The count and register typed before the trigger go in front.
local function run(buf, mode, keys, count, register)
  unmapTriggers(buf, mode)
  local prefix = register ~= defaultRegister() and ('"' .. register) or ''
  if count > 0 then prefix = prefix .. count end
  -- 'm' remaps, 'i' puts the keys before anything typed meanwhile. Not 't':
  -- the keys were already typed once (and recorded, in a macro).
  api.nvim_feedkeys(prefix .. keys, 'mi', false)
  -- Runs after the keys above were consumed.
  vim.schedule(function() mapTriggers(buf) end)
end

local generation = 0

query = function(mode, trigger)
  local buf = api.nvim_get_current_buf()
  local count, register = vim.v.count, vim.v.register
  local start = vim.keycode(trigger)
  local typed = {}
  local shown, timer = false, nil
  local result
  -- showcmd would print the trigger's Lua callback ("~@<fd>") in the
  -- statusline for as long as this waits; the window title shows the keys.
  local showcmd = vim.o.showcmd
  vim.o.showcmd = false

  while true do
    local keys = start .. table.concat(typed)
    local maps = mappingsFrom(mode, keys, start)
    local exact = maps[keys]
    local longer = vim.tbl_count(maps) > (exact and 1 or 0)

    if exact and not longer then result = keys break end
    if not longer then break end -- nothing is mapped to these keys: drop them

    generation = generation + 1
    if shown then
      show(maps, keys)
    else
      local gen = generation
      timer = vim.uv.new_timer()
      timer:start(vim.g.pure_keyhint_delay or 1000, 0, vim.schedule_wrap(function()
        -- getcharstr() may have returned in the meantime.
        if gen ~= generation then return end
        shown = true
        show(maps, keys)
      end))
    end

    local ok, ch = pcall(vim.fn.getcharstr)
    generation = generation + 1
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end

    if not ok or ch == ESC then break end
    if ch == BS then
      if #typed == 0 then break end
      table.remove(typed)
    elseif ch == CR and exact then
      result = keys
      break
    else
      table.insert(typed, ch)
    end
  end

  close()
  vim.o.showcmd = showcmd
  if result then run(buf, mode, result, count, register) end
end

-- -----------------------------------------------------------------------------
--  Setup
-- -----------------------------------------------------------------------------

setHighlights()
local group = api.nvim_create_augroup('PureKeyhint', { clear = true })
api.nvim_create_autocmd('ColorScheme', { group = group, callback = setHighlights })
api.nvim_create_autocmd('BufEnter', {
  group = group,
  callback = function(args) mapTriggers(args.buf) end,
})
for _, buf in ipairs(api.nvim_list_bufs()) do
  if api.nvim_buf_is_loaded(buf) then mapTriggers(buf) end
end

return M
