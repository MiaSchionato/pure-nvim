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
--    <leader>om   toggle the rendering (M.toggle)
-- =============================================================================

local M = {}
local View, Headings -- the sections below; they call into each other
View = M

-- The base groups (PureMd*: code shade, bullets, rule, table, bands) are defined by the Markdown file.
pcall(require, 'pure.render-md')
local notecolors = require('pure.notecolors')

local ns = vim.api.nvim_create_namespace('pure_orgview')
local enabled = true

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
        local text = title:gsub('%s+:[%w_@#%%:]+:%s*$', '') -- without the tags
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
  enabled = true,  -- mdview's toggle
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
      if lnum ~= state.cursor then
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
  local out = {}
  for _, h in ipairs(headingsOf(buf)) do
    local lnum = h.row + 1
    local height = heightOf(h.level)
    if height and lnum >= vim.fn.line('w0') and lnum <= vim.fn.line('w$') and lnum ~= state.cursor then
      local row, col = blockOrigin(win, lnum, height)
      if row then out[#out + 1] = drawBlock(win, h, lnum, row, col) end
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

  -- Before each redraw cycle: when the window scrolled, resized or the text changed, the old blocks go first.
  vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, win, buf, topline)
      if not state.mode or win ~= vim.api.nvim_get_current_win() then return end
      local key = table.concat({ topline, vim.api.nvim_buf_get_changedtick(buf), vim.api.nvim_win_get_height(win), vim.api.nvim_win_get_width(win) }, ':')
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
local embed_icon = '\u{F0219}'

-- Colours: org uses the groups of the Markdown view, which link to the theme.
local function setHighlights()
  notecolors.apply()
  for level = 1, 6 do
    vim.api.nvim_set_hl(0, 'PureOrgH' .. level, { link = '@markup.heading.' .. level .. '.markdown' })
  end
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
  mark(row, 0, { line_hl_group = 'PureMdH' .. math.min(level, 6) .. 'Bg' })
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
        virt_text = { { label .. string.rep(' ', math.max(cover - vim.fn.strdisplaywidth(label), 0)), 'PureMdCodeLabel' } },
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
local function links(buf, row, text, from, raw_col, mark)
  for start, inner, stop in text:gmatch('()%[%[(.-)%]%]()') do
    if start >= from then
      local key = start .. ':' .. stop
      if inner ~= '' and key ~= raw_col then
        local target, desc = inner:match('^(.-)%]%[(.*)$')
        local shown = desc or inner
        local hl = 'PureMdLink'
        if not desc and inner:match('^id:') then shown = embed_icon .. ' ' .. inner:sub(4); hl = 'PureMdLink' end
        mark(row, start - 1, { end_col = stop - 1, conceal = '', virt_text = { { shown, hl } }, virt_text_pos = 'inline' })
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

-- ---- drawers and the title --------------------------------------------------------
local function rangeAt(ranges, row)
  for _, r in ipairs(ranges or {}) do
    if row >= r[1] and row <= r[2] then return r[1] .. ':' .. r[2] end
  end
  return ''
end

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
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local mode = vim.fn.mode()
  local view = table.concat({ vim.fn.line('w0'), vim.fn.line('w$'), vim.api.nvim_win_get_width(0), mode }, ':')
  local key = table.concat({ vim.b[buf].changedtick, cursor[1], cursor[2], view }, ':')
  if not force and last_state[buf] == key then return end
  last_state[buf] = key

  local info = scan(buf)
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
        local covered = {}
        local own = row == cursor_row and raw_link or ''
        links(buf, row, text, from, own, mark)
        if emph then emphasis(row, text, from, covered, mark) end
      end
    elseif row ~= raw_row and not r and text:match('%S') then
      -- Plain text: links and emphasis too.
      local covered = {}
      local own = row == cursor_row and raw_link or ''
      links(buf, row, text, 1, own, mark)
      if emph then emphasis(row, text, 1, covered, mark) end
    end
  end

  reconcile(buf, want)
  vim.b[buf].pure_org_hidden = hidden
  vim.b[buf].pure_org_revealed = rangeAt(hidden, cursor_row)
  vim.b[buf].pure_org_link = cursorLink()
end

function M.toggle()
  enabled = not enabled
  Headings.set_enabled(enabled)
  M.refresh()
  vim.notify('Org rendering ' .. (enabled and 'on' or 'off'))
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
