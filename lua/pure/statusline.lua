local M = {}


local  colors_hl= {
  n = "%#BlueMode#",
  i = "%#EmeraldMode#",
  v = "%#PurpleMode#",
  V = "%#WatermelonMode#",
  c = "%#TanMode#",
  t = "%#PlantMode#",
  nt = "%#BlueMode#",
}
local icons_group = require('themes.myghtfly').icons_group

-- The mode and icon groups are only defined by the myghtfly theme; under any
-- other colorscheme (NeoSolarized included) they were empty and the statusline
-- lost all its colour. These are myghtfly's own values, set as `default` on
-- every ColorScheme: myghtfly still defines them itself, other themes get these.
local fallback = {
  BlueMode       = { bg = '#82aaff', fg = '#092236' },
  EmeraldMode    = { bg = '#21c7a8', fg = '#092236' },
  PurpleMode     = { bg = '#ae81ff', fg = '#092236' },
  WatermelonMode = { bg = '#ff5874', fg = '#092236' },
  TanMode        = { bg = '#ecc48d', fg = '#092236' },
  PlantMode      = { bg = '#2a4e57', fg = '#092236' },
  IconsBlue      = { fg = '#82aaff' },
  IconsGrey      = { fg = '#7c8f8f' },
  IconsPurple    = { fg = '#ae81ff' },
  IconsOrange    = { fg = '#f78c6c' },
  IconsYellow    = { fg = '#e3d18a' },
}
local function setFallbackColours()
  for name, spec in pairs(fallback) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend('force', spec, { default = true }))
  end
end
setFallbackColours()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setFallbackColours })

function _G.PureMacroStatus()
    local recording_register = vim.fn.reg_recording()
    if recording_register == "" then
        return ""
    else
        return " ⏺ @" .. recording_register .. " "
    end
end

--- Neovim draws every window's statusline with the *current* window still
--- current, and tells the function which window it is drawing in
--- g:statusline_winid. Reading vim.bo / buffer 0 / the mode directly showed the
--- active window's filetype, errors and mode in every other window too.
function M.MyStatusLine()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local active = win == vim.api.nvim_get_current_win()

  -- The mode only means something in the window being typed in.
  local m = active and vim.api.nvim_get_mode().mode or ''
  local highlight = colors_hl[m] or "%#StatusLine#"
  local mode = active and (" " .. m:upper() .. " ") or "   "

  local errors = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
  local diag_str = errors > 0 and string.format(" %%#DiagnosticError#  %d ", errors) or ""

  local filename = "%t %m"
  local cursor_location = "%l:%c"
  local ft = vim.bo[buf].filetype
  local data = icons_group[ft] or icons_group['default_icon']

  if vim.bo[buf].buftype == "terminal" then
    data = icons_group['terminal']
    filename =  vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
  end

    -- Pegamos o ícone correspondente ao filetype
  local icon = string.format("%%#%s#%s %%#StatusLine#%s ", data.hl, data.icon, ft)

  return table.concat({
    highlight, mode,
    "%#StatusLine#"," ", diag_str, filename,
    "%=",
    "%#StatusLine#" .. "%#ErrorMsg#%{v:lua.PureMacroStatus()}%*" .. " %S ",icon, cursor_location,
  })
end

vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
    callback = function()
        vim.cmd("redrawstatus")
    end,
})

return M
