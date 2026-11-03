-- =============================================================================
--  A pasted link gets its name (org and markdown notes)
-- =============================================================================
--  Paste a bare http(s) URL into an org or markdown note (a terminal paste: Ctrl+V, Win+V, the middle button) and it
--  becomes a link at once, called by the site's name:
--
--      org        [[https://github.com/neovim/neovim][github.com]]
--      markdown   [github.com](https://github.com/neovim/neovim)
--
--  then, as soon as the page answers (curl, in the background; the text you keep typing is not disturbed), the name
--  is replaced by the page's title: its og:title or <title>, and for YouTube the video's name (oEmbed). A page that
--  does not answer, or has no title, keeps the site's name.
--
--  Left alone: a paste of anything but one URL, a paste inside a link ([[...]] or ](...)), other file types (text
--  files have no link syntax), a long paste that arrives in pieces, and Visual or Command-line mode.
--  `vim.g.pure_url_titles = false` turns it off (configs/configs.lua: on by default).
--  Pasting makes a request to the pasted address: the same one opening the link would make.
local M = {}

local FILETYPES = { org = true, markdown = true }
local ns = vim.api.nvim_create_namespace('pure_url_title')
local USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
local MAX_TITLE = 120

-- ---- the title of a page ----------------------------------------------------------------------------------------
local ENTITIES = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', ndash = '–', mdash = '—', hellip = '…' }

local function decodeEntities(text)
  text = text:gsub('&#x(%x+);', function(n) return vim.fn.nr2char(tonumber(n, 16)) end)
  text = text:gsub('&#(%d+);', function(n) return vim.fn.nr2char(tonumber(n)) end)
  text = text:gsub('&(%a+);', function(name) return ENTITIES[name] end)
  return text
end

--- A title as it goes inside a link: entities decoded, spaces collapsed, no brackets (they would end the link early),
--- not too long.
function M.cleanTitle(title)
  title = decodeEntities(title)
  title = title:gsub('%s+', ' ')
  title = vim.trim(title)
  title = title:gsub('%[', '('):gsub('%]', ')')
  title = title:gsub('^(.-) %- YouTube$', '%1')
  if vim.fn.strchars(title) > MAX_TITLE then title = vim.fn.strcharpart(title, 0, MAX_TITLE - 1) .. '…' end
  return title
end

local function attribute(tag, name)
  return tag:match(name .. '%s*=%s*"([^"]*)"') or tag:match(name .. "%s*=%s*'([^']*)'")
end

--- The title in the HTML of a page: og:title, else <title>. nil when there is none.
function M.htmlTitle(html)
  for tag in html:gmatch('<[Mm][Ee][Tt][Aa][^>]*>') do
    if attribute(tag, 'property') == 'og:title' or attribute(tag, 'name') == 'og:title' then
      local content = attribute(tag, 'content')
      if content and vim.trim(content) ~= '' then return M.cleanTitle(content) end
    end
  end
  local title = html:match('<[Tt][Ii][Tt][Ll][Ee][^>]*>(.-)</[Tt][Ii][Tt][Ll][Ee]>')
  if title and vim.trim(title) ~= '' then return M.cleanTitle(title) end
  return nil
end

--- `host` of an address without "www.", the port and the user.
function M.siteName(url)
  local host = url:match('^%a+://([^/%?#]+)') or url
  host = host:gsub('^.*@', ''):gsub(':%d+$', ''):gsub('^[Ww][Ww][Ww]%.', '')
  return host
end

local function isYouTube(url)
  local host = M.siteName(url):lower()
  return host == 'youtube.com' or host == 'm.youtube.com' or host == 'music.youtube.com' or host == 'youtu.be'
end

local function curl(args, callback)
  if vim.fn.executable('curl') == 0 then return callback(nil) end
  local cmd = { 'curl', '-sL', '--compressed', '--max-time', '8', '--max-filesize', '3000000', '-A', USER_AGENT }
  vim.list_extend(cmd, args)
  local ok = pcall(vim.system, cmd, { text = true }, function(out)
    vim.schedule(function() callback(out.code == 0 and out.stdout or nil) end)
  end)
  if not ok then callback(nil) end
end

--- The title of the page at `url`, asked in the background; `callback(title or nil)` runs in the main loop.
function M.fetchTitle(url, callback)
  local function fromPage()
    curl({ '-r', '0-262143', url }, function(html)
      callback(html and M.htmlTitle(html) or nil)
    end)
  end
  if not isYouTube(url) then return fromPage() end
  -- A YouTube page is mostly script: its oEmbed answer holds the video's name.
  curl({ 'https://www.youtube.com/oembed?format=json&url=' .. vim.uri_encode(url) }, function(body)
    local ok, data = pcall(vim.json.decode, body or '')
    local title = ok and type(data) == 'table' and type(data.title) == 'string' and M.cleanTitle(data.title) or nil
    if title and title ~= '' then return callback(title) end
    fromPage()
  end)
end

-- ---- the link --------------------------------------------------------------------------------------------------
--- The text of the link for `filetype`; `name` nil gives the bare form.
function M.linkText(filetype, url, name)
  if filetype == 'org' then
    url = url:gsub('%[', '%%5B'):gsub('%]', '%%5D')
    return name and ('[[' .. url .. '][' .. name .. ']]') or ('[[' .. url .. ']]')
  end
  url = url:gsub('%(', '%%28'):gsub('%)', '%%29'):gsub(' ', '%%20')
  return '[' .. (name or url) .. '](' .. url .. ')'
end

--- Whether `col` (a byte index) of `line` is inside a link: after an unclosed [[ (org) or in the (...) of ](...) (markdown).
local function insideLink(line, col)
  local before = line:sub(1, col)
  local open, close = before:match('.*()%[%['), before:match('.*()%]%]')
  if open and (not close or close < open) then return true end
  local target = before:match('.*()%]%(')
  if target and not before:find(')', target, true) then return true end
  return false
end

--- Replace the placeholder at the extmark `id` by `text`, if the user has not touched it. The cursor of the window that
--- shows the buffer keeps its place: after the link it moves with the text; inside it (Esc after the paste leaves it on
--- the last character) it keeps its distance from the end.
local function replace(buf, id, placeholder, text)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local mark = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
  if not mark[1] then return end
  local row, col, details = mark[1], mark[2], mark[3]
  vim.api.nvim_buf_del_extmark(buf, ns, id)
  if details.end_row ~= row then return end
  local current = vim.api.nvim_buf_get_text(buf, row, col, row, details.end_col, {})[1]
  if current ~= placeholder then return end -- edited meanwhile: leave it
  local win = vim.fn.bufwinid(buf)
  local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or nil
  vim.api.nvim_buf_set_text(buf, row, col, row, details.end_col, { text })
  if cursor and cursor[1] == row + 1 and cursor[2] > col then
    local moved = cursor[2] + #text - #placeholder -- after the link: the same place in the text that follows
    if cursor[2] < details.end_col then moved = math.max(col + #text - (details.end_col - cursor[2]), col) end
    pcall(vim.api.nvim_win_set_cursor, win, { cursor[1], moved })
  end
end

--- Turn the pasted `url` into a link at the cursor. Returns true when it did.
function M.insert(url)
  local buf = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[buf].filetype
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local at = col
  local insert_mode = vim.api.nvim_get_mode().mode:sub(1, 1) == 'i'
  if not insert_mode and #line > 0 then at = col + 1 end -- Normal mode pastes after the cursor character
  if insideLink(line, at) then return false end

  local placeholder = M.linkText(filetype, url, M.siteName(url))
  vim.api.nvim_buf_set_text(buf, row - 1, at, row - 1, at, { placeholder })
  local id = vim.api.nvim_buf_set_extmark(buf, ns, row - 1, at, {
    end_row = row - 1, end_col = at + #placeholder, right_gravity = false, end_right_gravity = false,
  })
  vim.api.nvim_win_set_cursor(0, { row, at + #placeholder - (insert_mode and 0 or 1) })
  M.fetchTitle(url, function(title)
    if title and title ~= '' then replace(buf, id, placeholder, M.linkText(filetype, url, title)) end
  end)
  return true
end

--- `vim.paste`'s hook: true when the paste was a lone URL turned into a link.
function M.paste(lines, phase)
  if phase ~= -1 or vim.g.pure_url_titles == false then return false end
  local buf = vim.api.nvim_get_current_buf()
  if not FILETYPES[vim.bo[buf].filetype] or vim.bo[buf].buftype ~= '' or not vim.bo[buf].modifiable then return false end
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  if mode ~= 'i' and mode ~= 'n' then return false end
  local url
  for _, line in ipairs(lines) do
    line = vim.trim(line)
    if line ~= '' then
      if url then return false end -- more than one line of text
      url = line
    end
  end
  if not url or not url:match('^https?://[^%s]+$') then return false end
  return M.insert(url)
end

local installed = false
--- Put the hook in `vim.paste` (once).
function M.setup()
  if installed then return end
  installed = true
  local original = vim.paste
  vim.paste = function(lines, phase)
    local ok, handled = pcall(M.paste, lines, phase)
    if ok and handled then return true end
    return original(lines, phase)
  end
end

return M
