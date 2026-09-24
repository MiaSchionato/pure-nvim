local M = {}

--- What each key surrounds with: the letter aliases, and the brackets
--- themselves (either half), so s( / ds) / cs[{ work as well as sp / dsb.
---
--- There used to be a second table, `aliases`, with an empty closing half,
--- which relied on pure/pairs.lua closing the pair while the keys were typed.
--- It broke three ways: cs"q replaced the closing quote with nothing ("hello
--- became "hello), ds( found nothing (a bare "(" was treated like a quote),
--- and s( produced (word()) as the auto-pair and the key both closed it.
local pairsFor = {
  ['q'] = { '"', '"' },
  ["'"] = { "'", "'" },
  ['"'] = { '"', '"' },
  ['t'] = { '`', '`' },
  ['`'] = { '`', '`' },
  ['p'] = { '(', ')' }, ['('] = { '(', ')' }, [')'] = { '(', ')' },
  ['b'] = { '[', ']' }, ['['] = { '[', ']' }, [']'] = { '[', ']' },
  ['c'] = { '{', '}' }, ['{'] = { '{', '}' }, ['}'] = { '{', '}' },
  ['<'] = { '<', '>' }, ['>'] = { '<', '>' },
}

--- Opening and closing text for `char`; any other character surrounds with
--- itself on both sides (s* -> *word*).
local function pairOf(char)
  return pairsFor[char] or { char, char }
end

local function findSurroundPositions(char)
  local pair = pairOf(char)
  local openChar, closeChar = pair[1], pair[2]
  local isQuote = (openChar == closeChar) -- Aspas são tratadas diferente (sem nesting)

  local line = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2] + 1 -- Lua string é 1-based

  local openIdx, closeIdx = nil, nil

  -- 1. BUSCA PARA TRÁS (Esquerda) para achar a Abertura
  local balance = 0
  for i = col, 1, -1 do
    local c = line:sub(i, i)
    
    if isQuote then
      if c == openChar then
        openIdx = i
        break -- Aspas: pega a primeira que achar à esquerda
      end
    else
      -- Parenteses/Colchetes: Lógica de Balanceamento
      if c == closeChar then
        balance = balance + 1
      elseif c == openChar then
        if balance > 0 then
          balance = balance - 1
        else
          openIdx = i
          break -- Achamos a abertura correspondente
        end
      end
    end
  end

  -- 2. BUSCA PARA FRENTE (Direita) para achar o Fechamento
  -- Começamos a busca logo após a abertura encontrada, ou da posição atual
  local startRight = (openIdx and openIdx + 1) or col
  
  balance = 0 -- Reinicia balanço
  for i = startRight, #line do
    local c = line:sub(i, i)

    if isQuote then
      if c == closeChar then
        closeIdx = i
        break -- Aspas: pega a próxima
      end
    else
      -- Parenteses:
      if c == openChar then
        balance = balance + 1
      elseif c == closeChar then
        if balance > 0 then
          balance = balance - 1
        else
          closeIdx = i
          break -- Achamos o fechamento correspondente
        end
      end
    end
  end

  if openIdx and closeIdx then
    return {
      open = { line = row, col = openIdx - 1 },   -- Retorna 0-indexed
      close = { line = row, col = closeIdx - 1 }
    }
  end
  return nil
end

local function getChar()
  local char = vim.fn.getchar()
  return vim.fn.nr2char(tonumber(char) or char)
end

--- The keys are fed with 'n' (no remap), so the insert-mode auto-pairs in
--- pure/pairs.lua cannot add a second closing character; <C-r>" inserts the
--- word literally, without mappings either way.
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "n", false)
end

function M.applySurround(isVisual)
  local char = getChar()
  local pair = pairOf(char)
  local open, close = pair[1], pair[2]
  feed((isVisual and "c" or "viwc") .. open .. [[<C-r>"]] .. close .. "<Esc>")
end

function M.surroundFunction(isVisual)
  local func_name = vim.fn.input("Function name: ")
  if func_name == "" then return end
  feed((isVisual and "c" or "viwc") .. func_name .. "(" .. [[<C-r>"]] .. ")" .. "<Esc>")
end

function M.deleteSurround()
  local char = getChar()
  local positions = findSurroundPositions(char)
  if positions then
    local c = positions.close
    vim.api.nvim_buf_set_text(0, c.line, c.col, c.line, c.col +1, {})

    local o = positions.open
    vim.api.nvim_buf_set_text(0, o.line, o.col, o.line, o.col +1, {})
  else
    vim.notify("No surround '" .. char .. " found on the line", vim.log.levels.WARN)
  end
end

function M.changeSurround()
  --  Input: (Old)
  local oldChar = getChar()
  local positions = findSurroundPositions(oldChar)

  if not positions then
    vim.notify("No surround '" .. oldChar .. " found on the line", vim.log.levels.WARN)
    return
  end

  --  Input: (New)
  local newChar = getChar()
  local newPair = pairOf(newChar)
  local newOpen, newClose = newPair[1], newPair[2]

  --  Replace: Start from the right (Closing)
  local c_line, c_col = positions.close.line, positions.close.col
  vim.api.nvim_buf_set_text(0, c_line, c_col, c_line, c_col + 1, { newClose })

  local o_line, o_col = positions.open.line, positions.open.col
  vim.api.nvim_buf_set_text(0, o_line, o_col, o_line, o_col + 1, { newOpen })

  -- Opcional: Feedback visual sutil (piscar cursor ou msg)
  -- vim.notify("Changed " .. old_char .. " to " .. new_char)
end

return M
