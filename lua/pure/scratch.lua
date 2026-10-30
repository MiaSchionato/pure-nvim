-- =============================================================================
--  Scratch note  (Emacs' *scratch*, kept in a file)
-- =============================================================================
--  One note for whatever has no other place: a number, a command to try, a
--  thought. It is the same buffer in every tab and window, as *scratch* is in
--  Emacs, and a new tab opens on it. Unlike *scratch* it is saved: to a file in
--  stdpath('data') that is written whenever you stop typing, leave the buffer
--  or lose focus, so closing Neovim loses nothing.
--
--    <leader>ns          open it in this window
--    n on the dashboard  the same
--    new tab             opens on it (:tabnew, <leader>wn)
--    :Scratch            open it         :Scratch clear   empty it
--
--  Settings (configs.lua):
--    vim.g.pure_scratch_filetype  'org' (default): the notes of Flora; any filetype works
--    vim.g.pure_scratch_file      the path (default stdpath('data')/scratch.<ext>)
--    vim.g.pure_scratch_message   the text of a new, empty note
--                                 (default: a short comment, in the syntax of the filetype)
--    vim.g.pure_newtab            'scratch' (default) | 'dashboard' | 'empty': what a new tab shows
-- =============================================================================

local M = {}

local EXT = { org = 'org', markdown = 'md', text = 'txt', lua = 'lua' }
local COMMENT = { org = '# ', markdown = '<!-- %s -->', lua = '-- ', text = '' }

local function filetype()
  return vim.g.pure_scratch_filetype or 'org'
end

function M.path()
  if vim.g.pure_scratch_file then return vim.fs.normalize(vim.g.pure_scratch_file) end
  return vim.fn.stdpath('data') .. '/scratch.' .. (EXT[filetype()] or 'txt')
end

local function message()
  if vim.g.pure_scratch_message then return vim.g.pure_scratch_message end
  local text = 'Scratch: notes with no other place. Saved on its own; the same in every tab.'
  local c = COMMENT[filetype()] or ''
  if c:find('%%s') then return c:format(text) end
  return c .. text
end

--- The buffer of the scratch file, if it is loaded.
function M.buf()
  local buf = vim.fn.bufnr(M.path())
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then return buf end
end

local function attach(buf)
  if vim.b[buf].pure_scratch then return end
  vim.b[buf].pure_scratch = true
  local group = vim.api.nvim_create_augroup('PureScratch' .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave', 'BufLeave', 'FocusLost', 'VimLeavePre' }, {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
        vim.api.nvim_buf_call(buf, function() vim.cmd('silent! noautocmd update') end)
      end
    end,
  })
end

--- Show the scratch note in `win` (default: the current window).
function M.open(win)
  win = win or vim.api.nvim_get_current_win()
  local path = M.path()
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local fresh = vim.fn.filereadable(path) == 0
  vim.api.nvim_win_call(win, function() vim.cmd('silent edit ' .. vim.fn.fnameescape(path)) end)
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype == '' or vim.bo[buf].filetype ~= filetype() then vim.bo[buf].filetype = filetype() end
  if fresh and vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == '' then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { message(), '', '' })
    vim.api.nvim_win_set_cursor(win, { 3, 0 })
    vim.api.nvim_buf_call(buf, function() vim.cmd('silent! noautocmd write') end)
  end
  attach(buf)
  return buf
end

function M.clear()
  local buf = M.buf()
  if buf then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { message(), '', '' })
    vim.api.nvim_buf_call(buf, function() vim.cmd('silent! noautocmd write') end)
  else
    os.remove(M.path())
  end
  vim.notify('Scratch note emptied')
end

-- A new tab opens on the scratch note (or the dashboard, see vim.g.pure_newtab). Looked at once the
-- command that opened the tab is done: :tabnew file, :tab help or a plugin that fills its tab are left alone.
vim.api.nvim_create_autocmd('TabNewEntered', {
  group = vim.api.nvim_create_augroup('PureScratchNewTab', { clear = true }),
  callback = function()
    local mode = vim.g.pure_newtab or 'scratch'
    local tab = vim.api.nvim_get_current_tabpage()
    vim.schedule(function()
      if not vim.api.nvim_tabpage_is_valid(tab) or tab ~= vim.api.nvim_get_current_tabpage() then return end
      if mode == 'dashboard' then
        require('pure.dashboard').drawInBlankTab(tab)
      elseif mode == 'scratch' then
        local win = vim.api.nvim_get_current_win()
        for _, other in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          if other ~= win and vim.api.nvim_win_get_config(other).relative == '' then return end
        end
        local buf = vim.api.nvim_win_get_buf(win)
        local blank = vim.api.nvim_buf_get_name(buf) == '' and vim.bo[buf].buftype == ''
          and not vim.bo[buf].modified and vim.api.nvim_buf_line_count(buf) == 1
          and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
        if blank then M.open(win) end
      end
    end)
  end,
})

vim.api.nvim_create_user_command('Scratch', function(opts)
  if opts.args == 'clear' then M.clear() else M.open() end
end, {
  nargs = '?',
  complete = function() return { 'clear' } end,
  desc = 'Open the scratch note (clear: empty it)',
})

return M
