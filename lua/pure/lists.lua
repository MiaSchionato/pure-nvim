-- =============================================================================
--  Markdown lists
-- =============================================================================
--  In a markdown note a new line under a list item starts the next item, as
--  in Obsidian: <CR> in insert mode, and o / O in normal mode, repeat
--
--    - text  /  * text  /  + text     the same bullet
--    - [x] text                       a checkbox, always unchecked: - [ ]
--    3. text  /  3) text              the next number (O: the same one)
--
--  with the same indentation, inside a quote or callout too ("> - item").
--  <CR> in the middle of an item takes the rest of the line into the new one.
--
--  <CR> on an item with no text ends the list instead: an indented item moves
--  one level out, a top-level one loses its marker.
--
--  Nothing changes inside a fenced code block, with the cursor on the marker
--  itself, or on a line that is not a list item.
--
--  <CR> is mapped in configs/keymaps.lua (with Copilot's suggestions and the
--  completion menu), o in pure/calendar.lua (a calendar grid has its own);
--  both ask enter() / open() here for the keys.
-- =============================================================================

local M = {}

--- The list item on `line`, or nil.
---
---   prefix  what comes before the marker that autoindent does not repeat:
---           the quote ("> "), and any space after it
---   marker  what starts the item ("- [x]", "*", "3.")
---   next    the marker of a new item below; `same` of a new item above
---   start   0-based byte column where the item's text starts
---   text    the item's text
--- @param line string
--- @return table|nil
local function parse(line)
  local indent = line:match('^%s*')
  local pos = #indent + 1
  -- The quote, "> " or nested "> > ", taken one '>' at a time: Lua patterns
  -- cannot repeat a group.
  local quote = ''
  while line:sub(pos, pos) == '>' do
    local q = line:match('^>%s*', pos)
    quote = quote .. q
    pos = pos + #q
  end
  local rest = line:sub(pos)

  local bullet, box = rest:match('^([-*+]) (%[.%])')
  if bullet and (#rest == #bullet + 4 or rest:sub(#bullet + 5, #bullet + 5) == ' ') then
    local marker = bullet .. ' ' .. box
    local next = bullet .. ' [ ]'
    return { indent = indent, prefix = quote, marker = marker, next = next, same = next,
      start = pos - 1 + math.min(#rest, #marker + 1), text = rest:sub(#marker + 2) }
  end

  bullet = rest:match('^([-*+]) ')
  if bullet then
    return { indent = indent, prefix = quote, marker = bullet, next = bullet, same = bullet,
      start = pos - 1 + 2, text = rest:sub(3) }
  end

  local n, delim = rest:match('^(%d+)([.)]) ')
  if n then
    return { indent = indent, prefix = quote, marker = n .. delim,
      next = (tonumber(n) + 1) .. delim, same = n .. delim,
      start = pos - 1 + #n + 2, text = rest:sub(#n + 3) }
  end
  return nil
end

--- Whether 0-based `row` of the current buffer is inside a fenced code block.
local function inFence(row)
  local fence
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, row, false)) do
    local mark = line:match('^%s*(```+)') or line:match('^%s*(~~~+)')
    if mark then
      if not fence then
        fence = mark
      elseif mark:sub(1, 1) == fence:sub(1, 1) and #mark >= #fence then
        fence = nil
      end
    end
  end
  return fence ~= nil
end

--- The list item on the cursor line, when lists continue here.
local function current()
  if vim.bo.filetype ~= 'markdown' or vim.bo.buftype ~= '' then return nil end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local it = parse(vim.api.nvim_get_current_line())
  if not it or inFence(row) then return nil end
  return it
end

--- The list item on the cursor line, or nil. Public for Tab / S-Tab in
--- configs/keymaps.lua, which indent a list item from anywhere in it.
M.item = current

--- The keys for <CR> in insert mode on a list item, or nil when it is not
--- one (a plain <CR> then). Keycodes already replaced.
--- @return string|nil
function M.enter()
  local it = current()
  if not it then return nil end
  local col = vim.api.nvim_win_get_cursor(0)[2]
  if col < it.start then return nil end -- on the marker: a plain new line

  if vim.trim(it.text) == '' then
    -- An empty item ends the list. The indentation autoindent copies can be
    -- taken back with <C-d>; a quote is retyped without the marker.
    if it.prefix == '' and it.indent ~= '' then return vim.keycode('<C-d>') end
    return vim.keycode('<C-u>') .. it.indent:gsub('\t', '    ') .. it.prefix
  end
  -- autoindent (with copyindent) repeats the indentation; the rest is typed.
  return vim.keycode('<CR>') .. it.prefix .. it.next .. ' '
end

--- The keys for `key` (o or O) in normal mode: the key and, on a list item,
--- the marker of the new item.
--- @param key string
--- @return string
function M.open(key)
  local it = current()
  if not it then return key end
  return key .. it.prefix .. (key == 'O' and it.same or it.next) .. ' '
end

-- Markdown: indentation that autoindent copies as it is (tabs stay tabs), and
-- no smartindent, which is for C: in prose it indented the line after one
-- starting with "if" or "for", and dropped the indent of a "# heading".
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('PureLists', { clear = true }),
  pattern = 'markdown',
  callback = function(args)
    vim.bo[args.buf].autoindent = true
    vim.bo[args.buf].copyindent = true
    vim.bo[args.buf].smartindent = false
    vim.keymap.set('n', 'O', function() return M.open('O') end,
      { buffer = args.buf, expr = true, desc = 'Open a line above (next list item)' })
  end,
})

M._parse, M._inFence = parse, inFence

return M
