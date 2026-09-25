-- =============================================================================
--  Indent scope
-- =============================================================================
--  Replaces mini.indentscope. Draws a vertical line beside the indented block
--  the cursor is in, and adds a text object and motions for that block:
--
--    ii / ai   inner scope (the block) / outer scope (plus the lines around it)
--    [i / ]i   jump to the line above / below the block
--
--  A "scope" is the run of lines around the cursor whose indent is at least
--  the reference indent. Blank lines never end it, so a block with an empty
--  line in the middle stays one scope. The first line above and below with a
--  smaller indent are its borders ("if x then" / "end").
--
--  Colour: PureIndentscopeSymbol (links to Delimiter unless a theme sets it).
--  Disable in a buffer with  vim.b.pure_indentscope_disable = true
-- =============================================================================

local M = {}

local symbol = '╎'
local delay = 100       -- ms after the last cursor move before redrawing
local max_lines = 10000 -- stop scanning this far from the cursor

local ns = vim.api.nvim_create_namespace('pure_indentscope')
local timer = assert(vim.uv.new_timer())
local drawn_buf = nil   -- the buffer holding the current marks, to clear it

vim.api.nvim_set_hl(0, 'PureIndentscopeSymbol', { link = 'Delimiter', default = true })

local function isBlank(lnum)
  return vim.fn.getline(lnum):match('^%s*$') ~= nil
end

--- Indent the scope is measured against.
---
--- On a blank line the line itself says nothing, so the deeper of its two
--- neighbours is used: an empty line inside a block belongs to that block.
---
--- On other lines the cursor column caps it (mini's indent_at_cursor): with
--- the cursor inside the leading whitespace, moving left selects wider and
--- wider scopes. Not on blank lines, where the cursor always sits in column 0
--- and the cap would always pick the outermost scope.
local function referenceIndent(lnum)
  if isBlank(lnum) then
    local prev = vim.fn.prevnonblank(lnum)
    local next = vim.fn.nextnonblank(lnum)
    return math.max(prev > 0 and vim.fn.indent(prev) or 0, next > 0 and vim.fn.indent(next) or 0)
  end
  return math.min(vim.fn.indent(lnum), vim.fn.virtcol('.'))
end

--- Scope around `lnum`, or nil when the cursor is not inside an indented block.
--- @return { top: integer, bottom: integer, border_top: integer?, border_bottom: integer?, col: integer }?
function M.getScope(lnum)
  lnum = lnum or vim.fn.line('.')
  local ref = referenceIndent(lnum)
  -- Indent 0 means the whole file: nothing to draw and no borders to jump to.
  if ref <= 0 then return nil end

  local last = vim.fn.line('$')
  local function inside(l)
    return isBlank(l) or vim.fn.indent(l) >= ref
  end

  local top = lnum
  while top > 1 and lnum - top < max_lines and inside(top - 1) do
    top = top - 1
  end
  local bottom = lnum
  while bottom < last and bottom - lnum < max_lines and inside(bottom + 1) do
    bottom = bottom + 1
  end

  -- Blank lines at either edge sit between blocks, not inside this one.
  while top < bottom and isBlank(top) do top = top + 1 end
  while bottom > top and isBlank(bottom) do bottom = bottom - 1 end

  local border_top = top > 1 and top - 1 or nil
  local border_bottom = bottom < last and bottom + 1 or nil

  -- The line is drawn in the column where the borders start, i.e. inside the
  -- body's leading whitespace. Without borders (a block at the very top of the
  -- file) fall back to one step left of the body.
  local col
  if border_top or border_bottom then
    col = math.max(border_top and vim.fn.indent(border_top) or 0,
      border_bottom and vim.fn.indent(border_bottom) or 0)
  else
    col = math.max(ref - vim.fn.shiftwidth(), 0)
  end

  return { top = top, bottom = bottom, border_top = border_top, border_bottom = border_bottom, col = col }
end

