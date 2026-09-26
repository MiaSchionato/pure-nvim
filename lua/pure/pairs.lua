local M = {}

local pair = {
  ['('] = ')',
  ['['] = ']',
  ['{'] = '}',
  ['<'] = '>',
  ['"'] = '"',
  ["'"] = "'",
  ['`'] = '`',
}

local function nextChar()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  return vim.api.nvim_get_current_line():sub(col + 1, col + 1)
end

-- Typing a closer that is already there steps over it instead of inserting a
-- second one. Without this, "[ ]" typed by hand came out as "[ ]]": '[' had
-- already added the ']', and the ']' typed after the space added another.
for open, close in pairs(pair) do
  vim.keymap.set('i', open, function()
    -- Quotes open and close with the same key.
    if open == close and nextChar() == close then return '<Right>' end
    return open .. close .. '<Left>'
  end, { expr = true, noremap = true })

  if open ~= close then
    vim.keymap.set('i', close, function()
      return nextChar() == close and '<Right>' or close
    end, { expr = true, noremap = true })
  end
end

-- A completion that brings its own closers lands in front of the ones typed
-- with the opener. "[[" gives "[[]]"; accepting a note from the notes'
-- language server replaces "[[how th" with "[[How this vault works]]", which
-- left "[[How this vault works]]]]" and a broken link. After a completion,
-- the closers right after the cursor are dropped when the inserted text
-- already ends in them and nothing before it is still open for them to
-- close: completing "getcwd()" inside "print(|)" keeps print's own ")".
local opener_of = {}
for open, close in pairs(pair) do
  if open ~= close then opener_of[close] = open end
end

vim.api.nvim_create_autocmd('CompleteDone', {
  group = vim.api.nvim_create_augroup('PurePairsComplete', { clear = true }),
  callback = function()
    local word = (vim.v.completed_item or {}).word or ''
    if word == '' then return end
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local line = vim.api.nvim_get_current_line()
    local start = col - #word + 1
    -- Only when the completed text is what sits right before the cursor.
    if start < 1 or line:sub(start, col) ~= word then return end

    -- Openers the text before the completion leaves unclosed.
    local open = {}
    for ch in line:sub(1, start - 1):gmatch('.') do
      if pair[ch] and pair[ch] ~= ch then
        open[ch] = (open[ch] or 0) + 1
      elseif opener_of[ch] and (open[opener_of[ch]] or 0) > 0 then
        open[opener_of[ch]] = open[opener_of[ch]] - 1
      end
    end

    local after = line:sub(col + 1)
    local drop = 0
    for i = 1, math.min(#after, #word) do
      local ch = after:sub(i, i)
      if not opener_of[ch] or after:sub(1, i) ~= word:sub(-i) or (open[opener_of[ch]] or 0) > 0 then
        break
      end
      drop = i
    end
    if drop > 0 then
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1
      vim.api.nvim_buf_set_text(0, row, col, row, col + drop, {})
    end
  end,
})

local function delete_pair()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1 -- transforma para 0-indexed
  local col = cursor[2]
  local line = vim.api.nvim_get_current_line()
  local char = line:sub(col + 1, col + 1)

  local target_char = pair[char]
  local flags = 'nw'

  if not target_char then
    for o, c in pairs(pair) do
      if char == c then
        target_char = o
        flags = 'bnw'
        break
      end
    end
  end

  if target_char then
    local open_pat = char:match("[%[%(%{]") and "\\" .. char or char
    local close_pat = target_char:match("[%]%}%)]") and "\\" .. target_char or target_char

    if flags == 'bnw' then
      open_pat, close_pat = close_pat, open_pat
    end

    local pair_pos = vim.fn.searchpairpos(open_pat, "", close_pat, flags)

    if pair_pos[1] ~= 0 then
      local p_row, p_col = pair_pos[1] - 1, pair_pos[2] - 1

      if p_row > row or (p_row == row and p_col > col) then
        vim.api.nvim_buf_set_text(0, p_row, p_col, p_row, p_col + 1, {})
        vim.api.nvim_buf_set_text(0, row, col, row, col + 1, {})
      else
        vim.api.nvim_buf_set_text(0, row, col, row, col + 1, {})
        vim.api.nvim_buf_set_text(0, p_row, p_col, p_row, p_col + 1, {})
      end
      vim.notify('pair deleted')
      return
    end
  end

  vim.cmd("normal! x")
end
vim.keymap.set('n', 'dl', delete_pair, { desc = "Delete char and its pair" })

vim.keymap.set('i', '<BS>', function()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line()
  local left = line:sub(col, col)
  local right = line:sub(col + 1, col + 1)

  if pair[left] == right then
    return "<BS><Del>"
  end
  return "<BS>"
end, { expr = true })

return M
