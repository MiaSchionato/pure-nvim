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
