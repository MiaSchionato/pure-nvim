-- =============================================================================
--  Picker style  (the look of <leader>vf, for every picker)
-- =============================================================================
--  <leader>vf (pure/flora.lua) set the look: the name in colour on the left, then
--  (dim, to the right) the folder and how long ago the file was written; the
--  colours are PureNoteFile, PureNoteAlias, PureNoteSep (pure/notecolors.lua).
--  The other pickers (pure/fuzzyUtils.lua) draw their lines with this module.
--
--  A line of such a picker is  "visible \t hidden fields"  and fzf is run with
--  PICKER_FZF: it shows only the first field, so what you type matches the name,
--  the folder and the age, while the next fields (the full path, the line) come
--  back to Neovim with the choice.
-- =============================================================================

local M = {}

local ESC = string.char(27)

--- The fzf flags of a picker made of such lines.
M.FZF = "--ansi --delimiter '\\t' --with-nth 1 --tiebreak=index"

--- The width the name column takes before the dim text starts.
M.NAME_WIDTH = 44

function M.trunc(text, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  while vim.fn.strdisplaywidth(text) > width - 1 and #text > 0 do
    text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
  end
  return text .. '…'
end

function M.truncLeft(text, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  while vim.fn.strdisplaywidth(text) > width - 1 and #text > 0 do
    text = vim.fn.strcharpart(text, 1)
  end
  return '…' .. text
end

--- Dired's way of saying how long ago: now, 37m ago, 1h 37m ago, 1d 17h ago, 23d ago.
function M.age(mtime)
  local secs = math.max(0, os.time() - mtime)
  local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
  if secs < 60 then return 'now' end
  if secs < 3600 then return m .. 'm ago' end
  if secs < 86400 then return h .. 'h ' .. m .. 'm ago' end
  if d < 10 then return d .. 'd ' .. h .. 'h ago' end
  return d .. 'd ago'
end

--- The foreground of a highlight group as r, g, b (nil when it has none).
function M.rgb(group)
  local n = vim.api.nvim_get_hl(0, { name = group, link = false }).fg
  if not n then return nil end
  return math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
end

--- `text` in the foreground of highlight group `group` (ANSI truecolor); `extra` adds attributes ("3;" italic).
function M.paint(group, text, extra)
  local r, g, b = M.rgb(group)
  if not r then return text end
  return string.format('%s[%s38;2;%d;%d;%dm%s%s[0m', ESC, extra or '', r, g, b, text, ESC)
end

--- Make sure the groups exist for the current colorscheme.
function M.colors()
  pcall(function() require('pure.notecolors').apply() end)
end

local function plain(text)
  return (text:gsub(ESC .. '%[[%d;]*m', ''))
end

--- The visible part of a line: `left` (already painted), padded to the name column, then the dim `meta`.
function M.row(left, meta)
  local pad = math.max(M.NAME_WIDTH - vim.fn.strdisplaywidth(plain(left)), 2)
  return left .. string.rep(' ', pad) .. M.paint('PureNoteSep', meta)
end

--- A file as a line: the name in colour, then the folder (and how long ago) dim.
--- `hidden`: the fields that follow the tab, e.g. { path, lnum, col }; `extra`: text after the folder (":42").
function M.fileLine(path, hidden, extra)
  local full = vim.fs.normalize(path)
  local name = vim.fn.fnamemodify(full, ':t')
  local dir = vim.fn.fnamemodify(full, ':~:h')
  local stat = vim.uv.fs_stat(full)
  local meta = M.truncLeft(dir, 36) .. (extra or '')
  -- The age in a column of its own, so the lines line up (as the file search's awk does).
  meta = meta .. string.rep(' ', math.max(36 - vim.fn.strdisplaywidth(meta), 0))
  if stat then meta = string.format('%s  %11s', meta, M.age(stat.mtime.sec)) end
  local fields = { M.row(M.paint('PureNoteFile', M.trunc(name, M.NAME_WIDTH - 2)), meta) }
  for _, field in ipairs(hidden or { full }) do fields[#fields + 1] = tostring(field) end
  return table.concat(fields, '\t')
end

--- The last tab-separated field of a choice (the hidden one that names what was picked).
function M.last(selection)
  return selection:match('([^\t]*)$')
end

--- The fields after the visible one, as a list.
function M.fields(selection)
  local out = vim.split(selection, '\t', { plain = true })
  table.remove(out, 1)
  return out
end

--- The awk program that turns a list of paths into such lines (name, then the folder and the age, dim;
--- the path after a tab). Used where the list is made by fd, so the lines are drawn without Neovim
--- reading them. A line may start with "@LABEL<tab>" (how recently the file changed, as the list's tier
--- says: "<1h ago", "<1d ago", "7d+ ago"): the label is the age column. Reading the time of every file
--- takes minutes in a big tree, so the age is the tier of the list, not the exact time.
function M.awkProgram()
  local function sgr(group)
    local r, g, b = M.rgb(group)
    if not r then return '', '' end
    return string.format('\\033[38;2;%d;%d;%dm', r, g, b), '\\033[0m'
  end
  local nameOn, off = sgr('PureNoteFile')
  local dirOn = sgr('PureNoteSep')
  return table.concat({
    '{',
    '  line = $0',
    '  stamp = ""',
    '  if (match(line, /^@[^\\t]*\\t/)) { stamp = substr(line, 2, RLENGTH - 2); line = substr(line, RLENGTH + 1) }',
    '  n = split(line, a, "/")',
    '  name = a[n]',
    '  if (name == "" && n > 1) name = a[n - 1] "/"',
    '  dir = (n > 1) ? substr(line, 1, length(line) - length(a[n]) - 1) : ""',
    '  if (length(dir) > 36) dir = "…" substr(dir, length(dir) - 34)',
    '  pad = ' .. M.NAME_WIDTH .. ' - length(name)',
    '  if (pad < 2) pad = 2',
    '  meta = sprintf("%-36s  %11s", dir, stamp)',
    string.format('  printf "%s%%s%s%%*s%s%%s%s\\t%%s\\n", name, pad, "", meta, line', nameOn, off, dirOn, off),
    '}',
  }, '\n') .. '\n'
end

return M
