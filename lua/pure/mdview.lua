-- =============================================================================
--  Markdown view
-- =============================================================================
--  Renders markdown in place, the way render-markdown.nvim does: the text is
--  never changed, extmarks draw over it (the same mechanism as the git diff
--  toggle in configs/functions.lua). Treesitter says what each piece is, so a
--  '-' inside a code block is never mistaken for a bullet.
--
--    # Heading         icon over the #s, coloured band across the line
--    - item            bullet per nesting level (● ○ ◆ ◇)
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
-- =============================================================================

local M = {}

local ns = vim.api.nvim_create_namespace('pure_mdview')
local enabled = true

local heading_icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' }
local bullets = { '●', '○', '◆', '◇' }
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

  -- Checkbox icons: fixed colours, the same in every colorscheme, so a state
  -- always reads the same at a glance. Not `default` and re-applied on
  -- ColorScheme: a theme switch must not restyle them.
  local task_colours = {
    PureMdTaskTodo      = '#8b949e', -- [ ] grey
    PureMdTaskDone      = '#3fb950', -- [x] green
    PureMdTaskProgress  = '#58a6ff', -- [~] blue
    PureMdTaskImportant = '#f85149', -- [!] red
    PureMdTaskDeferred  = '#a371f7', -- [>] purple
    PureMdTaskCancelled = '#6e7681', -- [-] dark grey
  }
  for name, fg in pairs(task_colours) do
    vim.api.nvim_set_hl(0, name, { fg = fg })
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

--- Bullets change with depth; a task item's bullet is hidden instead, since
--- the checkbox takes its place.
function render.bullet(buf, node, mark)
  local item = node:parent()
  for child in item:iter_children() do
    if child:type():match('^task_list_marker') then
      local row, sc, _, ec = node:range()
      mark(row, sc, { end_col = ec, conceal = '' })
      return
    end
  end

  -- '- [~] text' and the like: hide the bullet, draw the state's icon over
  -- the '[' and conceal the rest of the box, as for real task items.
  local row, sc, _, ec = node:range()
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
  local row, col = node:start()
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
  for _, name in ipairs({ 'pure.todoist', 'pure.calendar' }) do
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
local function reconcile(buf, want)
  local have = drawn[buf] or {}
  local keep = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})) do
    local id = m[1]
    -- Keyed by where the mark is now: edits move marks with the text.
    local key = have[id] and (m[2] .. ':' .. m[3] .. ':' .. have[id])
    if key and not keep[key] then
      keep[key] = id
    else
      vim.api.nvim_buf_del_extmark(buf, ns, id)
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

--- Redraw the visible part of the current window's buffer. Skipped when
--- nothing it depends on changed since the last time (text, cursor, view,
--- mode): typing one key fires three or four events. `force` redraws anyway.
function M.refresh(force)
  local buf = vim.api.nvim_get_current_buf()
  if not active(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    drawn[buf], last_state[buf] = nil, nil
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local state = table.concat({ vim.b[buf].changedtick, cursor[1], cursor[2], vim.fn.line('w0'),
    vim.fn.line('w$'), vim.api.nvim_win_get_width(0), vim.fn.mode() }, ':')
  if not force and last_state[buf] == state then return end
  last_state[buf] = state

  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or not parser then return end

  -- Only the rows on screen, plus a margin so short scrolls look finished.
  local top = math.max(vim.fn.line('w0') - 1 - 20, 0)
  local bottom = vim.fn.line('w$') + 20
  parser:parse({ top, bottom })

  -- The cursor line is left raw while editing it.
  local mode = vim.fn.mode()
  local raw_row = (mode:match('^[iRvV\22]')) and (vim.fn.line('.') - 1) or -1

  local want = {}
  -- Every mark goes through here; reconcile() below applies them.
  local function place(row, col, opts)
    opts.priority = opts.priority or 200
    table.insert(want, { row = row, col = col, opts = opts, key = vim.inspect(opts, { newline = '', indent = '' }) })
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
  reconcile(buf, want)
  vim.b[buf].pure_md_hidden = ranges
  vim.b[buf].pure_md_revealed = rangeAt(ranges, vim.fn.line('.') - 1)
  vim.b[buf].pure_md_link = cursorLink()
end

function M.toggle()
  enabled = not enabled
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
vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = setHighlights })
setHighlights()

return M
