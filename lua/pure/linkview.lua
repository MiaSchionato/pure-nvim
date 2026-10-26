-- =============================================================================
--  Link view
-- =============================================================================
--  Look at a linked note without leaving the one you are writing:
--
--    hover        preview: a small read-only window next to the cursor, like
--                 the suggestion menu, with the note the link under the cursor
--                 points to (just the section for [[Note#Heading]], just the
--                 block for [[Note#^id]]), without its frontmatter. It shows
--                 when the cursor rests on a link and closes when it moves.
--    <leader>vp   the same on a key (toggles it).
--    <leader>vq   quick edit: the note itself (the real buffer, not a copy)
--                 in a floating window; it can be nested (a link inside a
--                 quick edit). :w saves. q or <Esc><Esc> in normal mode, or :q,
--                 closes ALL the quick edits and goes back to the window they
--                 started from (so does entering any normal window); a note
--                 with unsaved changes asks first. A note that was not open
--                 before is unloaded again.
--
--  Settings (vim.g.*, described in configs/configs.lua):
--    linkview_preview   'auto' (default: also after the cursor rests on a
--                       link), 'key' (only on the key) or 'off' (nothing)
--    linkview_delay     ms the cursor rests before 'auto' shows it (default 300)
--    linkview_size      { width = 64, rows = 12 } at most, for the preview
--    linkview_keys      { preview = '<leader>vp', edit = '<leader>vq' }
-- =============================================================================

local M = {}

local func = require('configs.functions')
local notes = require('pure.notes')

local DEFAULT_KEYS = { preview = '<leader>vp', edit = '<leader>vq' }

local DEFAULT_SIZE = { width = 64, rows = 12 }

local edits = {}    -- quick edit window -> { buf, seq }
local seq = 0       -- opening order of the quick edits
local closing = false
local origin = nil  -- the window the first quick edit was opened from
local buf_keys = {} -- buffer -> the keys mapped on it for the quick edits

local shown = { win = nil, from = nil } -- the preview window, and the buffer it was asked in

local function mode() return vim.g.linkview_preview or 'auto' end

-- -----------------------------------------------------------------------------
--  What to show
-- -----------------------------------------------------------------------------

--- The lines of the note: the buffer when it is loaded (what is not saved
--- yet shows), else the file.
local function linesOf(path)
  local nr = vim.fn.bufnr(path)
  if nr ~= -1 and vim.api.nvim_buf_is_loaded(nr) then
    return vim.api.nvim_buf_get_lines(nr, 0, -1, false)
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or {}
end

--- Without the frontmatter (---, ..., ---) at the top.
local function body(lines)
  if lines[1] ~= '---' then return lines end
  for i = 2, #lines do
    if lines[i] == '---' then return vim.list_slice(lines, i + 1) end
  end
  return lines
end

--- The part `sub` names: a heading and what is under it down to the next one
--- of the same or a higher level, or the paragraph that ends in ^block.
--- Nil when the note has no such part.
local function part(lines, sub)
  local block = sub:match('^%^(.+)$')
  if block then
    for i, l in ipairs(lines) do
      if l:match('%^' .. vim.pesc(block) .. '%s*$') then
        local first, last = i, i
        while first > 1 and lines[first - 1]:match('%S') do first = first - 1 end
        while last < #lines and lines[last + 1]:match('%S') do last = last + 1 end
        return vim.list_slice(lines, first, last)
      end
    end
    return nil
  end
  local want = notes.slug(sub:match('([^#]*)$'))
  local fence = false
  for i, l in ipairs(lines) do
    if l:match('^%s*```') then fence = not fence end
    local hashes, text = l:match('^(#+)%s+(.-)%s*#*%s*$')
    if not fence and text and notes.slug(text) == want then
      local last = #lines
      local in_fence = false
      for j = i + 1, #lines do
        if lines[j]:match('^%s*```') then in_fence = not in_fence end
        local h = lines[j]:match('^(#+)%s')
        if not in_fence and h and #h <= #hashes then
          last = j - 1
          break
        end
      end
      return vim.list_slice(lines, i, last)
    end
  end
  return nil
end

-- -----------------------------------------------------------------------------
--  Preview
-- -----------------------------------------------------------------------------

function M.closePreview()
  local win = shown.win
  shown.win, shown.from = nil, nil
  if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
end

--- Open the preview of the link under the cursor. `quiet`: say nothing when
--- there is nothing to show (the 'auto' mode asks on every rest).
function M.preview(quiet)
  local toggled = shown.win and vim.api.nvim_win_is_valid(shown.win)
  M.closePreview()
  if toggled and not quiet then return end

  local t = notes.target()
  if not t then
    if not quiet then vim.notify('No note link under the cursor', vim.log.levels.INFO) end
    return
  end
  if t.missing then
    if not quiet then vim.notify('No note called "' .. t.missing .. '" yet', vim.log.levels.INFO) end
    return
  end
  if not t.path:match('%.md$') then
    if not quiet then vim.notify(t.name .. ' is not a markdown note', vim.log.levels.INFO) end
    return
  end

  local lines = body(linesOf(t.path))
  if t.sub and t.sub ~= '' then
    local found = part(lines, t.sub)
    if not found then
      if not quiet then vim.notify('No "' .. t.sub .. '" in ' .. t.name, vim.log.levels.WARN) end
      return
    end
    lines = found
  end
  while lines[1] and not lines[1]:match('%S') do table.remove(lines, 1) end
  if #lines == 0 then lines = { '(empty note)' } end

  local from = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'

  -- Like the suggestion menu: small, next to the cursor, the menu's colours
  -- and border, and it never takes the focus.
  local size = vim.tbl_extend('force', DEFAULT_SIZE, vim.g.linkview_size or {})
  local longest = 0
  for _, l in ipairs(lines) do longest = math.max(longest, vim.fn.strdisplaywidth(l)) end
  local width = math.max(math.min(size.width, longest, vim.o.columns - 4), 20)
  local rows = 0
  for _, l in ipairs(lines) do rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width)) end
  -- Below the cursor line, or above it when there is more room there
  local line = vim.fn.winline() + vim.fn.win_screenpos(0)[1] - 1
  local below = vim.o.lines - vim.o.cmdheight - line - 2
  local above = line - 3
  local up = rows > below and above > below
  local height = math.max(math.min(rows, size.rows, up and above or below), 1)
  local col = math.min(0, vim.o.columns - 2 - (vim.fn.wincol() + vim.fn.win_screenpos(0)[2] - 1) - width)
  local border = (vim.o.pumborder ~= '' and vim.o.pumborder) or 'rounded'
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'cursor',
    anchor = up and 'SW' or 'NW',
    row = up and 0 or 1,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = border,
    title = ' ' .. t.name .. (t.sub and ('#' .. t.sub) or '') .. ' ',
    focusable = false,
    zindex = 60,
  })
  vim.wo[win].winhighlight = 'NormalFloat:Pmenu,FloatBorder:PmenuBorder,FloatTitle:Pmenu'
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 0
  shown.win, shown.from = win, from
end

-- -----------------------------------------------------------------------------
--  Quick edit
-- -----------------------------------------------------------------------------

--- Ready to let go of the buffer: when it has unsaved changes, ask. Yes saves,
--- No throws them away, Cancel keeps everything open (returns false).
local function settle(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then return true end
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t:r')
  local choice = vim.fn.confirm('Save changes to "' .. name .. '"?', '&Yes\n&No\n&Cancel', 1)
  if choice == 1 then
    vim.api.nvim_buf_call(buf, function() pcall(vim.cmd, 'silent update') end)
    return not vim.bo[buf].modified
  elseif choice == 2 then
    vim.api.nvim_buf_call(buf, function() pcall(vim.cmd, 'silent edit!') end)
    return true
  end
  return false
end

--- Close every quick edit window, the innermost first, and go back to the
--- window the first one was opened from. A modified note asks first; Cancel
--- stops and leaves the rest open.
function M.closeAll()
  if closing then return end
  closing = true
  local wins = vim.tbl_keys(edits)
  table.sort(wins, function(x, y) return edits[x].seq > edits[y].seq end)
  local done = true
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      if not settle(edits[win].buf) then
        done = false
        vim.api.nvim_set_current_win(win)
        break
      end
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  closing = false
  if done and origin and vim.api.nvim_win_is_valid(origin) then
    pcall(vim.api.nvim_set_current_win, origin)
  end
  if done then origin = nil end
end

--- The note under the cursor, in a floating window, as the real buffer.
function M.edit()
  M.closePreview()
  local t = notes.target()
  if not t then return vim.notify('No note link under the cursor', vim.log.levels.INFO) end
  if t.missing then
    return vim.notify('No note called "' .. t.missing .. '" yet: follow the link (K) to create it', vim.log.levels.INFO)
  end
  if not t.path:match('%.md$') then
    return vim.notify(t.name .. ' is not a markdown note', vim.log.levels.INFO)
  end

  if next(edits) == nil then origin = vim.api.nvim_get_current_win() end
  local nr = vim.fn.bufnr(t.path)
  local was_open = nr ~= -1 and vim.api.nvim_buf_is_loaded(nr)
  local buf = vim.fn.bufadd(t.path)
  vim.fn.bufload(buf)
  local win = func.createWindow(' ' .. t.name .. ' ', 0.8, { buf = buf })
  -- 'minimal' leaves the window options of the one it came from
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = 'nc'
  if t.sub and t.sub ~= '' then notes.jump(t.sub) end

  -- q and <Esc><Esc> close ALL the quick edits (they can be nested, and the
  -- same note can be in several of them), unless the buffer already has the
  -- key for something else. The mapping goes away with the last window.
  seq = seq + 1
  edits[win] = { buf = buf, seq = seq }
  local mapped = buf_keys[buf]
  if not mapped then
    mapped = {}
    for _, key in ipairs({ 'q', '<Esc><Esc>' }) do
      if vim.fn.maparg(key, 'n', false, true).buffer ~= 1 then
        vim.keymap.set('n', key, function()
          local cur = edits[vim.api.nvim_get_current_win()]
          if cur and cur.buf == buf then
            M.closeAll()
          else -- the note is also open in a normal window: the key keeps its own meaning
            vim.api.nvim_feedkeys(vim.keycode(key), 'n', false)
          end
        end, { buffer = buf, nowait = true, desc = 'Close the quick edits' })
        table.insert(mapped, key)
      end
    end
    buf_keys[buf] = mapped
  end

  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      edits[win] = nil
      local others = false
      for _, e in pairs(edits) do others = others or e.buf == buf end
      if not others then
        for _, key in ipairs(mapped) do pcall(vim.keymap.del, 'n', key, { buffer = buf }) end
        buf_keys[buf] = nil
      end
      -- Closed some other way (:q, :close): the rest goes with it
      if next(edits) and not closing then vim.schedule(M.closeAll) end
      -- Not open before: leave nothing behind (unless another window shows it)
      vim.schedule(function()
        if was_open or not vim.api.nvim_buf_is_valid(buf) or #vim.fn.win_findbuf(buf) > 0 then return end
        if vim.bo[buf].modified then return end -- unsaved: keep it
        pcall(vim.api.nvim_buf_delete, buf, {})
      end)
    end,
  })
