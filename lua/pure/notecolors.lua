-- =============================================================================
--  Note colours: the heading and task colours of the rendered notes
-- =============================================================================
--  Shared by the Markdown view (pure/render-md.lua) and the org
--  view (pure/render-org.lua), so a note reads the same in both.
--
--  The colours follow the colorscheme: each group is a link to a group every
--  theme defines, so changing the theme changes them. The one exception is the
--  Ethereal theme, whose colours are exactly the ones of the Emacs look (my/heading-colours
--  in ethereal-look.el); there they are fixed values.
--
--    @markup.heading.1..6.markdown   the theme's own group when it has one, else Title, Directory, ...
--    PureNoteTask<State>             Todo, Done, Progress, Important, Deferred, Cancelled
--
--  vim.g.pure_md_heading_colors (a list of six colours) replaces the heading colours in any theme.
-- =============================================================================

local M = {}

-- Ethereal: the Emacs look. Headings blue, purple, pink, cyan, green, orange.
local ethereal_headings = { '#7d82d9', '#c89dc1', '#faaaa9', '#a3bfd1', '#92a593', '#F99957' }
local ethereal_tasks = {
  Todo = '#8b949e',      -- [ ] grey
  Done = '#3fb950',      -- [x] green
  Progress = '#58a6ff',  -- [~] blue
  Important = '#f85149', -- [!] red
  Deferred = '#a371f7',  -- [>] purple
  Cancelled = '#6e7681', -- [-] dark grey
}

-- What a theme without its own groups links to.
local heading_links = { 'Title', 'Directory', 'Type', 'Special', 'Identifier', 'Constant' }
local task_links = {
  Todo = 'Comment',
  Done = 'DiagnosticOk',
  Progress = 'DiagnosticInfo',
  Important = 'DiagnosticError',
  Deferred = 'Statement',
  Cancelled = 'NonText',
}

M.task_states = { 'Todo', 'Done', 'Progress', 'Important', 'Deferred', 'Cancelled' }

local function isEthereal()
  return (vim.g.colors_name or ''):lower() == 'ethereal'
end

--- Define the groups for the current colorscheme. Call it again after a
--- colorscheme change (it does not use `default`: it replaces what was there).
function M.apply()
  local custom = vim.g.pure_md_heading_colors
  local colours = custom
  if colours == nil and isEthereal() then colours = ethereal_headings end

  for level = 1, 6 do
    local name = '@markup.heading.' .. level .. '.markdown'
    if colours then
      vim.api.nvim_set_hl(0, name, { fg = colours[level] or colours[#colours], bold = true })
    elseif next(vim.api.nvim_get_hl(0, { name = name, link = false })) == nil then
      vim.api.nvim_set_hl(0, name, { link = heading_links[level] })
    end
  end

  for _, state in ipairs(M.task_states) do
    local name = 'PureNoteTask' .. state
    if isEthereal() then
      vim.api.nvim_set_hl(0, name, { fg = ethereal_tasks[state] })
    else
      vim.api.nvim_set_hl(0, name, { link = task_links[state] })
    end
  end
end

return M
