-- =============================================================================
--  Highlights  (coloured marks over words and phrases in org notes)
-- =============================================================================
--  A highlight is an org link of its own type, so it is saved in the note and
--  comes back when the note is opened again (also in Emacs, where an unknown
--  link type is still a link):
--
--    [[hl:yellow][a phrase]]      a colour of the palette, by name
--    [[hl:#7d82d9][a phrase]]     any colour, by its hex code
--
--  The render (pure/render-org.lua) hides the brackets and the target like any
--  link; this module paints the text with the colour behind it (black or white
--  text on top, by brightness), with the render on or off.
--
--  The palette: the defaults below (vim.g.pure_highlights replaces them, a list
--  of { name, '#rrggbb' }) plus the note's own colours, declared anywhere in the
--  note with #+HL: lines. A name before a hex code names it; a bare hex code is
--  its own name. A note's name replaces a default of the same name.
--
--    #+HL: idea #7d82d9 doubt #F99957
--    #+HL: #92a593
--
--  Changing a colour in #+HL: recolours every highlight of that name in the note.
--
--    <leader>H   (normal) highlight the word under the cursor; on a highlight:
--                change its colour or remove it
--    <leader>H   (visual) highlight the selection (one line)
--
--  Export (org.nvim's links.types.hl, lua/plugins/org.lua): HTML gets
--  <mark style="background-color:...">, the other backends the plain text.
-- =============================================================================

local M = {}
local api = vim.api

local ns = api.nvim_create_namespace('pure_highlights')
local HEX = '^#%x%x%x%x%x%x$'

M.defaults = {
  { 'yellow', '#E9BB4F' },
  { 'green', '#92a593' },
  { 'blue', '#7d82d9' },
  { 'pink', '#faaaa9' },
  { 'orange', '#F99957' },
  { 'purple', '#c89dc1' },
}

-- ---- palette --------------------------------------------------------------------
--- { { name, hex } } of one #+HL: value ("idea #7d82d9 #92a593" -> idea, #92a593).
function M.parseKeyword(value)
  local out, pending = {}, nil
  for token in value:gmatch('%S+') do
    if token:match(HEX) then
      out[#out + 1] = { pending or token:lower(), token:lower() }
      pending = nil
    else
      pending = token
    end
  end
  return out
end

local cache = {} -- buf -> { tick, entries }

--- The colours a note declares (#+HL: lines), in order.
local function noteColours(buf)
  local tick = api.nvim_buf_get_changedtick(buf)
  local c = cache[buf]
  if c and c.tick == tick then return c.entries end
  local entries = {}
  for _, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local value = line:match('^%s*#%+[Hh][Ll]:%s*(.*)$')
    if value then vim.list_extend(entries, M.parseKeyword(value)) end
  end
  cache[buf] = { tick = tick, entries = entries }
  return entries
end

--- The palette of a buffer: the note's colours first, then the defaults it does not rename.
function M.palette(buf)
  local list, seen = {}, {}
  for _, e in ipairs(noteColours(buf)) do
    if not seen[e[1]:lower()] then
      list[#list + 1] = { e[1], e[2] }
      seen[e[1]:lower()] = true
    end
  end
  for _, e in ipairs(vim.g.pure_highlights or M.defaults) do
    if not seen[e[1]:lower()] then
      list[#list + 1] = { e[1], e[2]:lower() }
      seen[e[1]:lower()] = true
    end
  end
  return list
end

--- The hex code of a link's value (a name of the palette or a hex code), or nil.
function M.colour(buf, value)
  if value:match(HEX) then return value:lower() end
  for _, e in ipairs(M.palette(buf)) do
    if e[1]:lower() == value:lower() then return e[2] end
  end
end

api.nvim_set_hl(0, 'PureHighlightUnknown', { link = 'Search', default = true })

local function groupOf(buf, value)
  local hex = M.colour(buf, value)
  return hex and require('pure.hexcolors').group(hex:sub(2), 'background') or 'PureHighlightUnknown'
end

-- ---- finding the highlights -----------------------------------------------------
--- { { s, e, value, ds, de } } of the highlights in a line, 0-based: s..e the whole link (e exclusive),
--- ds..de its text.
function M.spans(line)
  local out = {}
  for start, value, desc, stop in line:gmatch('()%[%[hl:([^%]]+)%]%[(.-)%]%]()') do
    local ds = start - 1 + 2 + 3 + #value + 2
    out[#out + 1] = { s = start - 1, e = stop - 1, value = value, ds = ds, de = ds + #desc }
  end
  return out
end

--- Every [[link]] of a line, 0-based (any type), to refuse a highlight that would cut one.
local function allLinks(line)
  local out = {}
  for start, stop in line:gmatch('()%[%[.-%]%]()') do out[#out + 1] = { start - 1, stop - 1 } end
  return out
end

-- ---- drawing --------------------------------------------------------------------
-- Plain extmarks, made again for the whole buffer when its text changes. Not a decoration provider (ephemeral marks
-- drawn per line): render-org repaints rows from its own redraw and the ephemeral colour was lost there (only the
-- first character kept it).
function M.refresh(buf)
  buf = buf or api.nvim_get_current_buf()
  if not api.nvim_buf_is_valid(buf) then return end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if vim.bo[buf].filetype ~= 'org' then return end
  for row0, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find('[[hl:', 1, true) then
      for _, h in ipairs(M.spans(line)) do
        if h.de > h.ds then
          api.nvim_buf_set_extmark(buf, ns, row0 - 1, h.ds, {
            end_col = h.de,
            hl_group = groupOf(buf, h.value),
            priority = 4500, -- over the link colour and the hex codes
          })
        end
      end
    end
  end
end

local augroup = api.nvim_create_augroup('PureHighlights', { clear = true })
api.nvim_create_autocmd({ 'FileType', 'BufWinEnter', 'TextChanged', 'TextChangedI' }, {
  group = augroup,
  callback = function(args)
    if vim.bo[args.buf].filetype == 'org' then M.refresh(args.buf) end
  end,
})
-- A colorscheme clears the colour groups (pure/hexcolors makes them again when asked): draw again after it.
api.nvim_create_autocmd('ColorScheme', {
  group = augroup,
  callback = function()
    vim.schedule(function()
      for _, buf in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'org' then M.refresh(buf) end
      end
    end)
  end,
})

-- ---- editing --------------------------------------------------------------------
--- The text of `buf` row `row` still being `line` (the picker is asynchronous: the buffer may have changed).
local function unchanged(buf, row, line)
  return api.nvim_buf_is_valid(buf) and api.nvim_buf_get_lines(buf, row, row + 1, false)[1] == line
end

local function setValue(buf, row, h, value)
  api.nvim_buf_set_text(buf, row, h.s + 5, row, h.s + 5 + #h.value, { value })
end

local function remove(buf, row, line, h)
  local text = line:sub(h.ds + 1, h.de)
  api.nvim_buf_set_text(buf, row, h.s, row, h.e, { text })
end

local function wrap(buf, row, line, s, e, value)
  local text = line:sub(s + 1, e)
  api.nvim_buf_set_text(buf, row, s, row, e, { '[[hl:' .. value .. '][' .. text .. ']]' })
end

--- Ask for a colour (the palette, any hex code, or removing `existing`) and call `done(value | false)`.
local function ask(buf, existing, done)
  local items = {}
  if existing then items[#items + 1] = { kind = 'remove' } end
  for _, e in ipairs(M.palette(buf)) do items[#items + 1] = { kind = 'colour', name = e[1], hex = e[2] } end
  items[#items + 1] = { kind = 'other' }
  vim.ui.select(items, {
    prompt = existing and ('Highlight (' .. existing.value .. ')') or 'Highlight',
    format_item = function(it)
      if it.kind == 'remove' then return 'remove the highlight' end
      if it.kind == 'other' then return 'other colour (#rrggbb)...' end
      return it.name == it.hex and it.hex or (it.name .. '  ' .. it.hex)
    end,
  }, function(it)
    if not it then return end
    if it.kind == 'remove' then return done(false) end
    if it.kind == 'colour' then return done(it.name) end
    vim.ui.input({ prompt = 'Colour (#rrggbb): ' }, function(hex)
      hex = hex and vim.trim(hex) or ''
      if hex:match('^%x%x%x%x%x%x$') then hex = '#' .. hex end
      if hex:match(HEX) then
        done(hex:lower())
      elseif hex ~= '' then
        vim.notify('Not a colour: ' .. hex, vim.log.levels.WARN)
      end
    end)
  end)
end

--- The range to highlight: { s, e } (0-based, e exclusive) on `row`, or nil and a reason.
local function selection(line, row)
  local mode = vim.fn.mode()
  local v, c = vim.fn.getpos('v'), vim.fn.getpos('.')
  if v[2] ~= c[2] then return nil, 'a highlight is on one line: select within one line' end
  if mode == 'V' then
    local s = line:find('%S')
    if not s then return nil, 'the line is empty' end
    return { s - 1, #(line:gsub('%s+$', '')) }
  end
  local a, b = math.min(v[3], c[3]), math.max(v[3], c[3]) -- 1-based bytes; b is the first byte of the last character
  local last = vim.fn.strcharpart(line:sub(b), 0, 1)
  return { a - 1, b - 1 + #last }
end

--- <leader>H: highlight the selection (visual) or the word under the cursor; on a highlight, change or remove it.
function M.pick()
  local buf = api.nvim_get_current_buf()
  local visual = vim.fn.mode():match('^[vV\22]') ~= nil
  if vim.bo[buf].filetype ~= 'org' then
    if visual then api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false) end
    vim.notify('Highlights are for org notes', vim.log.levels.INFO)
    return
  end
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local line = api.nvim_get_current_line()

  local range, why
  if visual then
    range, why = selection(line, row)
    api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  end

  -- The highlight the cursor (or the selection) is on: change or remove it.
  local here = range and range[1] or col
  for _, h in ipairs(M.spans(line)) do
    if here >= h.s and here < h.e then
      return ask(buf, h, function(value)
        if not unchanged(buf, row, line) then return end
        if value == false then remove(buf, row, line, h) else setValue(buf, row, h, value) end
      end)
    end
  end

  if visual and not range then return vim.notify(why, vim.log.levels.WARN) end
  if not visual then
    local m = vim.fn.matchstrpos(line, '\\k*\\%' .. (col + 1) .. 'c\\k\\+')
    if m[2] < 0 then return vim.notify('No word under the cursor', vim.log.levels.INFO) end
    range = { m[2], m[3] }
  end
  if range[2] <= range[1] then return end
  for _, l in ipairs(allLinks(line)) do
    if range[1] < l[2] and range[2] > l[1] then
      return vim.notify('A highlight cannot go over a link (org has no link inside a link)', vim.log.levels.WARN)
    end
  end
  local text = line:sub(range[1] + 1, range[2])
  if text:find(']]', 1, true) or text:find('[[', 1, true) then
    return vim.notify('The text has ]] or [[ in it: it cannot be a highlight', vim.log.levels.WARN)
  end
  ask(buf, nil, function(value)
    if value and unchanged(buf, row, line) then wrap(buf, row, line, range[1], range[2], value) end
  end)
end

-- ---- org.nvim link type -----------------------------------------------------------
--- links.types.hl of org.nvim's setup: following a highlight tells its colour; HTML export marks the text.
M.linkType = {
  follow = function(path)
    local hex = M.colour(api.nvim_get_current_buf(), path or '')
    vim.notify('Highlight ' .. (path or '') .. (hex and hex ~= path and ('  ' .. hex) or '')
      .. (hex and '' or ' (not in the palette)'), vim.log.levels.INFO)
  end,
  export = function(path, desc, backend)
    desc = desc or ''
    if backend == 'html' then
      local hex = M.colour(api.nvim_get_current_buf(), path or '')
      return hex and ('<mark style="background-color:' .. hex .. '">' .. desc .. '</mark>') or ('<mark>' .. desc .. '</mark>')
    end
    return desc
  end,
}

return M
