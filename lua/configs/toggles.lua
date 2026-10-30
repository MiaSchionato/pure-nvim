-- =============================================================================
--  Toggles that stay as you left them
-- =============================================================================
--  The <leader>o toggles (and the note rendering) save their state in
--  stdpath('data')/toggles.json, so what was turned off stays off the next time
--  Neovim starts. Only a toggle you pressed is stored; until then the defaults
--  of configs.lua apply. Delete the file (or :PureToggles reset) to go back.
--
--    saved by          key in the file
--    <leader>om        render_md (true/false), render_org ('full'|'partial'|'off')
--    <leader>oH        heading_band (the coloured bar behind md/org headings)
--    <leader>oxc       transparent        <leader>od   diagnostics_virtual_text
--    <leader>os        laststatus         <leader>ot   showtabline
--    <leader>oc        signcolumn         <leader>ow   wrap
--    <leader>on / or   number, relativenumber
--    <leader>oi        inlay_hints        <leader>op   copilot
--    reading mode      reading (pure/reading.lua: a centred column between wide margins)
--
--  Not saved on purpose: zen mode (a temporary state; it puts things back as
--  they are) and the word highlight (<leader>oh, it follows the cursor).
--
--  This file loads after configs.lua and functions.lua, so the saved options
--  win over the defaults there.
--
--  :PureToggles          shows what is saved
--  :PureToggles reset    forgets it all (back to the defaults on the next start)
-- =============================================================================

local M = {}

local file = vim.fn.stdpath('data') .. '/toggles.json'
local data

local function load()
  if data then return data end
  data = {}
  local fh = io.open(file, 'r')
  if fh then
    local text = fh:read('*a')
    fh:close()
    local ok, decoded = pcall(vim.json.decode, text)
    if ok and type(decoded) == 'table' then data = decoded end
  end
  return data
end

--- The saved value of a toggle, or `default` when it was never pressed.
function M.get(key, default)
  local value = load()[key]
  if value == nil then return default end
  return value
end

--- Save a value (nil forgets it). Never raises: a read-only data folder must not break a toggle.
function M.set(key, value)
  load()[key] = value
  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  local ok, text = pcall(vim.json.encode, data)
  if not ok then return end
  local fh = io.open(file, 'w')
  if fh then
    fh:write(text)
    fh:close()
  end
end

-- -----------------------------------------------------------------------------
--  The coloured bar behind the headings (md and org): <leader>oH
-- -----------------------------------------------------------------------------
function M.headingBand()
  return M.get('heading_band', true)
end

function M.setHeadingBand(on)
  M.set('heading_band', on)
  for _, name in ipairs({ 'pure.render-md', 'pure.render-org' }) do
    local module = package.loaded[name]
    if type(module) == 'table' and module.refresh then pcall(module.refresh, true) end
  end
end

function M.toggleHeadingBand()
  local on = not M.headingBand()
  M.setHeadingBand(on)
  vim.notify('Heading background ' .. (on and 'on' or 'off'))
end

-- -----------------------------------------------------------------------------
--  Put the saved state back
-- -----------------------------------------------------------------------------
local function restore()
  local function saved(key, apply)
    local value = M.get(key)
    if value ~= nil then pcall(apply, value) end
  end

  saved('number', function(v) vim.o.number = v end)
  saved('relativenumber', function(v) vim.o.relativenumber = v end)
  saved('signcolumn', function(v) vim.o.signcolumn = v end)
  saved('wrap', function(v) vim.o.wrap = v end)
  saved('laststatus', function(v) vim.o.laststatus = v end)
  saved('showtabline', function(v) vim.o.showtabline = v end)
  saved('diagnostics_virtual_text', function(v) vim.diagnostic.config({ virtual_text = v }) end)
  saved('copilot', function(v) vim.g.copilot_enabled = v end)
  saved('transparent', function(v) require('configs.functions').transparent = v end)
end

restore()

-- What needs a running UI or the LSP client: after startup.
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    local func = require('configs.functions')
    if func.transparent then pcall(func.applyTransparency) end
    local hints = M.get('inlay_hints')
    if hints ~= nil then pcall(vim.lsp.inlay_hint.enable, hints) end
  end,
})

vim.api.nvim_create_user_command('PureToggles', function(opts)
  if opts.args == 'reset' then
    data = {}
    pcall(os.remove, file)
    vim.notify('Saved toggles forgotten (the defaults apply on the next start)')
    return
  end
  vim.notify(vim.inspect(load()))
end, {
  nargs = '?',
  complete = function() return { 'reset' } end,
  desc = 'Show or reset the saved toggle states',
})

return M