end

-- -----------------------------------------------------------------------------
--  Triggers
-- -----------------------------------------------------------------------------

local keys = vim.tbl_extend('force', DEFAULT_KEYS, vim.g.linkview_keys or {})
if mode() ~= 'off' then
  vim.keymap.set('n', keys.preview, function() M.preview(false) end, { desc = 'Preview the linked note' })
  vim.keymap.set('n', keys.edit, M.edit, { desc = 'Quick edit the linked note' })
end

local group = vim.api.nvim_create_augroup('LinkView', { clear = true })

-- :q in a quick edit: ask about unsaved changes first (Cancel: Vim's own
-- "no write since last change" stops the :q when it is the only window)
vim.api.nvim_create_autocmd('QuitPre', {
  group = group,
  callback = function()
    local e = edits[vim.api.nvim_get_current_win()]
    if e and not closing then settle(e.buf) end
  end,
})

-- Back in a normal window: the quick edits are over
vim.api.nvim_create_autocmd('WinEnter', {
  group = group,
  callback = function()
    if closing or next(edits) == nil then return end
    local cur = vim.api.nvim_get_current_win()
    if edits[cur] or vim.api.nvim_win_get_config(cur).relative ~= '' then return end
    vim.schedule(M.closeAll)
  end,
})
local timer = vim.uv.new_timer()

vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufLeave' }, {
  group = group,
  callback = function(args)
    -- Not while the cursor is in the preview itself or in a float
    if vim.api.nvim_win_get_config(0).relative ~= '' then return end
    if shown.win and (args.buf == shown.from or args.event == 'BufLeave') then M.closePreview() end
    timer:stop()
    if mode() ~= 'auto' or args.event ~= 'CursorMoved' or vim.bo[args.buf].filetype ~= 'markdown' then return end
    local pos = vim.api.nvim_win_get_cursor(0)
    timer:start(vim.g.linkview_delay or 300, 0, vim.schedule_wrap(function()
      if vim.api.nvim_get_current_buf() ~= args.buf or vim.fn.mode() ~= 'n' then return end
      if not vim.deep_equal(vim.api.nvim_win_get_cursor(0), pos) then return end
      M.preview(true)
    end))
  end,
})

return M
