-- =============================================================================
--  Org rendering: settings, view and bigger headings, in one file
-- =============================================================================
--  The org twin of pure/render-md.lua, built from it: the same three parts,
--  the same terminal logic, the same colours (pure/notecolors.lua, which
--  follow the colorscheme).
--
--  The text is never changed: extmarks draw over it. org.nvim's own drawing
--  (concealed links, star bullets, checkboxes, indent) is off in
--  lua/plugins/org.lua, so it is this file that draws, and <leader>om turns
--  it all off. org.nvim has no tree-sitter parser; the elements are found by
--  reading the lines (blocks and drawers first, so a `*` inside a src block
--  is never a bullet).
--
--    * Headline        icon over the stars, coloured band across the line
--    - item            bullet per nesting level (• ◦ ▪ ▫, vim.g.pure_md_bullets)
--    - [ ] / - [X]     checkbox icons ([-] partly done); done items are dimmed
--    #+begin_src lua   shaded block with the language as a label (any #+begin_xxx)
--    #+begin_quote     a bar instead of the margin
--    -----             full-width line
--    | tables |        box-drawing borders
--    [[target][text]]  links show only their text (the raw link under the cursor)
--    *bold* /italic/   the marks around emphasis are hidden (vim.g.pure_org_emphasis = false keeps them)
--    :PROPERTIES:      property and logbook drawers are hidden; they come back
--    :END:             while the cursor is on them
--    #+title: Name     drawn as a first-level title
--
--  Bigger headlines: kitty (OSC 66) and WezTerm (DECDHL) draw `*` and `**`
--  larger, exactly as for Markdown (the same checks; vim.g.pure_org_headings
--  or, when nil, vim.g.pure_md_headings: 'auto', 'osc66', 'decdhl', 'off').
--  :PureOrgHeadings [auto|osc66|decdhl|off] changes it at run time.
--
--    <leader>tm   rendering on / off (M.toggle; M.set_level('full'|'off') sets one)
--    <leader>tM   the big headlines (OSC 66 / DECDHL) on / off; off by default (key big_headings)
-- =============================================================================

local M = {}
local View, Headings -- the sections below; they call into each other
View = M

-- The toggles stay as left (configs/functions.lua): the saved value, or `default` when none.
local function saved(key, default)
  local ok, toggles = pcall(require, 'configs.functions')
  if ok then return toggles.get(key, default) end
  return default
end

local startLevel = saved('render_org', 'full')
if startLevel ~= 'off' then startLevel = 'full' end

-- The base groups (PureMd*: code shade, bullets, rule, table, bands) are defined by the Markdown file.
pcall(require, 'pure.render-md')
local notecolors = require('pure.notecolors')

local ns = vim.api.nvim_create_namespace('pure_orgview')
local enabled = startLevel ~= 'off'
local level = startLevel -- 'full' | 'off' (the big headlines are separate: <leader>tM)

-- org.nvim aligns a table by the width the buffer shows (a link counts as its text,
-- hidden emphasis marks as nothing), but only when its own conceal options say so, and those are off
-- in plugins/org.lua because this file does the hiding. Tell it per buffer, following the
-- rendering (<leader>tm) and vim.g.pure_org_emphasis, so the columns line up on screen.
local function syncTableWidths(buf)
  vim.b[buf].org_link_descriptive = enabled
  vim.b[buf].org_hide_emphasis_markers = enabled and vim.g.pure_org_emphasis ~= false
end

-- -----------------------------------------------------------------------------
--  Settings of an org buffer
-- -----------------------------------------------------------------------------
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('PureOrg', { clear = true }),
  pattern = 'org',
  callback = function(args)
    vim.opt_local.textwidth = 110
    vim.opt_local.spell = true
    -- Only the languages whose word list is present (see render-md.lua).
    local wanted = vim.g.pure_spelllang or { 'pt_br', 'en', 'it' }
    local available = {}
    for _, lang in ipairs(wanted) do
      local base = lang:gsub('_.*', '')
      if vim.fn.globpath(vim.o.runtimepath, 'spell/' .. base .. '.*.spl') ~= '' then
        table.insert(available, lang)
      end
    end
    vim.opt_local.spelllang = #available > 0 and available or { 'en' }
    vim.opt_local.spellsuggest = 'best,9'
    vim.opt_local.spelloptions = 'camel'
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = 'nc'
    -- The automatic break never splits a [[link]]: the markdown one reads [[ ... ]] too.
    vim.opt_local.formatexpr = "v:lua.require'pure.render-md'.formatexpr()"

    notecolors.apply()
    syncTableWidths(args.buf)

    local map = function(lhs, rhs, desc) vim.keymap.set('n', lhs, rhs, { buffer = args.buf, desc = desc }) end
    map('<leader>ds', 'z=', 'Dictionary suggestion')
    map('<leader>dg', 'zg', 'Dictionary good (add the word)')
    map('<leader>dw', 'zw', 'Dictionary wrong (word)')
    map('<leader>dp', '[s', 'Previous misspelled word')
    map('<leader>dn', ']s', 'Next misspelled word')
    vim.keymap.set('i', '<C-l>', function()
      return "<C-g>u<Cmd>lua require('pure.render-md').fixLastWord()<CR><C-g>u"
    end, { buffer = args.buf, expr = true, desc = 'Fix the last misspelled word' })
  end,
})

-- -----------------------------------------------------------------------------
--  Reading the lines
-- -----------------------------------------------------------------------------
--  One pass over the buffer, kept while the text is the same (changedtick):
--    headlines   { row, level, text }
--    rows[row]   { kind = 'headline'|'item'|'block'|'drawer'|'table'|'tablerule'|'rule'|'title', ... }
--    blocks      { first, last, name, lang }
--    drawers     { first, last }       only the ones that are hidden
local scan_cache = {}
local plainText -- defined with the links and the emphasis below

local HIDDEN_DRAWERS = { PROPERTIES = true, LOGBOOK = true }

