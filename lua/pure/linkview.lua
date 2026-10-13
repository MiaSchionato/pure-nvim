-- =============================================================================
--  Link view
-- =============================================================================
--  Look at a linked note without leaving the one you are writing:
--
--    <leader>vp   preview: a floating, read-only window with the note the
--                 link under the cursor points to (just the section for
--                 [[Note#Heading]], just the block for [[Note#^id]]), without
--                 its frontmatter. Moving the cursor closes it; the key again
--                 closes it too.
--    <leader>vq   quick edit: the note itself (the real buffer, not a copy)
--                 in a floating window. :w saves; q or <Esc> in normal mode
--                 closes it, saving what changed, and unloads the note again
--                 if it was not open before.
--
--  Settings (vim.g.*, described in configs/configs.lua):
--    linkview_preview   'key' (default: only on the key), 'auto' (also after
--                       the cursor rests on a link) or 'off' (nothing)
--    linkview_delay     ms the cursor rests before 'auto' shows it (default 600)
--    linkview_keys      { preview = '<leader>vp', edit = '<leader>vq' }
-- =============================================================================

local M = {}

local func = require('configs.functions')
local notes = require('pure.notes')

local DEFAULT_KEYS = { preview = '<leader>vp', edit = '<leader>vq' }

local shown = { win = nil, from = nil } -- the preview window, and the buffer it was asked in

local function mode() return vim.g.linkview_preview or 'key' end

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
  local win, buf = func.createWindow(' ' .. t.name .. (t.sub and ('#' .. t.sub) or '') .. ' ', 0.6, { enter = false })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 0
  shown.win, shown.from = win, from
  -- A short note leaves empty rows: shrink to what it needs.
  local rows = 0
  local width = vim.api.nvim_win_get_width(win)
  for _, l in ipairs(lines) do rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / math.max(width, 1))) end
  if rows < vim.api.nvim_win_get_height(win) then
    vim.api.nvim_win_set_height(win, math.max(rows, 1))
    local cfg = vim.api.nvim_win_get_config(win)
    cfg.row = math.max(math.ceil((vim.o.lines - rows - 2) / 2), 0)
    vim.api.nvim_win_set_config(win, cfg)
  end
end

-- -----------------------------------------------------------------------------
--  Quick edit
-- -----------------------------------------------------------------------------

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

  -- q and <Esc> close it, unless the buffer already has them for something
  local mapped = {}
  for _, key in ipairs({ 'q', '<Esc>' }) do
    if vim.fn.maparg(key, 'n', false, true).buffer ~= 1 then
      vim.keymap.set('n', key, function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      end, { buffer = buf, nowait = true, desc = 'Close the quick edit' })
      table.insert(mapped, key)
    end
  end

  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      for _, key in ipairs(mapped) do pcall(vim.keymap.del, 'n', key, { buffer = buf }) end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if vim.bo[buf].modified then
        vim.api.nvim_buf_call(buf, function() pcall(vim.cmd, 'silent update') end)
      end
      -- Not open before: leave nothing behind (unless another window shows it)
      vim.schedule(function()
        if was_open or not vim.api.nvim_buf_is_valid(buf) or #vim.fn.win_findbuf(buf) > 0 then return end
        if vim.bo[buf].modified then return end -- saving failed: keep it
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
    timer:start(vim.g.linkview_delay or 600, 0, vim.schedule_wrap(function()
      if vim.api.nvim_get_current_buf() ~= args.buf or vim.fn.mode() ~= 'n' then return end
      if not vim.deep_equal(vim.api.nvim_win_get_cursor(0), pos) then return end
      M.preview(true)
    end))
  end,
})

return M