-- -----------------------------------------------------------------------------
--  Drawing
-- -----------------------------------------------------------------------------
local function clear()
  if drawn_buf and vim.api.nvim_buf_is_valid(drawn_buf) then
    vim.api.nvim_buf_clear_namespace(drawn_buf, ns, 0, -1)
  end
  drawn_buf = nil
end

local function enabled(buf)
  -- buftype ~= '' skips terminals, help, oil, the dashboard, quickfix, ...
  return vim.bo[buf].buftype == ''
    and not vim.b[buf].pure_indentscope_disable
    and not vim.g.pure_indentscope_disable
end

local function draw()
  clear()
  local buf = vim.api.nvim_get_current_buf()
  if not enabled(buf) then return end

  local scope = M.getScope()
  if not scope then return end

  -- Only the visible part needs marks, so a long block costs no more than a
  -- screenful. Horizontal scroll moves the column the line has to be drawn at.
  local leftcol = vim.fn.winsaveview().leftcol
  local win_col = scope.col - leftcol
  if win_col < 0 then return end

  local first = math.max(scope.top, vim.fn.line('w0'))
  local last = math.min(scope.bottom, vim.fn.line('w$'))
  for lnum = first, last do
    -- Skip lines whose text starts at or before that column (a line inside a
    -- string, for instance); drawing there would cover real characters.
    if isBlank(lnum) or vim.fn.indent(lnum) > scope.col then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
        virt_text = { { symbol, 'PureIndentscopeSymbol' } },
        virt_text_win_col = win_col,
        hl_mode = 'combine',
        priority = 2,
      })
    end
  end
  drawn_buf = buf
end

--- Redraw after `delay` ms without movement, so holding j does not redraw on
--- every line.
local function schedule()
  timer:stop()
  timer:start(delay, 0, vim.schedule_wrap(draw))
end

vim.api.nvim_create_autocmd(
  { 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'WinScrolled', 'BufWinEnter' }, {
    group = vim.api.nvim_create_augroup('PureIndentscope', { clear = true }),
    callback = schedule,
  })

-- Leaving a window clears straight away, otherwise the line stays behind in
-- the window you just left.
vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
  group = 'PureIndentscope',
  callback = function()
    timer:stop()
    clear()
  end,
})

-- -----------------------------------------------------------------------------
--  Text objects and motions
-- -----------------------------------------------------------------------------

--- Select the scope linewise. `outer` includes the border lines.
---
--- Mapped through ':<C-u>' rather than <Cmd>: the ':' leaves visual mode (and
--- keeps a pending operator waiting), so the 'V' below becomes the selection
--- the operator acts on -- dii, yai and vii all work the same way.
function M.textobject(outer)
  local scope = M.getScope()
  if not scope then return end
  local top = outer and scope.border_top or scope.top
  local bottom = outer and scope.border_bottom or scope.bottom
  vim.cmd(('normal! %dGV%dG'):format(top, bottom))
end

--- Keys that jump to the line above (`up`) or below the scope.
---
--- Returned from an expr mapping as '{lnum}G', so the jump lands in the
--- jumplist like any G. With an operator pending, a leading 'V' makes it
--- linewise: d]i deletes whole lines down to the border.
local function jump(up)
  return function()
    local scope = M.getScope()
    if not scope then return '' end
    local target = up and (scope.border_top or scope.top) or (scope.border_bottom or scope.bottom)
    local linewise = vim.fn.mode(1):sub(1, 2) == 'no' and 'V' or ''
    return linewise .. target .. 'G'
  end
end

vim.keymap.set({ 'x', 'o' }, 'ii', ':<C-u>lua require("pure.indentscope").textobject(false)<CR>',
  { silent = true, desc = 'Inner indent scope' })
vim.keymap.set({ 'x', 'o' }, 'ai', ':<C-u>lua require("pure.indentscope").textobject(true)<CR>',
  { silent = true, desc = 'Outer indent scope' })
vim.keymap.set({ 'n', 'x', 'o' }, '[i', jump(true), { expr = true, desc = 'Indent scope top' })
vim.keymap.set({ 'n', 'x', 'o' }, ']i', jump(false), { expr = true, desc = 'Indent scope bottom' })

return M
