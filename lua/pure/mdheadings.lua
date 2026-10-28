-- =============================================================================
--  Markdown headings at a bigger size
-- =============================================================================
--  pure.mdview draws every heading the same size; this module makes `#` and `##` bigger when the terminal can do it:
--
--    kitty    the text sizing protocol (OSC 66): # = scale 3, ## = scale 2
--    WezTerm  the VT100 double-height lines (DECDHL): # and ## are 2x, on two screen rows
--    others   nothing changes: mdview draws the headings as before
--
--  vim.g.pure_md_headings: 'auto' (default: look at the terminal), 'osc66', 'decdhl' or 'off'.
--  :PureMdHeadings [auto|osc66|decdhl|off] changes it at run time. KITTY_WINDOW_ID, WEZTERM_PANE and TERM_PROGRAM tell the terminal;
--  Neovim inside WSL does not get WezTerm's variables, so there set vim.g.pure_md_headings = 'decdhl'.
--
--  How it avoids garbage on the screen (the same idea for both): Neovim repaints only the cells that changed, and a repaint over
--  a block leaves pieces of it. So the cells under a block must never change: the raw heading text is covered with spaces (an
--  overlay extmark) and the extra rows are reserved with blank virt_lines. Neovim then always sees the same blank cells there. The
--  blocks are written with nvim_ui_send after anything that moves them, and the old ones are erased BEFORE Neovim repaints (a
--  decoration provider). The heading under the cursor shows its raw text (its block is erased first).
--
--  DECDHL limits: the double-height attribute belongs to the whole screen row (the line number of a heading disappears), and the
--  text starts at the window's text column; so it is only used when the window spans the whole terminal width. In a split the
--  headings fall back to mdview's own drawing.
-- =============================================================================

local M = {}

local ESC = string.char(27)
local BEL = string.char(7)
local ns = vim.api.nvim_create_namespace('pure_md_headings')

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
  local want = vim.g.pure_md_headings
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
-- { { row (0-based), level, text } } from the markdown tree, so a '# comment' in a code block is not a heading.
local function headingsOf(buf)
  local tick = vim.b[buf].changedtick
  local c = cache[buf]
  if c and c.tick == tick then return c.list end
  local list = {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local function add(row, level, line)
    local text = line:gsub('^%s*#+%s*', ''):gsub('%s+#+%s*$', ''):gsub('%s+$', '')
    if text ~= '' then list[#list + 1] = { row = row, level = level, text = text } end
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if ok and parser then
    local trees = parser:parse()
    local qok, query = pcall(vim.treesitter.query.parse, 'markdown', '(atx_heading) @h')
    if trees[1] and qok then
      for _, node in query:iter_captures(trees[1]:root(), buf) do
        local marker = node:child(0)
        local level = marker and tonumber(marker:type():match('atx_h(%d)_marker'))
        local row = node:start()
        if level and lines[row + 1] then add(row, level, lines[row + 1]) end
      end
      cache[buf] = { tick = tick, list = list }
      return list
    end
  end
  -- No parser: '#'s at the start of a line, outside fenced blocks.
  local fence
  for i, line in ipairs(lines) do
    local f = line:match('^%s*(```)') or line:match('^%s*(~~~)')
    if f then fence = (fence == f) and nil or (fence or f) end
    if not fence then
      local hashes = line:match('^(#+)%s')
      if hashes and #hashes <= 6 then add(i - 1, #hashes, line) end
    end
  end
  cache[buf] = { tick = tick, list = list }
  return list
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
  local fg = rgb({ 'PureMdH' .. level, '@markup.heading.' .. level .. '.markdown', 'markdownH' .. level, 'Title' }, 'fg') or '39'
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
  return state.mode and state.enabled and vim.bo[buf].filetype == 'markdown'
    and (vim.bo[buf].buftype == '' or vim.b[buf].pure_mdview == true)
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
  local ok, mdview = pcall(require, 'pure.mdview')
  if ok then mdview.refresh(true) end
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
  local group = vim.api.nvim_create_augroup('PureMdHeadings', { clear = true })

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

  vim.api.nvim_create_user_command('PureMdHeadings', function(opts)
    if opts.args ~= '' then vim.g.pure_md_headings = opts.args end
    M.setup()
    vim.notify('Markdown headings: ' .. (state.mode or 'off'))
  end, {
    nargs = '?',
    complete = function() return { 'auto', 'osc66', 'decdhl', 'off' } end,
    desc = 'Bigger markdown headings (kitty OSC 66 / WezTerm DECDHL)',
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
