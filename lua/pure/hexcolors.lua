-- =============================================================================
--  Hex colours  (#rrggbb drawn in its own colour, in notes)
-- =============================================================================
--  Neovim paints hex codes by itself (vim.lsp.document_color) but only where a
--  language server reports colours: lua_ls in .lua, the CSS servers in CSS.
--  This module does the same in the files no server covers (notes, text), so
--  `#7d82d9` shows its colour behind it in markdown and org too. A buffer that
--  already has a server with colours is left to that server.
--
--  It draws with a decoration provider: only the lines on screen are looked at,
--  nothing is stored in the buffer, and nothing needs refreshing.
--
--  Settings (configs.lua):
--    vim.g.pure_hexcolors            false turns it off
--    vim.g.pure_hexcolors_filetypes  { 'markdown', 'org', 'text' }
--    vim.g.pure_hexcolors_style      'background' (default) | 'foreground'
--    vim.g.pure_hexcolors_short      true also draws #rgb (off: it catches tags like #bad)
--
--  :PureHexColors [on|off|toggle]    changes it while Neovim runs
-- =============================================================================

local M = {}
local api = vim.api

local ns = api.nvim_create_namespace('pure_hexcolors')
local on = true
local groups = {} -- 'bg' / 'fg' .. 'rrggbb' -> highlight group, created when first seen

local function filetypes()
  local list = vim.g.pure_hexcolors_filetypes or { 'markdown', 'org', 'text' }
  local set = {}
  for _, ft in ipairs(list) do set[ft] = true end
  return set
end

-- { { start_col, end_col (exclusive), 'rrggbb' } } of the hex codes in a line (0-based columns).
function M.spans(line, short)
  local out = {}
  local init = 1
  while true do
    local s, e, hex = line:find('#(%x+)', init)
    if not s then break end
    init = e + 1
    local before = line:sub(s - 1, s - 1)
    local after = line:sub(e + 1, e + 1)
    local boundary = not before:match('[%w_#]') and not after:match('[%w_]')
    if boundary then
      if #hex == 6 then
        out[#out + 1] = { s - 1, e, hex:lower() }
      elseif #hex == 3 and short then
        local r, g, b = hex:match('(%x)(%x)(%x)')
        out[#out + 1] = { s - 1, e, (r .. r .. g .. g .. b .. b):lower() }
      end
    end
  end
  return out
end

-- The group for a colour: the colour behind the code and black or white text on top, by brightness.
-- `style` ('background' | 'foreground') defaults to vim.g.pure_hexcolors_style. Also used by pure/highlights.lua.
local function groupFor(hex, style)
  style = style or vim.g.pure_hexcolors_style
  local fg_only = style == 'foreground'
  local key = (fg_only and 'fg' or 'bg') .. hex
  local name = groups[key]
  if name then return name end
  name = 'PureHex' .. (fg_only and 'Fg' or '') .. hex
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  if fg_only then
    api.nvim_set_hl(0, name, { fg = tonumber(hex, 16) })
  else
    local bright = (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.5
    api.nvim_set_hl(0, name, { bg = tonumber(hex, 16), fg = bright and 0x000000 or 0xffffff })
  end
  groups[key] = name
  return name
end

--- The highlight group of 'rrggbb' (no '#'): its colour as background ('background') or as text ('foreground').
function M.group(hex, style)
  return groupFor(hex:lower(), style)
end

local function hasColorServer(buf)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.server_capabilities and client.server_capabilities.colorProvider then return true end
  end
  return false
end

local function eligible(buf)
  return on and vim.g.pure_hexcolors ~= false
    and filetypes()[vim.bo[buf].filetype] == true
    and not hasColorServer(buf)
end

api.nvim_set_decoration_provider(ns, {
  on_win = function(_, _, buf)
    return eligible(buf)
  end,
  on_line = function(_, _, buf, row)
    local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    if not line or not line:find('#', 1, true) then return end
    for _, span in ipairs(M.spans(line, vim.g.pure_hexcolors_short)) do
      api.nvim_buf_set_extmark(buf, ns, row, span[1], {
        end_col = span[2],
        hl_group = groupFor(span[3]),
        priority = 4000,
        ephemeral = true,
      })
    end
  end,
})

-- :hi clear (a colorscheme change) drops the groups; they are made again when drawn.
api.nvim_create_autocmd('ColorScheme', {
  group = api.nvim_create_augroup('PureHexColors', { clear = true }),
  callback = function() groups = {} end,
})

function M.set(want)
  on = want
  vim.cmd('redraw!')
end

api.nvim_create_user_command('PureHexColors', function(opts)
  local arg = opts.args
  if arg == 'on' then M.set(true)
  elseif arg == 'off' then M.set(false)
  else M.set(not on) end
  vim.notify('Hex colours ' .. (on and 'on' or 'off'))
end, {
  nargs = '?',
  complete = function() return { 'on', 'off', 'toggle' } end,
  desc = 'Draw #rrggbb in its own colour (notes)',
})

return M