local function scan(buf)
  local tick = vim.b[buf].changedtick
  local c = scan_cache[buf]
  if c and c.tick == tick then return c.info end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local info = { lines = lines, headlines = {}, rows = {}, blocks = {}, drawers = {} }
  local rows = info.rows
  local block, drawer
  local stack = {} -- indentation of the open list levels

  for i, line in ipairs(lines) do
    local row = i - 1
    if block then
      rows[row] = { kind = 'block', name = block.name }
      local ending = line:match('^%s*#%+[Ee][Nn][Dd]_(%w+)')
      if ending and ending:lower() == block.name then
        block.last = row
        info.blocks[#info.blocks + 1] = block
        block = nil
      end
    elseif drawer then
      rows[row] = { kind = 'drawer' }
      if line:match('^%s*:[Ee][Nn][Dd]:%s*$') then
        drawer.last = row
        if HIDDEN_DRAWERS[drawer.name] then info.drawers[#info.drawers + 1] = drawer end
        drawer = nil
      end
    else
      local name, rest = line:match('^%s*#%+[Bb][Ee][Gg][Ii][Nn]_(%w+)%s*(.*)$')
      local dname = line:match('^%s*:([%w_-]+):%s*$')
      local stars, title = line:match('^(%*+)%s+(.*)$')
      local indent, bullet, after = line:match('^(%s*)([-+*])(%s+)')
      if not indent then indent, bullet, after = line:match('^(%s*)(%d+[.)])(%s+)') end
      if name then
        block = { first = row, name = name:lower(), lang = rest:match('^(%S+)') or '' }
        rows[row] = { kind = 'block', name = block.name, edge = true }
      elseif dname and dname:upper() ~= 'END' then
        drawer = { first = row, name = dname:upper() }
        rows[row] = { kind = 'drawer' }
      elseif stars then
        stack = {}
        local text = plainText((title:gsub('%s+:[%w_@#%%:]+:%s*$', ''))) -- without the tags, links and emphasis marks
        rows[row] = { kind = 'headline', level = #stars, stars = #stars }
        info.headlines[#info.headlines + 1] = { row = row, level = #stars, text = text }
      elseif line:match('^%s*%-%-%-%-%-+%s*$') then
        rows[row] = { kind = 'rule' }
      elseif line:match('^%s*|') then
        rows[row] = { kind = line:match('^%s*|[-+|]+%s*$') and 'tablerule' or 'table' }
      elseif indent and not (bullet == '*' and #indent == 0) then
        local width = #indent
        while #stack > 0 and stack[#stack] > width do table.remove(stack) end
        if #stack == 0 or stack[#stack] < width then stack[#stack + 1] = width end
        rows[row] = { kind = 'item', depth = #stack, indent = width, bullet = bullet, gap = #after }
      elseif line:match('^%s*#%+[Tt][Ii][Tt][Ll][Ee]:') then
        rows[row] = { kind = 'title' }
      elseif line:match('%S') and not line:match('^%s') then
        stack = {} -- text at column 0 ends a list
      end
    end
  end
  -- A block or drawer left open (being typed) is not one.
  for _, open in ipairs({ block or false, drawer or false }) do
    if open then for r = open.first, #lines - 1 do rows[r] = nil end end
  end

  scan_cache[buf] = { tick = tick, info = info }
  return info
end


-- =============================================================================
--  Bigger headlines: kitty (OSC 66) and WezTerm (DECDHL), as in render-md.lua
-- =============================================================================
Headings = (function()
local M = {}

local ESC = string.char(27)
local BEL = string.char(7)
local ns = vim.api.nvim_create_namespace('pure_org_headings')

local state = {
  mode = nil,      -- 'osc66' | 'decdhl' | nil (off)
  enabled = startLevel == 'full' and saved('big_headings', false) == true,  -- the big headlines: <leader>tM, off by default
  cursor = nil,    -- lnum of the heading under the cursor
  drawn = {},      -- blocks written by the last render: { row, col, width, height }
  setup = false,
}
local cache = {} -- buf -> { tick, list }
local last = {}

-- The level of heading -> how many screen rows its block takes.
local HEIGHT = {
  osc66 = { [1] = 3, [2] = 2 },
  decdhl = { [1] = 2, [2] = 2 },
}

-- -----------------------------------------------------------------------------
--  Which terminal
-- -----------------------------------------------------------------------------
local function detect()
  local want = vim.g.pure_org_headings
  if want == nil then want = vim.g.pure_md_headings end
  if want == nil then want = 'auto' end
  if want == 'off' or want == false then return nil end
  if want == 'osc66' or want == 'decdhl' then return want end
  if #vim.api.nvim_list_uis() == 0 or vim.g.neovide or vim.env.TMUX or vim.env.STY then return nil end
  if vim.env.KITTY_WINDOW_ID then return 'osc66' end
  if vim.env.WEZTERM_PANE or vim.env.TERM_PROGRAM == 'WezTerm' then return 'decdhl' end
  return nil
end

-- -----------------------------------------------------------------------------
--  The headings of a buffer
-- -----------------------------------------------------------------------------
-- { { row (0-based), level, text } } from the scan of the org lines (a `*` in a src block is not a headline).
local function headingsOf(buf)
  return scan(buf).headlines
end

local function heightOf(level)
  return state.mode and HEIGHT[state.mode][level] or nil
end

local function headingAt(buf, lnum)
  for _, h in ipairs(headingsOf(buf)) do
    if h.row == lnum - 1 and heightOf(h.level) then return h end
  end
end

-- -----------------------------------------------------------------------------
--  Escape sequences
-- -----------------------------------------------------------------------------
local function send(data)
  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send(data)
  else
    io.stdout:write(data)
  end
end

-- "38;2;r;g;b" for a highlight group's fg (the first group of the list that has one), or "48;2;..." for a bg; nil when none has.
local function rgb(groups, field)
  for _, group in ipairs(groups) do
    local n = vim.api.nvim_get_hl(0, { name = group, link = false })[field]
    if n then
      return string.format('%d;2;%d;%d;%d', field == 'fg' and 38 or 48, math.floor(n / 65536), math.floor(n / 256) % 256, n % 256)
    end
  end
end

local function colours(level)
  local fg = rgb({ 'PureOrgH' .. level, '@markup.heading.' .. level .. '.markdown', 'markdownH' .. level, 'Title' }, 'fg') or '39'
  local bg = rgb({ 'Normal' }, 'bg') or '49' -- a transparent theme has no bg: keep the terminal's
  return fg, bg
end

-- Cut the text so that it fits in `cols` cells.
local function fit(text, cols)
  if cols <= 0 then return '' end
  while vim.fn.strdisplaywidth(text) > cols and #text > 0 do
    text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
  end
  return text
end

-- Is the window as wide as the terminal (the DECDHL attribute covers the whole row)?
local function fullWidth(win)
  return vim.fn.win_screenpos(win)[2] == 1 and vim.api.nvim_win_get_width(win) + (vim.fn.getwininfo(win)[1].textoff or 0) >= vim.o.columns
end

-- First screen row/column of a heading's block, when the whole block is inside the window.
local function blockOrigin(win, lnum, height)
  local pos = vim.fn.screenpos(win, lnum, 1)
  local wp = vim.fn.win_screenpos(win)
  local bottom = wp[1] + vim.api.nvim_win_get_height(win) - 1
  if pos.row > 0 and pos.row + height - 1 <= bottom then
    return pos.row, pos.col
  end
end

-- Floating windows (the key hint, notifications, a preview, a completion menu) paint over the cells of a block; a block drawn
-- under one is cut in pieces, and the pieces stay when the window closes (seen in Kitsu: "Three" became "hree" with the
-- text of the hint left on its row). So no block is drawn where a floating window is, the blocks go before one opens or
-- moves (WinNew, and its position and size in on_win), and they come back when it closes.
local floatKeys = {} -- window -> "row:col:width:height" as last seen

local function floatRects()
  local rects = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative ~= '' and not cfg.hide then
      local pos = vim.api.nvim_win_get_position(w)
      -- 1-based screen rows and columns, with a cell around the window for its border
      rects[#rects + 1] = { top = pos[1], left = pos[2], bottom = pos[1] + vim.api.nvim_win_get_height(w) + 1,
        right = pos[2] + vim.api.nvim_win_get_width(w) + 1 }
    end
  end
  return rects
end

local function underFloat(floats, win, row, col, height)
  if #floats == 0 then return false end
  local left, right = 1, vim.o.columns
  if state.mode ~= 'decdhl' then
    left = col
    right = col + vim.api.nvim_win_get_width(win) - (vim.fn.getwininfo(win)[1].textoff or 0)
  end
  for _, f in ipairs(floats) do
    if row <= f.bottom and row + height - 1 >= f.top and left <= f.right and right >= f.left then return true end
  end
  return false
end

local function drawBlock(win, h, lnum, row, col)
  local height = HEIGHT[state.mode][h.level]
  local fg, bg = colours(h.level)
  local sgr = string.format('%s[0;%s;%sm', ESC, fg, bg)
  local textoff = vim.fn.getwininfo(win)[1].textoff or 0
  if state.mode == 'osc66' then
    local cols = vim.api.nvim_win_get_width(win) - textoff
    local text = fit(h.text, math.floor(cols / height))
    state.drawn[#state.drawn + 1] = { row = row, col = col, width = vim.fn.strdisplaywidth(text) * height, height = height }
    return string.format('%s%s[%d;%dH%s]66;s=%d;%s%s%s[0m', sgr, ESC, row, col, ESC, height, text, BEL, ESC)
  end
  -- DECDHL: every character is two cells wide, so the text starts at half the number of columns before the text.
  local startCol = math.floor(textoff / 2) + 1
  local text = fit(h.text, math.floor((vim.o.columns - (startCol - 1) * 2) / 2))
  state.drawn[#state.drawn + 1] = { row = row, col = 1, width = vim.o.columns, height = height }
  return table.concat({
    sgr,
    string.format('%s[%d;1H%s#3%s[2K%s[%d;%dH%s', ESC, row, ESC, ESC, ESC, row, startCol, text),
    string.format('%s[%d;1H%s#4%s[2K%s[%d;%dH%s', ESC, row + 1, ESC, ESC, ESC, row + 1, startCol, text),
    ESC .. '[0m',
  })
end

local function eraseBlocks(blocks)
  if #blocks == 0 then return end
  local out = {}
  for _, b in ipairs(blocks) do
    for r = b.row, b.row + b.height - 1 do
      if state.mode == 'decdhl' then
        out[#out + 1] = string.format('%s[0m%s[%d;1H%s#5%s[2K', ESC, ESC, r, ESC, ESC)
      else
        out[#out + 1] = string.format('%s[0m%s[%d;%dH%s[%dX', ESC, ESC, r, b.col, ESC, b.width)
      end
    end
  end
  send(ESC .. '7' .. table.concat(out) .. ESC .. '8')
end

-- Erase every block drawn before. It has to happen BEFORE Neovim paints the new screen.
local function eraseAll()
  if #state.drawn == 0 then return end
  local blocks = state.drawn
  state.drawn = {}
  eraseBlocks(blocks)
end

local function eligible(buf)
  return state.mode and state.enabled and vim.bo[buf].filetype == 'org'
    and (vim.bo[buf].buftype == '' or vim.b[buf].pure_orgview == true)
end

-- Do the headings of this window get the big size (so that mdview must not draw its own)?
local function activeFor(win)
  if not state.mode then return false end
  if state.mode == 'decdhl' and not fullWidth(win) then return false end
  return state.enabled
end

-- -----------------------------------------------------------------------------
--  Reserve the room, draw
-- -----------------------------------------------------------------------------
local function reserve(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not eligible(buf) or not activeFor(vim.api.nvim_get_current_win()) then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, h in ipairs(headingsOf(buf)) do
    local height = heightOf(h.level)
    if height then
      local lnum = h.row + 1
      local virt = {}
      for _ = 1, height - 1 do virt[#virt + 1] = { { ' ', 'Normal' } } end
      vim.api.nvim_buf_set_extmark(buf, ns, h.row, 0, { virt_lines = virt })
      if lnum ~= state.cursor and state.settled ~= false then
        vim.api.nvim_buf_set_extmark(buf, ns, h.row, 0, {
          virt_text = { { string.rep(' ', vim.fn.strdisplaywidth(lines[lnum] or '')), 'Normal' } },
          virt_text_pos = 'overlay',
        })
      end
    end
  end
end

local function render()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if not eligible(buf) or not activeFor(win) then return end
  state.drawn = {}
  -- Scrolled into the middle of a block's reserved rows (topfill) or of a wrapped line (skipcol): the rows Neovim reports
  -- for the lines are not the ones it puts on the screen (seen in Kitsu: blocks one row too low, drawn over the next
  -- line). Nothing is drawn until the scroll settles on a whole line; the raw text stays covered meanwhile.
  local view = vim.fn.winsaveview()
  local settled = view.topfill == 0 and view.skipcol == 0
  if settled ~= state.settled then
    state.settled = settled
    reserve(buf) -- the covers of the raw text come off (and back) with it
  end
  if not settled then return end
  local floats = floatRects()
  local out = {}
  for _, h in ipairs(headingsOf(buf)) do
    local lnum = h.row + 1
    local height = heightOf(h.level)
    if height and lnum >= vim.fn.line('w0') and lnum <= vim.fn.line('w$') and lnum ~= state.cursor then
      local row, col = blockOrigin(win, lnum, height)
      if row and not underFloat(floats, win, row, col, height) then out[#out + 1] = drawBlock(win, h, lnum, row, col) end
    end
  end
  local data = table.concat(out)
  if data ~= '' then
    send(ESC .. '7' .. ESC .. '[?25l' .. data .. ESC .. '8' .. ESC .. '[?25h')
  end
end

local timer = vim.uv.new_timer()
local function scheduleRender()
  timer:stop()
  timer:start(30, 0, vim.schedule_wrap(render))
end

-- mdview draws the headings of the levels this module takes only when the window is not one it can draw in.
function M.handles(level)
  return heightOf(level) ~= nil and activeFor(vim.api.nvim_get_current_win())
end

function M.mode() return state.mode end

local function redrawAll()
  eraseAll()
  local buf = vim.api.nvim_get_current_buf()
  reserve(buf)
  scheduleRender()
  if View then View.refresh(true) end
end

function M.set_enabled(on)
  state.enabled = on
  redrawAll()
end

-- -----------------------------------------------------------------------------
--  Setup
-- -----------------------------------------------------------------------------
function M.setup(force)
  local mode = detect()
  if state.setup then
    -- Called again (the command): only the mode changes.
    eraseAll()
    state.mode = mode
    redrawAll()
    return
  end
  state.mode = mode
  state.setup = true
  local group = vim.api.nvim_create_augroup('PureOrgHeadings', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'TextChanged', 'TextChangedI' }, {
    group = group,
    callback = function(args)
      if not state.mode then return end
      reserve(args.buf)
      scheduleRender()
    end,
  })
  vim.api.nvim_create_autocmd({ 'WinScrolled', 'WinResized', 'VimResized', 'ModeChanged', 'FocusGained', 'WinEnter' }, {
    group = group,
    callback = function()
      if not state.mode then return end
      -- A split may have made the window too narrow for DECDHL (or wide again): mdview takes over or gives back the headings.
      local want = M.handles(1)
      if last.handles ~= want then
        last.handles = want
        redrawAll()
        return
      end
      scheduleRender()
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    callback = function(args)
      if not state.mode or not eligible(args.buf) then return end
      local win = vim.api.nvim_get_current_win()
      local lnum = vim.fn.line('.')
      local h = headingAt(args.buf, lnum)
      local now = h and lnum or nil
      if now ~= state.cursor then
        state.cursor = now
        if h and activeFor(win) then
          local height = heightOf(h.level)
          local row = blockOrigin(win, lnum, height)
          if row then
            -- Before Neovim writes the raw text over those cells.
            eraseBlocks({ { row = row, col = state.mode == 'decdhl' and 1 or select(2, blockOrigin(win, lnum, height)),
              width = state.mode == 'decdhl' and vim.o.columns or vim.fn.strdisplaywidth(h.text) * height, height = height } })
            -- And it is no longer a block on the screen: a later eraseAll (another heading row repainted in the same cycle) would
            -- wipe these rows again AFTER Neovim wrote the raw text there, leaving the heading line empty.
            for i = #state.drawn, 1, -1 do
              if state.drawn[i].row == row then table.remove(state.drawn, i) end
            end
          end
        end
        reserve(args.buf)
        scheduleRender()
      end
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = function() if state.mode then scheduleRender() end end })
  vim.api.nvim_create_autocmd('BufWipeout', { group = group, callback = function(args) cache[args.buf] = nil end })
  -- A window opened (before it is painted) or closed: the blocks go, and are drawn again once the screen is settled.
  vim.api.nvim_create_autocmd('WinNew', {
    group = group,
    callback = function()
      if not state.mode then return end
      eraseAll()
      scheduleRender()
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      if not state.mode then return end
      floatKeys[tonumber(args.match)] = nil
      scheduleRender()
    end,
  })

  -- Before each redraw cycle: when the window scrolled, resized or the text changed, the old blocks go first.
  vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, win, buf, topline)
      if not state.mode then return end
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative ~= '' then
        -- A floating window is being painted: when it appeared, moved or changed size, the blocks go first.
        local pos = vim.api.nvim_win_get_position(win)
        local fkey = table.concat({ pos[1], pos[2], vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) }, ':')
        if floatKeys[win] ~= fkey then
          floatKeys[win] = fkey
          eraseAll()
          scheduleRender()
        end
        return
      end
      if win ~= vim.api.nvim_get_current_win() then return end
      -- topfill / skipcol: scrolling through the virtual lines a block reserves (or a wrapped line) moves the screen without
      -- changing `topline`; without them in the key the old blocks stayed where they were and new ones were drawn beside them.
      local view = vim.fn.winsaveview()
      local key = table.concat({ topline, view.topfill, view.skipcol, vim.api.nvim_buf_get_changedtick(buf), vim.api.nvim_win_get_height(win), vim.api.nvim_win_get_width(win) }, ':')
      if key ~= last.key then
        last.key = key
        eraseAll()
        scheduleRender()
      end
    end,
    -- Neovim is repainting a heading row (a highlight arrived, another plugin changed its extmarks...): that can erase part of
    -- the block, so the blocks go and are written again after this cycle.
    on_line = function(_, win, buf, row)
      if not state.mode or win ~= vim.api.nvim_get_current_win() or #state.drawn == 0 then return end
      for _, h in ipairs(headingsOf(buf)) do
        if h.row == row and row + 1 ~= state.cursor and heightOf(h.level) then
          eraseAll()
          scheduleRender()
          return
        end
      end
    end,
  })

  vim.api.nvim_create_user_command('PureOrgHeadings', function(opts)
    if opts.args ~= '' then vim.g.pure_org_headings = opts.args end
    M.setup()
    vim.notify('Org headings: ' .. (state.mode or 'off'))
  end, {
    nargs = '?',
    complete = function() return { 'auto', 'osc66', 'decdhl', 'off' } end,
    desc = 'Bigger org headlines (kitty OSC 66 / WezTerm DECDHL)',
  })

  -- The buffer that is already open has had its BufEnter, and the cursor may already be on a heading.
  vim.schedule(function()
    local buf = vim.api.nvim_get_current_buf()
    if state.mode and eligible(buf) then
      local h = headingAt(buf, vim.fn.line('.'))
      state.cursor = h and vim.fn.line('.') or nil
    end
    redrawAll()
  end)
end



return M
end)()

-- =============================================================================
--  The view: org drawn in place
-- =============================================================================
local heading_icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' }
local bullets = vim.g.pure_md_bullets or { '•', '◦', '▪', '▫' }
local checkbox = { unchecked = '󰄱', checked = '󰄲', partial = '\u{F0856}' } -- md-checkbox_intermediate

-- Colours: org uses the groups of the Markdown view, which link to the theme.
local function setHighlights()
  notecolors.apply()
  -- The bands (PureMdHnBg) and the base groups are computed from the colours above: again for this theme.
  local md = package.loaded['pure.render-md']
  if md and md.setHighlights then md.setHighlights() end
  for level = 1, 6 do
    vim.api.nvim_set_hl(0, 'PureOrgH' .. level, { link = '@markup.heading.' .. level .. '.markdown' })
  end
  -- The headline text takes the colours of the Markdown headings (they follow the theme; Ethereal: Doom's list), not
  -- org.nvim's own per-level colours, so a note reads the same in both.
  for level = 1, 8 do
    vim.api.nvim_set_hl(0, 'OrgHeadlineLevel' .. level, { link = 'PureOrgH' .. math.min(level, 6) })
  end
  -- The label and the covered end line of a block sit over the shaded line: they take its background, or the
  -- shade had a hole as wide as the text (seen in Kitsu).
  local label = vim.api.nvim_get_hl(0, { name = 'PureMdCodeLabel', link = false })
  local code = vim.api.nvim_get_hl(0, { name = 'PureMdCode', link = false })
  vim.api.nvim_set_hl(0, 'PureOrgCodeLabel', { fg = label.fg, bg = code.bg, italic = label.italic })
end

local function lineText(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
end

-- ---- headlines ---------------------------------------------------------------
local function headline(row, info, mark)
  local level, stars = info.level, info.stars
  -- The levels the terminal draws bigger (kitty, WezTerm) are not drawn here.
  if Headings.handles(level) then return end
  local width = stars + 1
  local icon = heading_icons[math.min(level, 6)]
  local pad = math.max(width - vim.fn.strdisplaywidth(icon), 0)
  mark(row, 0, {
    virt_text = { { string.rep(' ', pad) .. icon, 'PureOrgH' .. math.min(level, 6) } },
    virt_text_pos = 'overlay',
  })
  if saved('heading_band', true) then
    mark(row, 0, { line_hl_group = 'PureMdH' .. math.min(level, 6) .. 'Bg' })
  end
end

-- ---- lists and checkboxes ----------------------------------------------------
local function item(buf, row, text, info, mark)
  local col = info.indent
  local box, state = text:match('^%s*[-+*%d.)]+%s+()%[([ Xx-])%]', 1)
  if box then
    local box_start = box - 1
    local kind = state == ' ' and 'unchecked' or state == '-' and 'partial' or 'checked'
    -- The bullet is hidden; the icon sits where it was (the '[' is replaced by it, the rest of the box is hidden).
    mark(row, col, { end_col = box_start, conceal = '' })
    local colour = kind == 'checked' and 'PureNoteTaskDone' or kind == 'partial' and 'PureNoteTaskProgress' or 'PureNoteTaskTodo'
    mark(row, box_start, { virt_text = { { checkbox[kind], colour } }, virt_text_pos = 'overlay' })
    mark(row, box_start + 1, { end_col = box_start + 3, conceal = '' })
    if kind == 'checked' then
      mark(row, box_start + 3, { end_col = #text, hl_group = 'PureMdCheckedText' })
    end
    return
  end
  -- Only the unordered bullets change; "1." stays.
  if info.bullet:match('^[-+*]$') then
    mark(row, col, {
      virt_text = { { bullets[(info.depth - 1) % #bullets + 1], 'PureMdBullet' } },
      virt_text_pos = 'overlay',
    })
  end
end

-- ---- blocks ------------------------------------------------------------------
local function block(buf, b, mark)
  local code = b.name ~= 'quote' and b.name ~= 'verse' and b.name ~= 'center'
  for row = b.first, b.last do
    if code then mark(row, 0, { line_hl_group = 'PureMdCode' }) end
  end
  if code then
    -- #+begin_src lua / #+end_src: covered, the language shown as a label on the first line.
    for _, row in ipairs({ b.first, b.last }) do
      local text = lineText(buf, row)
      local indent = #text:match('^%s*')
      local label = row == b.first and (' ' .. (b.lang ~= '' and b.lang or b.name)) or ''
      local cover = vim.fn.strdisplaywidth(text) - indent
      mark(row, indent, {
        virt_text = { { label .. string.rep(' ', math.max(cover - vim.fn.strdisplaywidth(label), 0)), 'PureOrgCodeLabel' } },
        virt_text_pos = 'overlay',
      })
    end
  else
    for row = b.first, b.last do
      local text = lineText(buf, row)
      if row == b.first or row == b.last then
        mark(row, 0, { virt_text = { { string.rep(' ', vim.fn.strdisplaywidth(text)), 'PureMdQuote' } }, virt_text_pos = 'overlay' })
      else
        mark(row, 0, { virt_text = { { '▋', 'PureMdQuote' } }, virt_text_pos = 'overlay' })
      end
    end
  end
end

-- ---- rule and tables ---------------------------------------------------------
local function rule(buf, row, mark)
  local width = vim.api.nvim_win_get_width(0) - vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
  mark(row, 0, { virt_text = { { string.rep('─', width), 'PureMdRule' } }, virt_text_pos = 'overlay' })
end

--- Pipes become │; the rule row (|---+---|) becomes ├───┼───┤.
local function tableRow(buf, row, text, kind, mark)
  if kind == 'tablerule' then
    local indent = #text:match('^%s*')
    local first = text:find('|', 1, true)
    local last_pipe = #text - (text:reverse():find('|', 1, true) or 0) + 1
    local out = {}
    for pos = indent + 1, #text do
      local ch = text:sub(pos, pos)
      if ch == '|' then
        table.insert(out, pos == first and '├' or pos == last_pipe and '┤' or '┼')
      elseif ch == '+' then
        table.insert(out, '┼')
      elseif ch:match('%s') then
        table.insert(out, ch)
      else
        table.insert(out, '─')
      end
    end
    mark(row, indent, { virt_text = { { table.concat(out), 'PureMdTable' } }, virt_text_pos = 'overlay' })
    return
  end
  local col = 0
  while true do
    local p = text:find('|', col + 1, true)
    if not p then break end
    if text:sub(p - 1, p - 1) ~= '\\' then
      mark(row, p - 1, { virt_text = { { '│', 'PureMdTable' } }, virt_text_pos = 'overlay' })
    end
    col = p
  end
  for pos, mark_char in text:gmatch('()%[([ xX])%]') do
    local kind = mark_char == ' ' and 'unchecked' or 'checked'
    mark(row, pos - 1, {
      virt_text = { { checkbox[kind] .. string.rep(' ', 3 - vim.fn.strdisplaywidth(checkbox[kind])),
        kind == 'checked' and 'PureNoteTaskDone' or 'PureNoteTaskTodo' } },
      virt_text_pos = 'overlay',
    })
  end
end

-- ---- links and emphasis --------------------------------------------------------
--- "start:stop" (1-based, stop exclusive) of the [[link]] under byte column `col`, or ''.
local function linkAt(text, col)
  for start, stop in text:gmatch('()%[%[.-%]%]()') do
    if col + 1 >= start and col + 1 < stop then return start .. ':' .. stop end
  end
  return ''
end

local function cursorLink()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local key = linkAt(vim.api.nvim_get_current_line(), col)
  return key ~= '' and (row .. ':' .. key) or ''
end

--- [[target][text]] shows text; [[target]] shows target. The link under the cursor stays raw.
--- The text stays the buffer's own text, only the brackets and the target are concealed: an inline virtual text instead
--- is counted by Neovim on top of the raw width, so a line that fits needed one row more and showed a blank one under it.
local function links(buf, row, text, from, raw_col, mark)
  for start, inner, stop in text:gmatch('()%[%[(.-)%]%]()') do
    if start >= from then
      local key = start .. ':' .. stop
      if inner ~= '' and key ~= raw_col then
        local target, desc = inner:match('^(.-)%]%[(.*)$')
        local first = start + 1 -- 0-based column after '[['
        if desc then
          local shown = first + #target + 2 -- after '][', where the text starts
          -- [[id:ID][Note#Heading||alias]]: the text keeps what the link is to, the render shows the alias only.
          local bar = desc:find('||', 1, true)
          if bar and bar + 1 < #desc then shown = shown + bar + 1 end
          mark(row, start - 1, { end_col = shown, conceal = '' })
          -- [[hl:colour][text]]: a highlight, painted by pure/highlights.lua, not a link colour.
          if not target:match('^hl:') then mark(row, shown, { end_col = stop - 3, hl_group = 'PureMdLink' }) end
        else
          -- [[Note#Heading||alias]] (no target apart from the text): the same, the alias only.
          local bar = inner:find('||', 1, true)
          local shown = first
          if bar and bar + 1 < #inner then shown = first + bar + 1 end
          mark(row, start - 1, { end_col = shown, conceal = '' })
          mark(row, shown, { end_col = stop - 3, hl_group = 'PureMdLink' })
        end
        mark(row, stop - 3, { end_col = stop - 1, conceal = '' })
      end
    end
  end
end

--- The marks around *bold* /italic/ _underline_ =verbatim= ~code~ +strike+, hidden. Org's own rule:
--- the opening mark follows a space or one of -({'" (or starts the text) and is followed by a non-space; the closing mark
--- follows a non-space and is followed by a space, end of text or one of -.,;:!?')}"[ .
local PRE = '[%s%-%(%{\'"]'
local POST = '[%s%-%.,;:!?\'%)%}"%[]'
local function emphasis(row, text, from, covered, mark)
  for _, m in ipairs({ '=', '~', '*', '/', '_', '+' }) do
    local pos = from
    while true do
      local s = text:find(m, pos, true)
      if not s then break end
      local before = s > 1 and text:sub(s - 1, s - 1) or ' '
      local nxt = text:sub(s + 1, s + 1)
      local ok = (s == from or before:match(PRE)) and nxt ~= '' and not nxt:match('%s') and nxt ~= m
      local close
      if ok then
        local e = s + 2
        while true do
          e = text:find(m, e, true)
          if not e then break end
          local prev = text:sub(e - 1, e - 1)
          local after = text:sub(e + 1, e + 1)
          if not prev:match('%s') and (after == '' or after:match(POST)) then close = e break end
          e = e + 1
        end
      end
      if close and not covered[s] and not covered[close] then
        mark(row, s - 1, { end_col = s, conceal = '' })
        mark(row, close - 1, { end_col = close, conceal = '' })
        if m == '=' or m == '~' then
          for i = s, close do covered[i] = true end
        end
        pos = close + 1
      else
        pos = s + 1
      end
    end
  end
end

--- Links and emphasis marks of one line. Neovim sizes a wrapped line by its raw width, concealed text included, so hiding
--- text that makes the line need fewer rows than Neovim reserves leaves blank rows under it (seen in Kitsu on
--- "- Part of: [[id:...][Title]]" in a narrow window). Then the line is left as it is, unless
--- vim.g.pure_org_conceal_wrapped = true asks for the hiding anyway.
local function inline(buf, row, text, from, own_link, emph, mark)
  local pending, saved = {}, 0
  local function collect(row_, col, opts)
    pending[#pending + 1] = { row_, col, opts }
    if opts.conceal then
      saved = saved + vim.fn.strdisplaywidth(text:sub(col + 1, opts.end_col))
    end
  end
  links(buf, row, text, from, own_link, collect)
  if emph then emphasis(row, text, from, {}, collect) end
  if #pending == 0 then return end
  -- (only a window that wraps has the problem: with 'nowrap' every line is one row, raw or not)
  if vim.g.pure_org_conceal_wrapped ~= true and vim.wo.wrap then
    local width = vim.api.nvim_win_get_width(0) - vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
    local raw = vim.fn.strdisplaywidth(text)
    if width > 0 and math.ceil(raw / width) > math.ceil(math.max(raw - saved, 1) / width) then return end
  end
  for _, m in ipairs(pending) do mark(m[1], m[2], m[3]) end
end

--- The text of a headline as the big drawing shows it: [[t][d]] is d, and the marks around emphasis are gone.
plainText = function(text)
  text = text:gsub('%[%[[^%]]*%]%[([^%]]*)%]%]', '%1')
  text = text:gsub('%[%[([^%]]*)%]%]', '%1')
  local cuts = {}
  emphasis(0, text, 1, {}, function(_, col) cuts[#cuts + 1] = col end)
  table.sort(cuts, function(a, b) return a > b end)
  for _, col in ipairs(cuts) do text = text:sub(1, col) .. text:sub(col + 2) end
  return text
end

-- ---- drawers and the title --------------------------------------------------------
local function rangeAt(ranges, row)
  for _, r in ipairs(ranges or {}) do
    if row >= r[1] and row <= r[2] then return r[1] .. ':' .. r[2] end
  end
  return ''
end

-- -----------------------------------------------------------------------------
--  Narrowing wide tables (<leader>tT)
-- -----------------------------------------------------------------------------
--  org.nvim can shrink a column: a column with a width cookie `<W>` shows the first W characters of each
--  cell and a "…", and the text is never changed. Here the toggle works out the widths that make every
--  table wider than the window fit and hands them to that same drawing, so no cookie is written into the
--  note. A column that fits keeps its width; the others share what is left, the widest first. A table with
--  cookies of its own is left to org.nvim. In Insert mode a table shows in full (org.nvim does that).
--  The window does not wrap while a table is shrunk: a raw row longer than the window would otherwise take
--  extra screen rows under the drawing. Saved as `table_shrink`.
local MIN_COLUMN = 4
local shrink_on = saved('table_shrink', false) == true
local original_cookies

local function textWidth(win)
  return vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

local function windowOf(buf)
  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current) == buf then return current end
  return vim.fn.win_findbuf(buf)[1]
end

--- The width of every column of parsed table `t` once it fits `width` columns, and the set of columns that had
--- to shrink (empty when it already fits).
local function fittedWidths(t, o, width)
  local natural = require('org.table').layout(t, o)
  local ncols, total = t.ncols, 0
  for c = 1, ncols do total = total + natural[c] end
  local avail = width - #t.indent - (3 * ncols + 1) -- the pipes and a space each side of every cell
  if total <= avail or avail < ncols * MIN_COLUMN then return natural, {} end
  local widths, left, remaining = {}, avail, {}
  for c = 1, ncols do remaining[c] = c end
  local changed = true
  while changed and #remaining > 0 do
    changed = false
    local share = math.floor(left / #remaining)
    for idx = #remaining, 1, -1 do
      local c = remaining[idx]
      if natural[c] <= share then
        widths[c], left, changed = natural[c], left - natural[c], true
        table.remove(remaining, idx)
      end
    end
  end
  local shrunk = {}
  if #remaining > 0 then
    table.sort(remaining, function(a, b) return natural[a] > natural[b] or (natural[a] == natural[b] and a < b) end)
    local share, extra = math.floor(left / #remaining), left % #remaining
    for i, c in ipairs(remaining) do
      widths[c] = math.max(MIN_COLUMN, share + (i <= extra and 1 or 0))
      if widths[c] < natural[c] then shrunk[c] = true end
    end
  end
  return widths, shrunk
end

--- org.nvim reads the widths from the cookies in the table; while the toggle is on a table without cookies
--- gets the fitted ones (the natural widths when it fits, so nothing is cut).
local function installCookieWidths()
  if original_cookies then return end
  local shrink = require('org.table.shrink')
  original_cookies = shrink.cookie_widths
  shrink.cookie_widths = function(t)
    local own = original_cookies(t)
    if next(own) or not shrink_on then return own end
    local win = windowOf(vim.api.nvim_get_current_buf())
    if not win then return own end
    return (fittedWidths(t, require('org.ui').conceal_opts(0), textWidth(win)))
  end
end

--- The window does not wrap for as long as a reason holds: 'shrink' (a table is shrunk in it) or 'table' (a table row
--- is wider than the window as written). A 'wrap' turned off here is given back when no reason is left.
local function noWrap(win, reason, on)
  local reasons = vim.w[win].pure_org_nowrap_for or {}
  reasons[reason] = on or nil
  vim.w[win].pure_org_nowrap_for = reasons
  local ours = vim.w[win].pure_org_nowrap == true
  if next(reasons) and vim.wo[win].wrap then
    vim.wo[win].wrap, vim.w[win].pure_org_nowrap = false, true
  elseif not next(reasons) and ours then
    vim.wo[win].wrap, vim.w[win].pure_org_nowrap = true, nil
  end
end

--- Calls fn(info, t) for every table of the buffer.
local function eachTable(buf, fn)
  local T = require('org.table')
  local l = 1
  while l <= vim.api.nvim_buf_line_count(buf) do
    local line = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1]
    local info = T.is_table_line(line) and T.find(buf, l) or nil
    if info then
      fn(info, T.parse(info.lines))
      l = info.finish + 1
    else
      l = l + 1
    end
  end
end

local function sameSet(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

--- Shrink the tables of the buffer that do not fit its window and expand the ones that do.
local function applyShrink(buf)
  if not shrink_on or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'org' then return end
  local win = windowOf(buf)
  if not win or vim.fn.mode():match('^[iR]') then return end
  installCookieWidths()
  local shrink = require('org.table.shrink')
  local o = require('org.ui').conceal_opts(buf)
  local width, any = textWidth(win), false
  eachTable(buf, function(info, t)
    if next(original_cookies(t)) then return end
    local _, shrunk = fittedWidths(t, o, width)
    local current = shrink.get(buf, info.start)
    if next(shrunk) then
      any = true
      if not sameSet(current, shrunk) then shrink.set(buf, info.start, shrunk) end
    elseif next(current) then
      shrink.expand(buf, info.start)
    end
  end)
  -- org.nvim only clears the marks inside a table that still exists: a deleted table leaves its inline cells
  -- piled up on the line where it was. Clear the whole namespace; refresh_all redraws the live tables.
  vim.api.nvim_buf_clear_namespace(buf, vim.api.nvim_create_namespace('org.table.shrink'), 0, -1)
  shrink.refresh_all(buf) -- the window may have changed size: the widths are worked out again
  noWrap(win, 'shrink', any)
end

--- Expand the tables this toggle shrank and give the window its 'wrap' back.
local function clearShrink(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'org' then return end
  local shrink = require('org.table.shrink')
  eachTable(buf, function(info, t)
    if not next(original_cookies and original_cookies(t) or shrink.cookie_widths(t)) and next(shrink.get(buf, info.start)) then
      shrink.expand(buf, info.start)
    end
  end)
  vim.api.nvim_buf_clear_namespace(buf, vim.api.nvim_create_namespace('org.table.shrink'), 0, -1) -- marks of deleted tables
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do noWrap(win, 'shrink', false) end
end

--- <leader>tT: shrink the tables wider than the window (and expand them again).
function M.toggleTableShrink()
  shrink_on = not shrink_on
  local ok, toggles = pcall(require, 'configs.functions')
  if ok then toggles.set('table_shrink', shrink_on) end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'org' then
      if shrink_on then applyShrink(b) else clearShrink(b) end
    end
  end
  vim.notify('Table shrink ' .. (shrink_on and 'on' or 'off'))
end

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinResized', 'InsertLeave', 'TextChanged' }, {
  group = vim.api.nvim_create_augroup('PureOrgTableShrink', { clear = true }),
  callback = function(args)
    if not shrink_on or vim.bo[args.buf].filetype ~= 'org' then return end
    -- After org.nvim's own alignment on opening (it is scheduled).
    vim.defer_fn(function() applyShrink(args.buf) end, args.event == 'BufWinEnter' and 60 or 0)
  end,
})
-- A window that leaves the note gets its 'wrap' back (the other buffer must not inherit the nowrap).
vim.api.nvim_create_autocmd('BufWinLeave', {
  group = 'PureOrgTableShrink',
  callback = function(args)
    if vim.bo[args.buf].filetype == 'org' then
      local win = vim.api.nvim_get_current_win()
      noWrap(win, 'shrink', false)
      noWrap(win, 'table', false)
    end
  end,
})

-- -----------------------------------------------------------------------------
--  Wrapping wide tables into rows (<leader>tW)
-- -----------------------------------------------------------------------------
--  The other way to make a table fit the window, and this one changes the text: a cell that does not
--  fit its column goes on the next line, as an extra table row that holds only the rest of that
--  cell (the other cells of the row empty). Widths are worked out as for shrinking (above) and the
--  rows are written aligned by org.nvim's own formatter, so the columns line up on the screen as
--  they do in the text. It runs when a note is opened and when Insert mode is left in a table; a
--  table that already fits is left alone, as one with a #+TBLFM line. The continuation rows are
--  remembered (extmarks), so turning the toggle off joins them back into their rows (this session
--  only: a row written in an earlier session is an ordinary row). Saved as `table_wrap`.
--  A script that reads the note's tables will see the extra rows: the toggle is off by default.
local wrap_rows_on = saved('table_wrap', false) == true
local cont_ns = vim.api.nvim_create_namespace('pure_org_table_cont')
local cont_glue = {} -- "buf:extmark id" of a continuation row -> { [column] = true } where it goes on from a cut word

--- `raw` cut at spaces into tokens that are not split: a [[link]] and an =verbatim= or ~code~ keep their spaces.
local function rawTokens(raw)
  local tokens, i = {}, 1
  while i <= #raw do
    if raw:sub(i, i):match('%s') then
      i = i + 1
    else
      local j = i
      local mark = raw:sub(i, i)
      if mark == '=' or mark == '~' then
        local close = raw:find(mark, i + 2, true)
        if close and not raw:sub(close - 1, close - 1):match('%s') then j = close + 1 end
      end
      while j <= #raw and not raw:sub(j, j):match('%s') do
        if raw:sub(j, j + 1) == '[[' then
          local close = raw:find(']]', j + 2, true)
          j = close and close + 2 or j + 2
        else
          j = j + 1
        end
      end
      tokens[#tokens + 1] = raw:sub(i, j - 1)
      i = j
    end
  end
  return tokens
end

--- `raw` (a cell as written) in lines that show at most `width` columns. A token that is too wide alone goes
--- on a line of its own; a plain one (no link, no marks) is cut where it must be.
--- Second result: `glued[i]` is true when line i goes on from line i-1 in the middle of a word (a cut one), so
--- joining the lines back must not put a space between them.
local function wrapRaw(raw, width, o)
  local ui = require('org.ui')
  local lines, glued, line, line_width = {}, {}, '', 0
  local function flush() lines[#lines + 1], line, line_width = line, '', 0 end
  for _, token in ipairs(rawTokens(raw)) do
    local token_width = ui.visible_width(token, o)
    local plain = not token:find('[%[%]=~]')
    local cut = false -- the token was cut: what is left goes on from the piece before
    while plain and token_width > width do
      if line_width > 0 then flush() end
      local piece, taken = '', 0
      for ci = 0, vim.fn.strchars(token) - 1 do
        local ch = vim.fn.strcharpart(token, ci, 1)
        if vim.fn.strdisplaywidth(piece .. ch) > width then break end
        piece, taken = piece .. ch, ci + 1
      end
      if taken == 0 then taken, piece = 1, vim.fn.strcharpart(token, 0, 1) end
      if cut then glued[#lines + 1] = true end
      lines[#lines + 1] = piece
      cut = true
      token = vim.fn.strcharpart(token, taken)
      token_width = vim.fn.strdisplaywidth(token)
    end
    if token ~= '' then
      if line_width == 0 then
        if cut then glued[#lines + 1] = true end
        line, line_width = token, token_width
      elseif line_width + 1 + token_width <= width then
        line, line_width = line .. ' ' .. token, line_width + 1 + token_width
      else
        flush()
        line, line_width = token, token_width
      end
    end
  end
  if line_width > 0 or #lines == 0 then flush() end
  return lines, glued
end

--- Rewrite the table `info` so that it fits `width`. Returns the number of rows added (0: nothing changed) and, for
--- each original row, the buffer line (1-based) where it now starts.
local function wrapTable(buf, info, t, o, width)
  if #info.tblfm > 0 then return 0 end
  local widths, shrunk = fittedWidths(t, o, width)
  if not next(shrunk) then return 0 end
  local rows, starts, added = {}, {}, {}
  for i, row in ipairs(t.rows) do
    starts[i] = info.start + #rows
    if row.hline then
      rows[#rows + 1] = { hline = true }
    else
      local pieces, glued, height = {}, {}, 1
      for c = 1, t.ncols do
        pieces[c], glued[c] = wrapRaw(vim.trim(row.cells[c] or ''), widths[c], o)
        height = math.max(height, #pieces[c])
      end
      for h = 1, height do
        local cells, glue = {}, {}
        for c = 1, t.ncols do
          cells[c] = pieces[c][h] or ''
          glue[c] = glued[c][h] or nil
        end
        if h > 1 then added[#added + 1] = { lnum = info.start + #rows, glue = glue } end
        rows[#rows + 1] = { cells = cells }
      end
    end
  end
  local lines = require('org.table').render({ indent = t.indent, rows = rows, ncols = t.ncols })
  if vim.deep_equal(lines, info.lines) then return 0 end
  vim.api.nvim_buf_set_lines(buf, info.start - 1, info.finish, false, lines)
  for _, a in ipairs(added) do
    local id = vim.api.nvim_buf_set_extmark(buf, cont_ns, a.lnum - 1, 0, {})
    cont_glue[buf .. ':' .. id] = a.glue
  end
  return #added, starts
end

--- Wrap every table of the buffer that does not fit its window. Returns how many tables changed.
local function wrapTables(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'org' or not vim.bo[buf].modifiable then return 0 end
  local win = windowOf(buf)
  if not win then return 0 end
  local o, width = require('org.ui').conceal_opts(buf), textWidth(win)
  local found = {}
  eachTable(buf, function(info, t) found[#found + 1] = { info = info, t = t } end)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local changed, moved = 0, 0
  for k = #found, 1, -1 do -- from the bottom, so the lines of the tables above do not move
    local info = found[k].info
    local added, starts = wrapTable(buf, info, found[k].t, o, width)
    if added > 0 then
      changed = changed + 1
      if cursor[1] >= info.start and cursor[1] <= info.finish then
        local row = cursor[1] - info.start + 1 -- the row the cursor was on, now at its first line
        moved = starts[row] - cursor[1]
      elseif cursor[1] > info.finish then
        moved = moved + added
      end
    end
  end
  if changed > 0 and moved ~= 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { math.max(cursor[1] + moved, 1), cursor[2] })
  end
  return changed
end

--- Join the continuation rows this session made back into their rows.
local function unwrapTables(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then return end
  local T = require('org.table')
  local marks = vim.api.nvim_buf_get_extmarks(buf, cont_ns, 0, -1, {})
  for k = #marks, 1, -1 do -- from the bottom: a row split in three folds in two steps, in order
    local lnum = marks[k][2] + 1
    local prev_line = vim.api.nvim_buf_get_lines(buf, lnum - 2, lnum - 1, false)[1]
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
    if lnum > 1 and prev_line and line and T.is_table_line(prev_line) and T.is_table_line(line) then
      local upper, lower = T.parse({ prev_line }).rows[1], T.parse({ line }).rows[1]
      if upper.cells and lower.cells then
        local cells = {}
        local glue = cont_glue[buf .. ':' .. marks[k][1]] or {}
        for c = 1, math.max(#upper.cells, #lower.cells) do
          local a, b = vim.trim(upper.cells[c] or ''), vim.trim(lower.cells[c] or '')
          cells[c] = (a ~= '' and b ~= '' and not glue[c]) and (a .. ' ' .. b) or (a .. b)
        end
        local indent = prev_line:match('^%s*')
        vim.api.nvim_buf_set_lines(buf, lnum - 2, lnum, false, { indent .. '| ' .. table.concat(cells, ' | ') .. ' |' })
      end
    end
    pcall(vim.api.nvim_buf_del_extmark, buf, cont_ns, marks[k][1])
    cont_glue[buf .. ':' .. marks[k][1]] = nil
  end
  vim.api.nvim_buf_clear_namespace(buf, cont_ns, 0, -1)
  -- Pad the joined rows again (org.nvim's own alignment, by the width the buffer shows).
  local T2 = require('org.table')
  pcall(T2.align_all, buf)
end

--- <leader>tW: wrap the tables wider than the window into rows (and join them back).
function M.toggleTableWrap()
  wrap_rows_on = not wrap_rows_on
  local ok, toggles = pcall(require, 'configs.functions')
  if ok then toggles.set('table_wrap', wrap_rows_on) end
  local buf = vim.api.nvim_get_current_buf()
  local changed = 0
  if wrap_rows_on then
    changed = wrapTables(buf)
  else
    unwrapTables(buf)
  end
  vim.notify('Table wrap ' .. (wrap_rows_on and 'on' or 'off') .. (changed > 0 and (' (' .. changed .. ' tables)') or ''))
end

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'InsertLeave' }, {
  group = vim.api.nvim_create_augroup('PureOrgTableWrap', { clear = true }),
  callback = function(args)
    if not wrap_rows_on or vim.bo[args.buf].filetype ~= 'org' then return end
    -- After org.nvim's own alignment (on opening it is scheduled, on leaving Insert mode it runs in this event).
    vim.defer_fn(function() wrapTables(args.buf) end, args.event == 'BufWinEnter' and 80 or 10)
  end,
})

-- -----------------------------------------------------------------------------
--  Driver
-- -----------------------------------------------------------------------------
local function active(buf)
  return enabled and vim.bo[buf].filetype == 'org'
    and (vim.bo[buf].buftype == '' or vim.b[buf].pure_orgview == true)
end

local drawn = {}      -- buf -> extmark id -> key of what it draws
local last_state = {} -- buf -> what the last refresh saw

--- Make the buffer's marks `want` ({ row, col, opts, key }), touching only what differs from what is drawn
--- (clearing and redrawing everything flickers while typing; see render-md.lua).
local function reconcile(buf, want)
  local have = drawn[buf] or {}
  local keep = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local id = m[1]
    local key = have[id] and (m[2] .. ':' .. m[3] .. ':' .. have[id])
    -- A mark whose end is no longer the one it was drawn with is stale (a replaced line collapses its marks).
    local drawn_end = key and have[id]:match('end_col = (%d+)')
    if drawn_end and (m[4].end_col ~= tonumber(drawn_end)
        or (not have[id]:find('end_row', 1, true) and (m[4].end_row or m[2]) ~= m[2])) then
      key = nil
    end
    if key and not keep[key] then
      keep[key] = id
    else
      vim.api.nvim_buf_del_extmark(buf, ns, id)
      have[id] = nil
    end
  end
  local now = {}
  for _, w in ipairs(want) do
    local key = w.row .. ':' .. w.col .. ':' .. w.key
    local id = keep[key]
    if id then
      keep[key] = nil
      now[id] = w.key
    else
      local ok, new_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, w.row, w.col, w.opts)
      if ok then now[new_id] = w.key end
    end
  end
  for _, id in pairs(keep) do vim.api.nvim_buf_del_extmark(buf, ns, id) end
  drawn[buf] = now
end

--- Redraw the visible part of the current window's buffer. Skipped when nothing it depends on changed (text, cursor,
--- view, mode); `force` redraws anyway.
function M.refresh(force)
  local buf = vim.api.nvim_get_current_buf()
  if not active(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    drawn[buf], last_state[buf] = nil, nil
    noWrap(0, 'table', false) -- the rendering is off: the text is as written, nothing hides
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local mode = vim.fn.mode()
  local view = table.concat({ vim.fn.line('w0'), vim.fn.line('w$'), vim.api.nvim_win_get_width(0), mode }, ':')
  local key = table.concat({ vim.b[buf].changedtick, cursor[1], cursor[2], view }, ':')
  if not force and last_state[buf] == key then return end
  last_state[buf] = key

  local info = scan(buf)

  -- A table row wider than the window as written (a long [[link]] counts in full, the render hides it) would wrap into
  -- extra screen rows and break the table: the window does not wrap while one is in view. vim.g.pure_org_table_nowrap
  -- = false turns it off.
  local text_width = vim.api.nvim_win_get_width(0) - vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
  local wide_table = false
  if vim.g.pure_org_table_nowrap ~= false then
    for row = vim.fn.line('w0') - 1, vim.fn.line('w$') - 1 do
      local r = info.rows[row]
      if r and (r.kind == 'table' or r.kind == 'tablerule')
        and vim.fn.strdisplaywidth(info.lines[row + 1] or '') > text_width then
        wide_table = true
        break
      end
    end
  end
  noWrap(0, 'table', wide_table)

  -- Only the rows on screen, plus a margin so short scrolls look finished.
  local top = math.max(vim.fn.line('w0') - 1 - 20, 0)
  local bottom = vim.fn.line('w$') + 20
  -- The cursor line is left raw while editing it.
  local raw_row = (mode:match('^[iRvV\22]')) and (cursor[1] - 1) or -1
  local cursor_row = cursor[1] - 1

  local want = {}
  local function place(row, col, opts)
    opts.priority = opts.priority or 200
    table.insert(want, { row = row, col = col, opts = opts, key = vim.inspect(opts, { newline = '', indent = '' }) })
  end
  local function mark(row, col, opts)
    if row == raw_row or row < top or row > bottom then return end
    place(row, col, opts)
  end

  -- Hidden drawers, except the one the cursor is in.
  local hidden = {}
  for _, d in ipairs(info.drawers) do
    hidden[#hidden + 1] = { d.first, d.last }
    if cursor_row < d.first or cursor_row > d.last then
      for row = d.first, d.last do
        if row >= top and row <= bottom then place(row, 0, { conceal_lines = '' }) end
      end
    end
  end

  for _, b in ipairs(info.blocks) do
    if b.last >= top and b.first <= bottom then block(buf, b, mark) end
  end

  local raw_link = ''
  if cursor_row >= 0 then
    local c = linkAt(info.lines[cursor_row + 1] or '', cursor[2])
    raw_link = c
  end
  local emph = vim.g.pure_org_emphasis ~= false

  for row = top, math.min(bottom, #info.lines - 1) do
    local r = info.rows[row]
    local text = info.lines[row + 1] or ''
    if row ~= raw_row and r then
      local from = 1 -- where the plain text of the line starts (after the stars, the bullet, the box)
      if r.kind == 'headline' then
        headline(row, r, mark)
        from = r.stars + 2
      elseif r.kind == 'item' then
        item(buf, row, text, r, mark)
        from = r.indent + #r.bullet + r.gap + 1
      elseif r.kind == 'rule' then
        rule(buf, row, mark)
      elseif r.kind == 'table' or r.kind == 'tablerule' then
        tableRow(buf, row, text, r.kind, mark)
      elseif r.kind == 'title' then
        local prefix = text:match('^%s*#%+[Tt][Ii][Tt][Ll][Ee]:%s*')
        mark(row, 0, { end_col = #prefix, conceal = '' })
        mark(row, #prefix, { end_col = #text, hl_group = 'PureOrgH1' })
      end
      if r.kind == 'headline' or r.kind == 'item' or r.kind == 'title' or r.kind == 'table' then
        inline(buf, row, text, from, row == cursor_row and raw_link or '', emph, mark)
      end
    elseif row ~= raw_row and not r and text:match('%S') then
      -- Plain text: links and emphasis too.
      inline(buf, row, text, 1, row == cursor_row and raw_link or '', emph, mark)
    end
  end

  reconcile(buf, want)
  vim.b[buf].pure_org_hidden = hidden
  vim.b[buf].pure_org_revealed = rangeAt(hidden, cursor_row)
  vim.b[buf].pure_org_link = cursorLink()
end

local NEXT = { full = 'off', off = 'full' }
local LABEL = { full = 'on', off = 'off' }

--- The big headlines (OSC 66 / DECDHL, <leader>tM) need the rendering on too.
local function bigHeadings(on)
  local ok, toggles = pcall(require, 'configs.functions')
  return on and ok and toggles.get('big_headings', false) == true
end

function M.set_level(want)
  if not NEXT[want] then return end
  level = want
  enabled = want ~= 'off'
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'org' then syncTableWidths(b) end
  end
  local ok, toggles = pcall(require, 'configs.functions')
  if ok then toggles.set('render_org', want) end
  Headings.set_enabled(bigHeadings(enabled))
  M.refresh(true)
  vim.notify('Org rendering ' .. LABEL[want])
end

--- <leader>tM changed: draw or stop drawing the big headlines.
function M.applyBigHeadings()
  Headings.set_enabled(bigHeadings(enabled))
  M.refresh(true)
end

function M.level() return level end

function M.toggle()
  M.set_level(NEXT[level])
end

local group = vim.api.nvim_create_augroup('PureOrgview', { clear = true })

vim.api.nvim_create_autocmd(
  { 'BufWinEnter', 'WinScrolled', 'TextChanged', 'TextChangedI', 'CursorMoved', 'CursorMovedI', 'ModeChanged', 'WinResized' }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype ~= 'org' then return end
      -- In normal mode plain movement needs no redraw, unless it enters or leaves a hidden drawer or a link.
      if args.event == 'CursorMoved' and vim.fn.mode() == 'n'
        and rangeAt(vim.b[args.buf].pure_org_hidden, vim.fn.line('.') - 1) == vim.b[args.buf].pure_org_revealed
        and cursorLink() == vim.b[args.buf].pure_org_link then
        return
      end
      M.refresh()
    end,
  })

-- Scheduled so it runs after the FileType handler above, which sets the colours the bands are computed from.
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'org',
  callback = function() vim.schedule(function() setHighlights(); M.refresh(true) end) end,
})
vim.api.nvim_create_autocmd('BufWipeout', {
  group = group,
  callback = function(args) scan_cache[args.buf], drawn[args.buf], last_state[args.buf] = nil, nil, nil end,
})
vim.api.nvim_create_autocmd('ColorScheme', {
  group = group,
  callback = function()
    setHighlights()
    vim.schedule(function() M.refresh(true) end)
  end,
})
setHighlights()

-- Bigger headlines where the terminal can do it; a no-op elsewhere.
Headings.setup()

M.headings = Headings

return M
