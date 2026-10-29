-- =============================================================================
--  Markdown rendering: settings, view and bigger headings, in one file
-- =============================================================================
--  What used to be render-md.lua (the settings of a markdown buffer), mdview.lua (the
--  drawing in place) and mdheadings.lua (bigger # and ## where the terminal can). Colours:
--  pure/notecolors.lua, which follows the colorscheme. The org twin of this file is
--  pure/render-org.lua.
--
--    <leader>om   toggle the rendering (M.toggle; it is the org toggle in org notes)
--    :PureMdHeadings [auto|osc66|decdhl|off]
-- =============================================================================

local M = {}
local View, Headings -- the sections below; the settings and the headings call into them

-- -----------------------------------------------------------------------------
--  Settings of a markdown buffer
-- -----------------------------------------------------------------------------
local mdGroup = vim.api.nvim_create_augroup("PureMarkdown", { clear = true})

-- While typing, **bold** and `code` flashed back to their raw marks for one
-- key (Improvment.md). Since Neovim 0.11 treesitter parses asynchronously
-- once a parse takes over 3 ms, which a note with its inline markdown does;
-- the screen was drawn in between, with no highlight yet. Parsing
-- synchronously (vim.g._ts_force_sync_parsing, Neovim's own switch) is only
-- turned on in markdown buffers: notes are small, while a large code file
-- could make every key wait for the parse.
-- FileType too: a buffer made markdown after it was entered (:set ft=markdown)
-- got it only on the next BufEnter. Only for the current buffer, or a buffer
-- loaded in the background would decide for the one being edited.
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
  group = mdGroup,
  callback = function(args)
    if args.buf ~= vim.api.nvim_get_current_buf() then return end
    vim.g._ts_force_sync_parsing = vim.bo[args.buf].filetype == "markdown" or nil
  end,
})

