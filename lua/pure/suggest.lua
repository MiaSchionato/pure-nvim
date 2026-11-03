-- =============================================================================
--  Suggestions from what is being written (a source of the 'autocomplete' menu)
-- =============================================================================
--  Type "hoje", "today" or "oggi" and the menu offers today's date; "amanhã" / "tomorrow", "ontem" /
--  "yesterday", the name of a weekday (its next date) and "agora" / "now" (the time) work the same way.
--  Taking one replaces the word you typed.
--
--  The shapes of a date: in an org note the org timestamps first (<2026-11-03 Tue>, [2026-11-03 Tue]),
--  then 2026-11-03, 03/11/2026 and "3 de novembro de 2026". The time: 14:05, 2026-11-03 14:05 (and the org
--  timestamps with the time, in org notes).
--
--  How it is wired: 'complete' in configs/configs.lua has `Fv:lua.require'pure.suggest'.complete` (the F{func}
--  flag: a function that is asked like a 'completefunc'), before the other sources. It answers in text and markup
--  files only (org, markdown and .txt): `vim.g.pure_suggest_filetypes` replaces that list,
--  `vim.g.pure_suggest = false` turns it off. Which words count: the whole trigger, or the start of it when that
--  is at least five letters and at most one letter short ("tomorro" shows tomorrow, "toda" and "ho" do not, so
--  "toda a noite" is left alone); weekday names only when typed whole. Accents and case do not matter
--  ("amanha" is "amanhã"). The triggers are the table below.
local M = {}

local PROSE = { org = true, markdown = true, text = true } -- text is .txt

local MONTHS = {
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
}

--  words: what to type (without accents, lower case: the typed word is folded the same way)
--  day: days from today · weekday: 1 = Sunday ... 7 = Saturday (as os.date('*t').wday) · now: the time
--  exact: only the whole word counts
local TRIGGERS = {
  { words = { 'hoje', 'today', 'oggi' }, day = 0, label = 'today' },
  { words = { 'amanha', 'tomorrow', 'domani' }, day = 1, label = 'tomorrow' },
  { words = { 'ontem', 'yesterday', 'ieri' }, day = -1, label = 'yesterday' },
  { words = { 'agora', 'now', 'adesso' }, now = true, label = 'now' },
  { words = { 'domingo', 'sunday', 'domenica' }, weekday = 1, exact = true },
  { words = { 'segunda', 'monday', 'lunedi' }, weekday = 2, exact = true },
  { words = { 'terca', 'tuesday', 'martedi' }, weekday = 3, exact = true },
  { words = { 'quarta', 'wednesday', 'mercoledi' }, weekday = 4, exact = true },
  { words = { 'quinta', 'thursday', 'giovedi' }, weekday = 5, exact = true },
  { words = { 'sexta', 'friday', 'venerdi' }, weekday = 6, exact = true },
  { words = { 'sabado', 'saturday', 'sabato' }, weekday = 7, exact = true },
}

local ACCENTS = {
  ['á'] = 'a', ['à'] = 'a', ['â'] = 'a', ['ã'] = 'a', ['ä'] = 'a',
  ['é'] = 'e', ['è'] = 'e', ['ê'] = 'e', ['ë'] = 'e',
  ['í'] = 'i', ['ì'] = 'i', ['î'] = 'i',
  ['ó'] = 'o', ['ò'] = 'o', ['ô'] = 'o', ['õ'] = 'o', ['ö'] = 'o',
  ['ú'] = 'u', ['ù'] = 'u', ['û'] = 'u', ['ü'] = 'u',
  ['ç'] = 'c',
}

--- Lower case and without accents.
local function fold(text)
  text = vim.fn.tolower(text)
  for from, to in pairs(ACCENTS) do text = text:gsub(from, to) end
  return text
end

--- Whether the typed word `base` (folded) asks for the trigger word `word`.
local function matches(base, word, exact)
  if base == word then return true end
  if exact then return false end
  return #base >= math.max(5, #word - 1) and word:sub(1, #base) == base
end

--- Noon of today plus `days`, so a change of daylight saving time never moves it to another day.
local function dayAt(days)
  local today = os.date('*t')
  return os.time({ year = today.year, month = today.month, day = today.day + days, hour = 12 })
end

local function dateTexts(time, org)
  local weekday = os.date('%a', time)
  local iso = os.date('%Y-%m-%d', time)
  local parts = os.date('*t', time)
  local texts = {}
  if org then
    texts[#texts + 1] = '<' .. iso .. ' ' .. weekday .. '>'
    texts[#texts + 1] = '[' .. iso .. ' ' .. weekday .. ']'
  end
  texts[#texts + 1] = iso
  texts[#texts + 1] = os.date('%d/%m/%Y', time)
  texts[#texts + 1] = parts.day .. ' de ' .. MONTHS[parts.month] .. ' de ' .. parts.year
  return texts
end

local function timeTexts(org)
  local clock, iso, weekday = os.date('%H:%M'), os.date('%Y-%m-%d'), os.date('%a')
  local texts = {}
  if org then
    texts[#texts + 1] = '<' .. iso .. ' ' .. weekday .. ' ' .. clock .. '>'
    texts[#texts + 1] = '[' .. iso .. ' ' .. weekday .. ' ' .. clock .. ']'
  end
  texts[#texts + 1] = clock
  texts[#texts + 1] = iso .. ' ' .. clock
  return texts
end

--- The menu items (a `complete-items` list) for the typed word `base`, in the shape `org` asks for.
--- Pure: it needs no buffer, so it can be tested alone.
function M.items(base, org)
  base = fold(base)
  local items, seen = {}, {}
  local function add(text, label, kind)
    if seen[text] then return end
    seen[text] = true
    items[#items + 1] = { word = text, abbr = text, menu = label, kind = kind, dup = 1 }
  end
  for _, trigger in ipairs(TRIGGERS) do
    local hit = false
    for _, word in ipairs(trigger.words) do
      if matches(base, word, trigger.exact) then hit = true end
    end
    if hit then
      if trigger.now then
        for _, text in ipairs(timeTexts(org)) do add(text, trigger.label, 'Time') end
      else
        local days = trigger.day
        if trigger.weekday then
          days = (trigger.weekday - os.date('*t').wday) % 7
          if days == 0 then days = 7 end -- the weekday of today means the next one
        end
        local label = trigger.label or (os.date('%A', dayAt(days)):lower())
        for _, text in ipairs(dateTexts(dayAt(days), org)) do add(text, label, 'Date') end
      end
    end
  end
  return items
end

local function wanted()
  if vim.g.pure_suggest == false then return false end
  local list = vim.g.pure_suggest_filetypes
  local filetype = vim.bo.filetype
  if type(list) == 'table' then return vim.tbl_contains(list, filetype) end
  return PROSE[filetype] == true
end

--- The source of 'complete' (called like a 'completefunc'). -2: nothing here, the other sources go on.
function M.complete(findstart, base)
  if findstart == 1 then
    if not wanted() then return -2 end
    local col = vim.fn.col('.') - 1
    local word = vim.api.nvim_get_current_line():sub(1, col):match('([%a\128-\255]+)$')
    if not word or #word < 3 or #M.items(word, false) == 0 then return -2 end
    return col - #word
  end
  return M.items(base, vim.bo.filetype == 'org')
end

return M