--- <C-l> in insert mode (mapped below): the last really misspelled word
--- before the cursor on this line becomes the first spelling suggestion.
function M.fixLastWord()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before = line:sub(1, col)
  -- vim.spell.check gives { word, type, 1-based start col }; type 'bad'
  -- only: 'rare', 'local' and 'caps' are left alone.
  local last
  for _, hit in ipairs(vim.spell.check(before)) do
    if hit[2] == 'bad' then last = hit end
  end
  if not last then return vim.notify('No misspelled word before the cursor') end
  local word, start = last[1], last[3] - 1
  local fix = vim.fn.spellsuggest(word, 1)[1]
  if not fix then return vim.notify('No suggestion for "' .. word .. '"') end
  vim.api.nvim_buf_set_text(0, row - 1, start, row - 1, start + #word, { fix })
  vim.api.nvim_win_set_cursor(0, { row, col + #fix - #word })
end

--- 'formatexpr' of notes: the automatic line break while typing ('t' in
--- 'formatoptions', at 'textwidth') never falls inside a [[wikilink]]. Vim
--- broke at the last blank before the limit, also between [[ and ]], and a
--- link split over two lines is no link, in Obsidian either (Improvment.md:
--- "[[Build to learn" / "& build to earn]]"). There the line breaks before
--- the link instead; a link that does not fit even so stays on the line,
--- longer than 'textwidth'. A [[ not closed yet (the link being typed)
--- counts to the end of the line. Everything else, gq included, is Vim's.
function M.formatexpr()
  if vim.v.char == '' or not vim.fn.mode():match('^[iR]') then return 1 end
  local lnum, tw = vim.v.lnum, vim.bo.textwidth
  local line = vim.fn.getline(lnum)

  local links, from = {}, 1
  while true do
    local s = line:find('[[', from, true)
    if not s then break end
    local e = line:find(']]', s + 2, true)
    table.insert(links, { s, e and e + 1 or #line + 1 })
    if not e then break end
    from = e + 2
  end
  if #links == 0 then return 1 end

  --- The last blank before byte `limit` whose text before it fits.
  local function lastBlank(limit)
    local best
    for p in line:gmatch('()%s') do
      if p >= limit then break end
      if vim.fn.strdisplaywidth(line:sub(1, p - 1)) <= tw then best = p end
    end
    return best
  end
  local p = lastBlank(#line + 1)
  if not p then return 1 end
  local link
  for _, l in ipairs(links) do
    if p > l[1] and p < l[2] then link = l end
  end
  if not link then return 1 end
  local q = lastBlank(link[1])
  if not q then return 0 end

  -- What the next line starts with, as Vim's own break gives it: the quote
  -- marks of a blockquote ('q'), the indent of a list item's text ('n').
  local lead = line:match('^(%s*>[>%s]*)')
  if not lead then
    local item = line:match('^(%s*[-*+] %[.%] )') or line:match('^(%s*[-*+] )') or line:match('^(%s*%d+[.)] )')
    lead = item and string.rep(' ', vim.fn.strdisplaywidth(item)) or line:match('^%s*')
  end
  local before = (line:sub(1, q - 1):gsub('%s+$', ''))
  local after = (line:sub(q + 1):gsub('^%s+', ''))
  local col, cut = vim.fn.col('.') - 1, #line - #after
  vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { before, lead .. after })
  if col >= cut then
    vim.api.nvim_win_set_cursor(0, { lnum + 1, #lead + col - cut })
  else
    vim.api.nvim_win_set_cursor(0, { lnum, math.min(col, #before) })
  end
  return 0
end


vim.api.nvim_create_autocmd("FileType", {
  group = mdGroup,
  pattern =  "markdown",
  callback = function(args)
    vim.opt_local.textwidth = 110
    vim.opt_local.formatoptions = "tcnq"
    vim.opt_local.formatexpr = "v:lua.require'pure.render-md'.formatexpr()"
    vim.opt_local.spell = true

    -- Only enable languages whose word list is actually present. A missing one
    -- makes Neovim warn ('Cannot find word list "pt.utf-8.spl"') every single
    -- time a markdown buffer opens, and prompt to download it.
    -- Brazilian Portuguese: with the region, European spellings ("facto")
    -- are marked as regional words. vim.g.pure_spelllang overrides the list.
    local wanted = vim.g.pure_spelllang or { "pt_br", "en", "it" }
    local available = {}
    for _, lang in ipairs(wanted) do
      local base = lang:gsub("_.*", "")   -- 'pt_br' looks for 'pt.<enc>.spl'
      if vim.fn.globpath(vim.o.runtimepath, "spell/" .. base .. ".*.spl") ~= "" then
        table.insert(available, lang)
      end
    end
    vim.opt_local.spelllang = #available > 0 and available or { "en" }
    -- Better suggestions: "best" ranks by closeness across the three
    -- languages, and 9 keeps z= on one screen. camel checks each part of
    -- camelCase words instead of flagging the whole word.
    vim.opt_local.spellsuggest = "best,9"
    vim.opt_local.spelloptions = "camel"
    -- No "kspell" in 'complete': with autocomplete on, every word typed would
    -- open a menu of dictionary words, and <CR> now takes its first item.

    -- Keep indentation
    vim.opt_local.autoindent = true
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc" -- Hide in normal and command modes

    -- Heading and checkbox colours: pure/notecolors.lua (they follow the colorscheme).
    require("pure.notecolors").apply()

    -- Headings, bullets, checkboxes and the rest are drawn by the view below.
    -- The regex conceals that used to be here matched inside code blocks too,
    -- and matchadd() is per window, so they piled up on every FileType.

    -- Keymaps
    vim.keymap.set("n", "<leader>ft", "'[,']!column -t -s '|' -o '|'", {buffer = true}) -- Table format
    vim.keymap.set("n", "<leader>ds", "z=", {buffer = true}) -- Dictionary suggert
    vim.keymap.set("n", "<leader>dg", "zg", {buffer = true}) -- Dictionary Good (Add word to dictionary)
    vim.keymap.set("n", "<leader>dw", "zw", {buffer = true}) -- Dictionary Wrong (word)
    vim.keymap.set("n", "<leader>dp", "[s", {buffer = true}) -- Dictionary previous misspelled word
    vim.keymap.set("n", "<leader>dn", "]s", {buffer = true}) -- Dictionary next misspelled word
    -- Autocorrect on demand: <C-l> in insert mode replaces the last misspelled
    -- word before the cursor, on this line, with the first suggestion, and
    -- the cursor stays where it was (moved by the length difference). Undo
    -- (u) takes back just the correction, thanks to the <C-g>u around it.
    -- Added for Improvment.md in the vault: a fix meant leaving insert mode.
    --
    -- The first version was <Esc>[s1z=`]a, which did not work well: [s also
    -- stops on rare and regional words (many, with three languages on) and
    -- "fixed" correct ones; with no bad word on the line it wrapped around
    -- the file and changed a word far away; and leaving insert mode moved
    -- the cursor. This only looks at this line, before the cursor, at words
    -- that are really wrong.
    vim.keymap.set("i", "<C-l>", function()
      return "<C-g>u<Cmd>lua require('pure.render-md').fixLastWord()<CR><C-g>u"
    end, { buffer = true, expr = true, desc = "Fix the last misspelled word" })
    vim.keymap.set("n", "<leader>tx", require('configs.functions').toggleCheckbox, { buffer = true, desc = "Alternar Checkbox" })
    -- Obsidian's extra states, in notes only: the Todoist list is markdown too
    -- (a buffer with buftype set), but Todoist knows just [ ] and [x].
    if vim.bo[args.buf].buftype == "" then
      vim.keymap.set("n", "<leader>x", require('configs.functions').cycleCheckbox,
        { buffer = args.buf, desc = "Cycle checkbox state" })
      vim.keymap.set("x", "<leader>x", require('configs.functions').cycleCheckboxRange,
        { buffer = args.buf, desc = "Cycle checkbox state of the selected tasks" })
    end
  end
})



-- =============================================================================
--  Bigger headings: kitty (OSC 66) and WezTerm (DECDHL)
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

Headings = (function()
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
end)()

-- =============================================================================
--  The view: markdown drawn in place
-- =============================================================================
--  Renders markdown in place, the way render-markdown.nvim does: the text is
--  never changed, extmarks draw over it (the same mechanism as the git diff
--  toggle in configs/functions.lua). Treesitter says what each piece is, so a
--  '-' inside a code block is never mistaken for a bullet.
--
--    # Heading         icon over the #s, coloured band across the line
--    - item            bullet per nesting level (• ◦ ▪ ▫, vim.g.pure_md_bullets)
--    - [ ] / - [x]     checkbox icons; done items are dimmed
--    > quote           bar instead of '>'
--    ---               full-width line
--    | tables |        box-drawing borders
--    ```lang           shaded block with the language as a label
--    `code`            shaded background
--    ---               the frontmatter (Obsidian's properties) is hidden
--    key: value
--    ---
--    [^1]: note        footnote definitions are hidden
--    text[^1]          footnote references show as a superscript: text¹
--    [[path/note|Text]]  wikilinks show only their text: Text
--    [[note#Section]]    ... or the note (and section): note > Section
--    ![[image.png]]      embeds get an icon: image or file
--    ```todoist          the query is hidden; pure/todoist.lua draws the tasks
--
--  Everything is drawn with 'overlay' virtual text of the same width as what
--  it covers, so columns never shift and the cursor lands where the real
--  characters are. The one exception is the bullet of a task item, which is
--  concealed so the checkbox sits where the bullet was.
--
--  The line under the cursor shows the raw markdown in insert and visual mode,
--  to edit it; in normal mode it stays rendered, like concealcursor=nc.
--  Hidden lines (frontmatter, footnotes, todoist queries) come back while the
--  cursor is on them: gg shows the frontmatter, and moving onto a footnote
--  shows it. A wikilink shows raw while the cursor is inside it, as in
--  Obsidian's live preview, so it can be edited and followed (<CR>).
--
--    <leader>om  toggle rendering

View = (function()
local M = {}

local ns = vim.api.nvim_create_namespace('pure_mdview')
local enabled = true

local heading_icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' }
-- Smaller glyphs than the old ● ○ ◆ ◇, which looked heavy next to the text
-- (asked for in the vault's Improvment.md). vim.g.pure_md_bullets overrides
-- them, one per nesting level, repeating after the last.
local bullets = vim.g.pure_md_bullets or { '•', '◦', '▪', '▫' }
local checkbox = { unchecked = '󰄱', checked = '󰄲' }
-- Obsidian's extra states. Markdown does not know them ('- [~] x' is a plain
-- item whose text starts with '[~]'), so render.bullet finds them by text.
-- Box-shaped icons, like the two checkboxes, written as code points: pasted
-- private-use glyphs have been lost in copying before, leaving empty icons.
local extra_states = {
  ['~'] = { '\u{F0856}', 'PureMdTaskProgress' },  -- md-checkbox_intermediate: in progress
  ['!'] = { '\u{F0CE4}', 'PureMdTaskImportant' }, -- md-alert_box_outline: important
  ['>'] = { '\u{F0736}', 'PureMdTaskDeferred' },  -- md-arrow_right_bold_box_outline: deferred
  ['-'] = { '\u{F06F2}', 'PureMdTaskCancelled' }, -- md-minus_box_outline: cancelled
}

-- -----------------------------------------------------------------------------
--  Colours
-- -----------------------------------------------------------------------------
--  Themes rarely know these groups, so each one links to something every
--  theme has. The heading bands are computed: the heading colour mixed into
--  the CursorLine background, so they follow the theme instead of being fixed
--  colours that clash with it.

local function hexToRgb(n) return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256 end

--- `fg` mixed into `bg` by `amount` (0..1), both as 0xRRGGBB integers.
local function blend(fg, bg, amount)
  local fr, fg_, fb = hexToRgb(fg)
  local br, bg_, bb = hexToRgb(bg)
  local function mix(a, b) return math.floor(a * amount + b * (1 - amount) + 0.5) end
  return mix(fr, br) * 65536 + mix(fg_, bg_) * 256 + mix(fb, bb)
end

local function resolved(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function setHighlights()
  local set = function(name, val) vim.api.nvim_set_hl(0, name, vim.tbl_extend('force', val, { default = true })) end

  -- A transparent theme has no Normal background to shade against, so the
  -- base is CursorLine's (it always has one to be visible), else near black.
  local dark = vim.o.background == 'dark'
  local base = resolved('CursorLine').bg or resolved('Normal').bg or (dark and 0x101010 or 0xf0f0f0)

  for level = 1, 6 do
    set('PureMdH' .. level, { link = '@markup.heading.' .. level .. '.markdown' })
    local fg = resolved('PureMdH' .. level).fg or resolved('Title').fg
    -- Not `default`: recomputed on every call so it follows the heading colour
    -- that render-md.lua assigns per level.
    vim.api.nvim_set_hl(0, 'PureMdH' .. level .. 'Bg', { bg = fg and blend(fg, base, 0.2) or base })
  end

  set('PureMdCode', { bg = base })
  set('PureMdCodeLabel', { link = 'Comment' })
  set('PureMdInlineCode', { bg = base })
  set('PureMdBullet', { link = 'Special' })
  set('PureMdQuote', { link = 'Comment' })
  set('PureMdRule', { link = 'Comment' })
  set('PureMdTable', { link = 'Comment' })
  set('PureMdCheckedText', { link = 'Comment' })
  set('PureMdFootnote', { link = 'Special' })
  set('PureMdLink', { link = '@markup.link.label' })

  -- Checkbox icons: the colours of pure/notecolors.lua, which follow the
  -- colorscheme (fixed values only in Ethereal). Not `default` and re-applied
  -- on ColorScheme, as the groups below link to the ones it defines.
  require('pure.notecolors').apply()
  for _, state in ipairs(require('pure.notecolors').task_states) do
    vim.api.nvim_set_hl(0, 'PureMdTask' .. state, { link = 'PureNoteTask' .. state })
  end
end

-- -----------------------------------------------------------------------------
--  Queries
-- -----------------------------------------------------------------------------
local block_query = vim.treesitter.query.parse('markdown', [[
  (atx_heading) @heading
  (fenced_code_block) @code
  [(list_marker_minus) (list_marker_plus) (list_marker_star)] @bullet
  (task_list_marker_unchecked) @unchecked
  (task_list_marker_checked) @checked
  (block_quote) @quote
  (thematic_break) @rule
  (pipe_table) @table
]])

local inline_query = vim.treesitter.query.parse('markdown_inline', [[
  (code_span) @code_span
]])

-- -----------------------------------------------------------------------------
--  Renderers, one per capture
-- -----------------------------------------------------------------------------
--  Each gets the buffer, the node and a `mark(row, col, opts)` helper that
--  skips the raw (cursor) line.

local function lineText(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
end

--- Last row a block node really covers. Blocks end at column 0 of the line
--- after them, which is not part of the block.
local function lastRow(node)
  local _, _, er, ec = node:range()
  return ec == 0 and er - 1 or er
end

local render = {}

function render.heading(buf, node, mark)
  local row = node:start()
  local marker = node:child(0)
  local level = tonumber(marker:type():match('atx_h(%d)_marker'))
  if not level then return end

  -- The levels the terminal can draw bigger (kitty, WezTerm; pure/mdheadings.lua) are not drawn here.
  if Headings.handles(level) then return end

  -- The #s plus the space after them; the icon is right-aligned in that width
  -- so the heading text does not move.
  local _, sc, _, ec = marker:range()
  local width = ec - sc + 1
  local icon = heading_icons[level]
  local pad = math.max(width - vim.fn.strdisplaywidth(icon), 0)
  mark(row, sc, {
    virt_text = { { string.rep(' ', pad) .. icon, 'PureMdH' .. level } },
    virt_text_pos = 'overlay',
  })
  mark(row, 0, { line_hl_group = 'PureMdH' .. level .. 'Bg' })
end

function render.code(buf, node, mark)
  local first, last = node:start(), lastRow(node)
  -- A calendar grid (pure/calendar.lua) is a code block only to keep it
  -- monospaced in Obsidian: no shading, no label.
  local ok, calendar = pcall(require, 'pure.calendar')
  if ok and calendar.isGrid(buf, first) then return end
  for row = first, last do
    mark(row, 0, { line_hl_group = 'PureMdCode' })
  end

  -- Fence lines: cover ```lang with the language as a label.
  local lang = ''
  for child in node:iter_children() do
    if child:type() == 'info_string' then
      lang = vim.treesitter.get_node_text(child, buf):match('^%S+') or ''
    end
  end
  for _, row in ipairs({ first, last }) do
    local text = lineText(buf, row)
    local indent = #text:match('^%s*')
    local label = row == first and lang ~= '' and (' ' .. lang) or ''
    local cover = vim.fn.strdisplaywidth(text) - indent
    mark(row, indent, {
      virt_text = { { label .. string.rep(' ', math.max(cover - vim.fn.strdisplaywidth(label), 0)), 'PureMdCodeLabel' } },
      virt_text_pos = 'overlay',
    })
  end
end

--- The list marker's range without the spaces the parser sometimes puts in
--- it: for a nested item under a task ("    - [ ] sub") the marker node
--- was "  - " from column 2, so concealing it hid half the indentation and
--- the subtask showed level with its parent (Improvment.md).
local function markerRange(buf, node)
  local row, sc, _, ec = node:range()
  local lead = #(lineText(buf, row):sub(sc + 1, ec):match('^%s*'))
  return row, sc + lead, ec
end

--- Bullets change with depth; a task item's bullet is hidden instead, since
--- the checkbox takes its place.
function render.bullet(buf, node, mark)
  local item = node:parent()
  for child in item:iter_children() do
    if child:type():match('^task_list_marker') then
      local row, sc, ec = markerRange(buf, node)
      mark(row, sc, { end_col = ec, conceal = '' })
      return
    end
  end

  -- '- [~] text' and the like: hide the bullet, draw the state's icon over
  -- the '[' and conceal the rest of the box, as for real task items.
  local row, sc, ec = markerRange(buf, node)
  local box_col, state = lineText(buf, row):match('()%[([^%]])%]', ec + 1)
  if box_col == ec + 1 and extra_states[state] then
    -- The whole '[~]' is concealed *into* the icon. Treesitter reads '[~]' as
    -- a shortcut link and conceals its brackets itself; an overlay plus a
    -- partial conceal fought with that and swallowed the space after it.
    local icon, hl = unpack(extra_states[state])
    mark(row, sc, { end_col = ec, conceal = '' })
    mark(row, ec, { end_col = ec + 3, conceal = icon, hl_group = hl, priority = 300 })
    return
  end

  local depth = 0
  local parent = item:parent()
  while parent do
    if parent:type() == 'list' then depth = depth + 1 end
    parent = parent:parent()
  end
  local _, col = markerRange(buf, node)
  mark(row, col, {
    virt_text = { { bullets[(depth - 1) % #bullets + 1], 'PureMdBullet' } },
    virt_text_pos = 'overlay',
  })
end

--- The icon covers the '[' and the rest of the box (' ]' / 'x]') is concealed,
--- so the icon sits where the concealed bullet was, level with the bullets of
--- ordinary items. Padding the icon to the box's width instead left a gap.
local function task(buf, node, mark, state)
  local row, sc, _, ec = node:range()
  mark(row, sc, {
    virt_text = { { checkbox[state], state == 'checked' and 'PureMdTaskDone' or 'PureMdTaskTodo' } },
    virt_text_pos = 'overlay',
  })
  mark(row, sc + 1, { end_col = ec, conceal = '' })
  if state == 'checked' then
    -- Dim the item's text, from after the box to the end of the line.
    mark(row, ec, { end_col = #lineText(buf, row), hl_group = 'PureMdCheckedText' })
  end
end

function render.unchecked(buf, node, mark) task(buf, node, mark, 'unchecked') end
function render.checked(buf, node, mark) task(buf, node, mark, 'checked') end

--- Every '>' at the start of the quote's lines, nested ones included. The
--- markers after the first line are not separate nodes, so the lines are
--- scanned instead.
function render.quote(buf, node, mark)
  -- A nested quote is also captured on its own; the outermost one already
  -- scans its lines, so drawing again would stack a second set of bars.
  local parent = node:parent()
  while parent do
    if parent:type() == 'block_quote' then return end
    parent = parent:parent()
  end
  for row = node:start(), lastRow(node) do
    local text = lineText(buf, row)
    local col = 0
    while true do
      local s = text:find('^%s*>', col + 1)
      if not s then break end
      local gt = text:find('>', s, true)
      mark(row, gt - 1, { virt_text = { { '▋', 'PureMdQuote' } }, virt_text_pos = 'overlay' })
      col = gt
    end
  end
end

function render.rule(buf, node, mark)
  local row = node:start()
  local width = vim.api.nvim_win_get_width(0) - vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
  mark(row, 0, { virt_text = { { string.rep('─', width), 'PureMdRule' } }, virt_text_pos = 'overlay' })
end

--- Pipes become │; the delimiter row (|---|:-:|) becomes ├───┼───┤.
function render.table(buf, node, mark)
  for row = node:start(), lastRow(node) do
    local text = lineText(buf, row)
    local is_delimiter = text:match('^%s*|?[%s:%-|]+$') and text:find('-', 1, true)
    if is_delimiter then
      -- Built from the original (all ASCII) characters: substituting in place
      -- would shift byte offsets, since ─ ├ ┼ ┤ are three bytes each.
      local indent = #text:match('^%s*')
      local first = text:find('|', 1, true)
      local last_pipe = #text - (text:reverse():find('|', 1, true) or 0) + 1
      local out = {}
      for pos = indent + 1, #text do
        local ch = text:sub(pos, pos)
        if ch == '|' then
          table.insert(out, pos == first and '├' or pos == last_pipe and '┤' or '┼')
        elseif ch:match('%s') then
          table.insert(out, ch)
        else
          table.insert(out, '─')
        end
      end
      mark(row, indent, { virt_text = { { table.concat(out), 'PureMdTable' } }, virt_text_pos = 'overlay' })
    else
      local col = 0
      while true do
        local p = text:find('|', col + 1, true)
        if not p then break end
        -- A '\|' is a literal pipe inside a cell, not a border.
        if text:sub(p - 1, p - 1) ~= '\\' then
          mark(row, p - 1, { virt_text = { { '│', 'PureMdTable' } }, virt_text_pos = 'overlay' })
        end
        col = p
      end
      -- Checkboxes in cells. Markdown has no task items inside tables, so
      -- treesitter sees plain text; match the [ ] / [x] literally instead.
      for pos, mark_char in text:gmatch('()%[([ xX])%]') do
        local state = mark_char == ' ' and 'unchecked' or 'checked'
        local icon = checkbox[state]
        mark(row, pos - 1, {
          virt_text = { { icon .. string.rep(' ', 3 - vim.fn.strdisplaywidth(icon)),
            state == 'checked' and 'PureMdTaskDone' or 'PureMdTaskTodo' } },
          virt_text_pos = 'overlay',
        })
      end
    end
  end
end

function render.code_span(buf, node, mark)
  local row, sc, erow, ec = node:range()
  if row ~= erow then return end
  mark(row, sc, { end_col = ec, hl_group = 'PureMdInlineCode' })
end

-- -----------------------------------------------------------------------------
--  Hidden lines: frontmatter and footnotes
-- -----------------------------------------------------------------------------
--  Found by text rather than by treesitter: the markdown parser does not know
--  footnotes, and Obsidian's rule for the frontmatter is simply "the file
--  starts with a --- line".

local superscript = { ['0'] = '⁰', ['1'] = '¹', ['2'] = '²', ['3'] = '³', ['4'] = '⁴',
  ['5'] = '⁵', ['6'] = '⁶', ['7'] = '⁷', ['8'] = '⁸', ['9'] = '⁹' }

--- True when (row, col) is inside a code block or `code`, where [^1] and
--- --- are just text.
local function inCode(buf, row, col)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col }, ignore_injections = false })
  while ok and node do
    local t = node:type()
    if t == 'fenced_code_block' or t == 'indented_code_block' or t == 'code_span' then return true end
    node = node:parent()
  end
  return false
end

--- Rows (0-based, inclusive) of the frontmatter, or nil.
local function frontmatter(buf)
  if lineText(buf, 0) ~= '---' then return nil end
  local lines = vim.api.nvim_buf_get_lines(buf, 1, 200, false)
  for i, l in ipairs(lines) do
    if l == '---' or l == '...' then return { 0, i } end
  end
end

--- { first, last } row ranges of footnote definitions between top and bottom:
--- the "[^id]: text" line plus the indented lines that continue it.
local function footnotes(buf, top, bottom)
  local ranges = {}
  local lines = vim.api.nvim_buf_get_lines(buf, top, bottom + 1, false)
  local i = 1
  while i <= #lines do
    local row = top + i - 1
    if lines[i]:match('^ ? ? ?%[%^[^%]]+%]:') and not inCode(buf, row, #lines[i]:match('^%s*')) then
      local last = i
      while lines[last + 1] and lines[last + 1]:match('^\t') or (lines[last + 1] or ''):match('^    %S') do
        last = last + 1
      end
      table.insert(ranges, { row, top + last - 1 })
      i = last + 1
    else
      i = i + 1
    end
  end
  return ranges
end

--- Hide the frontmatter and footnote definitions, except the one the cursor
--- is in, and draw footnote references as superscripts.
--- Returns the hidden-able ranges, so cursor moves can tell when to redraw.
local function hideLines(buf, top, bottom, mark, place)
  local cursor = vim.fn.line('.') - 1
  local ranges = footnotes(buf, top, bottom)
  local fm = frontmatter(buf)
  if fm then table.insert(ranges, 1, fm) end
  for _, name in ipairs({ 'pure.todoist', 'pure.calendar', 'pure.llm' }) do
    local ok, mod = pcall(require, name)
    if ok and mod.hiddenBlocks then vim.list_extend(ranges, mod.hiddenBlocks(buf)) end
  end

  for _, r in ipairs(ranges) do
    if cursor < r[1] or cursor > r[2] then
      for row = r[1], r[2] do
        place(row, 0, { conceal_lines = '' })
      end
    end
  end

  local lines = vim.api.nvim_buf_get_lines(buf, top, bottom + 1, false)
  for i, text in ipairs(lines) do
    local row = top + i - 1
    for start, id, stop in text:gmatch('()%[%^([^%]]+)%]()') do
      -- Not the label that opens a definition line, and not inside code.
      local is_definition = text:sub(stop, stop) == ':' and not text:sub(1, start - 1):match('%S')
      if not is_definition and not inCode(buf, row, start - 1) then
        local label = id:match('^%d+$') and id:gsub('%d', superscript) or ('^' .. id)
        mark(row, start - 1, {
          end_col = stop - 1,
          conceal = '',
          virt_text = { { label, 'PureMdFootnote' } },
          virt_text_pos = 'inline',
        })
      end
    end
  end
  return ranges
end

local embed_icons = { image = '\u{F02E9}', file = '\u{F0219}' } -- md-image, md-file_document
local image_ext = { png = true, jpg = true, jpeg = true, gif = true, svg = true, webp = true, bmp = true }

--- What Obsidian shows for the inside of a [[wikilink]]: the alias after
--- '|' if there is one, else the target, with '#' sections as ' > '.
local function wikilinkText(inner)
  local alias = inner:match('|(.*)$')
  if alias and alias ~= '' then return alias end
  local target = inner:gsub('|.*$', '')
  local note, rest = target:match('^([^#]*)#(.*)$')
  if not note then return target end
  -- [[#Section]] links inside the same note show just the section.
  local parts = vim.tbl_filter(function(p) return p ~= '' end, vim.split(rest, '#', { plain = true }))
  local shown = table.concat(parts, ' > ')
  return note ~= '' and (note .. ' > ' .. shown) or shown
end

--- The [[wikilink]] (with its '!') under byte column `col` of `text`, as
--- "start:stop" (1-based, stop exclusive), or ''.
local function linkAt(text, col)
  for start, stop in text:gmatch('()%[%[[^%[%]]-%]%]()') do
    if text:sub(start - 1, start - 1) == '!' then start = start - 1 end
    if col + 1 >= start and col + 1 < stop then return start .. ':' .. stop end
  end
  return ''
end

--- The link under the cursor, as a key that changes when the cursor enters
--- or leaves one.
local function cursorLink()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local key = linkAt(vim.api.nvim_get_current_line(), col)
  return key ~= '' and (row .. ':' .. key) or ''
end

--- [[target|alias]] drawn as its text. Obsidian's own syntax, which the
--- markdown parser does not know (it already hides the URL of [text](url)).
--- The link under the cursor is left raw.
local function wikilinks(buf, top, bottom, mark)
  local lines = vim.api.nvim_buf_get_lines(buf, top, bottom + 1, false)
  local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  for i, text in ipairs(lines) do
    local row = top + i - 1
    local raw = row == cursor_row - 1 and linkAt(text, cursor_col) or ''
    for start, inner, stop in text:gmatch('()%[%[([^%[%]]-)%]%]()') do
      local key = (text:sub(start - 1, start - 1) == '!' and start - 1 or start) .. ':' .. stop
      if inner ~= '' and key ~= raw and not inCode(buf, row, start - 1) then
        local shown = wikilinkText(inner)
        -- ![[...]] embeds a note or a file: the '!' becomes an icon.
        if text:sub(start - 1, start - 1) == '!' then
          start = start - 1
          local is_image = inner:gsub('|.*$', ''):lower():match('%.(%a+)$')
          is_image = is_image and image_ext[is_image]
          shown = (is_image and embed_icons.image or embed_icons.file) .. ' ' .. shown
        end
        mark(row, start - 1, {
          end_col = stop - 1,
          conceal = '',
          virt_text = { { shown, 'PureMdLink' } },
          virt_text_pos = 'inline',
        })
      end
    end
  end
end

--- The range of `ranges` holding row `row`, as "first:last", or ''.
local function rangeAt(ranges, row)
  for _, r in ipairs(ranges or {}) do
    if row >= r[1] and row <= r[2] then return r[1] .. ':' .. r[2] end
  end
  return ''
end

-- -----------------------------------------------------------------------------
--  Code fences
-- -----------------------------------------------------------------------------
--  Neovim's own markdown highlights hide the whole ```lang line
--  (conceal_lines), which also hid the language label render.code draws
--  there. Load the same query without that directive; the backticks and
--  the language name are still concealed, the line itself stays.
do
  local parts = {}
  for _, file in ipairs(vim.treesitter.query.get_files('markdown', 'highlights')) do
    local text = table.concat(vim.fn.readfile(file), '\n')
    table.insert(parts, (text:gsub('%(#set! conceal_lines ""%)', '')))
  end
  pcall(vim.treesitter.query.set, 'markdown', 'highlights', table.concat(parts, '\n'))
end

-- -----------------------------------------------------------------------------
--  Driver
-- -----------------------------------------------------------------------------

--- True when `buf` should show rendered markdown.
--- Scratch buffers (buftype set) are skipped unless they opt in with
--- vim.b.pure_mdview = true, as the Todoist task list does.
local function active(buf)
  return enabled and vim.bo[buf].filetype == 'markdown'
    and (vim.bo[buf].buftype == '' or vim.b[buf].pure_mdview == true)
end

-- Marks drawn per buffer: extmark id -> the key of what it draws.
local drawn = {}
-- What the last refresh saw per buffer, to skip one that would change nothing.
local last_state = {}

--- Make the buffer's marks `want` ({ row, col, opts, key }), touching only
--- what differs from what is drawn. Clearing and redrawing every mark made
--- Neovim redraw the whole window on every key typed, several times: the
--- render flickered while typing, most of all on Windows terminals.
---
--- With `rows` ({ first, last }), only the marks on those rows are looked at;
--- the others stay as they are.
local function reconcile(buf, want, rows)
  local have = drawn[buf] or {}
  local keep = {}
  local from, to = 0, -1
  if rows then from, to = { rows[1], 0 }, { rows[2], -1 } end
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, from, to, { details = true })) do
    local id = m[1]
    -- Keyed by where the mark is now: edits move marks with the text.
    local key = have[id] and (m[2] .. ':' .. m[3] .. ':' .. have[id])
    -- Replacing a whole line (cycling a checkbox) collapses the marks on it
    -- onto the line below, where a conceal of end_col 2 became one of width
    -- 0 and still passed for the real one: the bullet below stayed visible.
    -- A mark whose end is no longer the one it was drawn with is stale.
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
  -- A partial pass keeps what is drawn elsewhere.
  local now = {}
  if rows then
    now = have
    for _, id in pairs(keep) do now[id] = nil end
  end
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

-- -----------------------------------------------------------------------------
--  What changed
-- -----------------------------------------------------------------------------
--  Typing changes one line. Redrawing the whole screen for it (even when
--  reconcile() ends up touching nothing) cost a parse, a scan of every
--  block and a pass over each visible line per key, and the screen showed
--  it. So each buffer's edits are followed as they happen: the rows edited
--  (nvim_buf_attach) and the rows where the syntax tree changed (the
--  parser's on_changedtree). When both stay on one line, only that line
--  is drawn again; while typing on the cursor line in insert mode, which is
--  shown raw anyway, nothing is.

-- buf -> { first, last (0-based rows), shifted (lines added or removed),
--          tree_first, tree_last (rows where the syntax tree changed) }
local dirty = {}
local attached = {}  -- buf -> the parser the tree callback is on

local function note(buf, first, last)
  local d = dirty[buf]
  if not d then
    dirty[buf] = { first = first, last = last }
  else
    d.first, d.last = math.min(d.first, first), math.max(d.last, last)
  end
  return dirty[buf]
end

local function follow(buf, parser)
  if attached[buf] == parser then return end
  if attached[buf] == nil then
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, b, _, first, last_old, last_new)
        local d = note(b, first, math.max(first, math.max(last_old, last_new) - 1))
        if last_old ~= last_new then d.shifted = true end
      end,
      on_reload = function(_, b) note(b, 0, 0).shifted = true end,
      on_detach = function(_, b) attached[b], dirty[b] = nil, nil end,
    })
  end
  attached[buf] = parser
  parser:register_cbs({
    on_changedtree = function(ranges)
      if attached[buf] ~= parser then return end
      local d = dirty[buf] or note(buf, math.huge, -1)
      for _, r in ipairs(ranges) do
        local sr, er = r[1], (#r == 6 and r[4] or r[3])
        d.tree_first = math.min(d.tree_first or sr, sr)
        d.tree_last = math.max(d.tree_last or er, er)
      end
    end,
  }, true)
end

-- A line that can change how other lines read: a code fence, a thematic
-- break or frontmatter fence, an HTML comment (the markers of the Todoist,
-- calendar and Claude blocks), a footnote definition.
local function structural(text)
  return text:match('^%s*```') or text:match('^%s*~~~') or text:match('^%-%-%-')
    or text:find('<!--', 1, true) or text:match('^ ? ? ?%[%^')
end

--- The one row the last edits touched, when they can be drawn alone; nil
--- when the screen has to be drawn again.
local function editedRow(buf, prev, now)
  local d = dirty[buf]
  if not (d and prev and now) or d.shifted or d.first ~= d.last then return nil end
  -- Anything but the text and the cursor column changed: view, mode, size.
  if prev.row ~= now.row or prev.view ~= now.view then return nil end
  if d.tree_first and (d.tree_first < d.first or d.tree_last > d.last) then return nil end
  if structural(lineText(buf, d.first)) then return nil end
  return d.first
end

--- Redraw the visible part of the current window's buffer. Skipped when
--- nothing it depends on changed since the last time (text, cursor, view,
--- mode): typing one key fires three or four events. `force` redraws anyway.
function M.refresh(force)
  local buf = vim.api.nvim_get_current_buf()
  if not active(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    drawn[buf], last_state[buf], dirty[buf] = nil, nil, nil
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local mode = vim.fn.mode()
  local view = table.concat({ vim.fn.line('w0'), vim.fn.line('w$'), vim.api.nvim_win_get_width(0), mode }, ':')
  local state = { key = table.concat({ vim.b[buf].changedtick, cursor[1], cursor[2], view }, ':'),
    row = cursor[1], view = view }
  local prev = last_state[buf]
  if not force and prev and prev.key == state.key then return end
  last_state[buf] = state

  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or not parser then return end
  follow(buf, parser)

  -- Only the rows on screen, plus a margin so short scrolls look finished.
  local top = math.max(vim.fn.line('w0') - 1 - 20, 0)
  local bottom = vim.fn.line('w$') + 20
  parser:parse({ top, bottom })

  -- The cursor line is left raw while editing it.
  local raw_row = (mode:match('^[iRvV\22]')) and (cursor[1] - 1) or -1

  -- One line edited: draw that line only (nothing, if it is the raw one).
  local row = not force and editedRow(buf, prev, state)
  dirty[buf] = nil
  local partial = row ~= nil and row ~= false
  if partial then
    if row == raw_row then return end
    top, bottom = row, row
  end

  local want = {}
  -- Every mark goes through here; reconcile() below applies them.
  local function place(row_, col, opts)
    if partial and (row_ < top or row_ > bottom) then return end
    opts.priority = opts.priority or 200
    table.insert(want, { row = row_, col = col, opts = opts, key = vim.inspect(opts, { newline = '', indent = '' }) })
  end
  local function mark(row, col, opts)
    if row == raw_row or row < top or row > bottom then return end
    place(row, col, opts)
  end

  parser:for_each_tree(function(tree, ltree)
    local lang = ltree:lang()
    local query = lang == 'markdown' and block_query or lang == 'markdown_inline' and inline_query
    if not query then return end
    for id, node in query:iter_captures(tree:root(), buf, top, bottom + 1) do
      local fn = render[query.captures[id]]
      if fn then fn(buf, node, mark) end
    end
  end)

  local ranges = hideLines(buf, top, bottom, mark, place)
  wikilinks(buf, top, bottom, mark)
  reconcile(buf, want, partial and { top, bottom } or nil)
  if partial then return end
  vim.b[buf].pure_md_hidden = ranges
  vim.b[buf].pure_md_revealed = rangeAt(ranges, vim.fn.line('.') - 1)
  vim.b[buf].pure_md_link = cursorLink()
end

function M.toggle()
  enabled = not enabled
  Headings.set_enabled(enabled)
  M.refresh()
  vim.notify('Markdown rendering ' .. (enabled and 'on' or 'off'))
end

local group = vim.api.nvim_create_augroup('PureMdview', { clear = true })

vim.api.nvim_create_autocmd(
  { 'BufWinEnter', 'WinScrolled', 'TextChanged', 'TextChangedI', 'CursorMoved', 'CursorMovedI', 'ModeChanged', 'WinResized' }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype ~= 'markdown' then return end
      -- In normal mode the render does not depend on the cursor, so plain
      -- movement needs no redraw -- unless it enters or leaves a hidden block
      -- (frontmatter, footnote). In visual mode the raw line follows it.
      if args.event == 'CursorMoved' and vim.fn.mode() == 'n'
        and rangeAt(vim.b[args.buf].pure_md_hidden, vim.fn.line('.') - 1) == vim.b[args.buf].pure_md_revealed
        and cursorLink() == vim.b[args.buf].pure_md_link then
        return
      end
      -- A note opens on its first line, which would reveal the frontmatter:
      -- start just below it instead, as Obsidian does.
      if args.event == 'BufWinEnter' and vim.fn.line('.') == 1 and active(args.buf) then
        local fm = frontmatter(args.buf)
        if fm then pcall(vim.api.nvim_win_set_cursor, 0, { math.min(fm[2] + 2, vim.fn.line('$')), 0 }) end
      end
      M.refresh()
    end,
  })

-- Scheduled so it runs after render-md.lua's FileType handler, which assigns
-- the per-level heading colours the bands are computed from.
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'markdown',
  callback = function() vim.schedule(function() setHighlights(); M.refresh(true) end) end,
})
vim.api.nvim_create_autocmd('ColorScheme', {
  group = group,
  callback = function()
    setHighlights()
    vim.schedule(function() M.refresh(true) end)
  end,
})
setHighlights()
M.setHighlights = setHighlights

return M
end)()

-- Bigger headings where the terminal can do it; a no-op elsewhere.
Headings.setup()

M.refresh = View.refresh
M.toggle = View.toggle
M.setHighlights = View.setHighlights
M.headings = Headings

return M
