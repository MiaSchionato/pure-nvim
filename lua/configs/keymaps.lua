-- =============================================================================
--  Keymaps
-- =============================================================================
--  Leader is <Space>. The second key groups the action:
--
--    b  buffers        e  explore (pickers)   l  lsp             u  undotree
--    c  code           f  find (pickers)      n  new file        v  window focus
--    d  diagnostics    g  git                 o  toggles         w  tabs
--    j  jumps          s  split               t  terminal        x  execute
--    z  folds
--
--  No mapping may be a prefix of another one: Neovim then waits 'timeoutlen'
--  (500 ms) after the shorter key to see whether the longer one follows. That
--  is why every group has a full two-key form (<leader>ee, <leader>dd, ...)
--  instead of a bare <leader>e / <leader>d.
--
--  Non-leader keys come first: motions, text objects, surround.
-- =============================================================================

local map = vim.keymap.set
local func = require('configs.functions')
local fzf = require('pure.fuzzyUtils')
local sur = require('pure.surround')
local term = require('pure.terms')
local zet = require('pure.zettelkasten')
local lsp = vim.lsp.buf
local diag = vim.diagnostic

local opts = { noremap = true, silent = true }

vim.g.mapleader = ' '

local home = vim.uv.os_homedir():gsub("\\", "/") .. "/"

-- -----------------------------------------------------------------------------
--  Picker targets
-- -----------------------------------------------------------------------------
--  One table feeds explore (<leader>e_), find (<leader>f_) and new file
--  (<leader>n_), so each directory is written once instead of three times in
--  three near-identical blocks.
local dirs = {
  ['~'] = home,
  ['.'] = home .. '.config/',
  n     = home .. '.config/nvim/',
  m     = home .. 'iCloudDrive/Documents/Obsidian/Atlas/',
}

--- Run `picker` on `dir`, saying so when the directory simply is not there.
--- Without this the picker opens, the shell fails on a missing path, and the
--- floating window blinks shut with nothing explaining why.
local function inDir(picker, dir)
  return function()
    if vim.fn.isdirectory(dir) == 0 then
      return vim.notify('Directory does not exist: ' .. dir, vim.log.levels.WARN)
    end
    picker(dir)
  end
end

--- Explorer with a yazi front-end, falling back to the fzf one when yazi is
--- missing or fails to start.
local function explore(dir)
  return function()
    if vim.fn.isdirectory(dir) == 0 then
      return vim.notify('Directory does not exist: ' .. dir, vim.log.levels.WARN)
    end
    if not pcall(fzf.yaziExplorer, dir) then
      fzf.fuzzyExplorer(dir)
    end
  end
end

--- Directory of the current file, always with a trailing slash.
local function here()
  return vim.fn.expand('%:p:h') .. '/'
end

-- =============================================================================
--  Motions and basics
-- =============================================================================
map({ 'n', 'v', 'o' }, "gl", "$", func.getOpts(opts, "End of line"))
map({ 'n', 'v', 'o' }, "gh", "^", func.getOpts(opts, "First non-blank"))
map('n', "ge", "G", func.getOpts(opts, "Last line"))
map('n', "gj", "<C-d>", func.getOpts(opts, "Half page down"))
map('n', "gk", "<C-u>", func.getOpts(opts, "Half page up"))
map('n', '<C-f>', '<C-d>', func.getOpts(opts, "Half page down"))
map('n', '<C-p>', [[%]], func.getOpts(opts, "Jump to matching pair"))

map('n', "Y", "y$", func.getOpts(opts, "Yank to end of line"))
map('n', "U", "<C-r>", func.getOpts(opts, "Redo"))
map('n', "q;", "q:", func.getOpts(opts, "Command-line window"))
map('n', "J", "mzJ`z", func.getOpts(opts, "Join lines, keep cursor"))
map('n', "vv", 'viw', func.getOpts(opts, "Select word"))

-- '=', '+', '<' and '>' are deliberately left unmapped: in normal mode they are
-- operators (=ip, gg=G, >}, <ip), and mapping them to fold / single-line
-- actions threw those away. Folds live under <leader>z and za; a single line is
-- indented with the builtin << and >>.

-- Visual
map('v', "J", '5j', func.getOpts(opts, "Down 5 lines"))
map('v', "K", '5k', func.getOpts(opts, "Up 5 lines"))
map('v', "<", "<gv", func.getOpts(opts, "Outdent and reselect"))
map('v', ">", ">gv", func.getOpts(opts, "Indent and reselect"))

-- Move lines
--
-- Guarded by buffer type. The fuzzy pickers run fzf inside a terminal buffer,
-- and any moment spent in terminal-normal mode there (fuzzyLogic only calls
-- startinsert after a delay) meant the arrow keys fired this mapping instead of
-- reaching fzf -- failing with "E21: Cannot make changes, 'modifiable' is off"
-- and leaving the arrows apparently dead inside the picker.
--
-- Returning the key itself falls through to the builtin, because these mappings
-- are noremap: the returned key is not looked up again.
local function moveLine(keys, fallback)
  return function()
    if vim.bo.buftype ~= '' or not vim.bo.modifiable then
      return fallback
    end
    return keys
  end
end

local move_opts = { expr = true, silent = true, noremap = true }
map('n', "<up>", moveLine(":m .-2<CR>==", "<up>"), func.getOpts(move_opts, "Move line up"))
map('n', "<down>", moveLine(":m .+1<CR>==", "<down>"), func.getOpts(move_opts, "Move line down"))
map('v', "<up>", moveLine(":m '<-2<CR>gv=gv", "<up>"), func.getOpts(move_opts, "Move selection up"))
map('v', "<down>", moveLine(":m '>+1<CR>gv=gv", "<down>"), func.getOpts(move_opts, "Move selection down"))

-- =============================================================================
--  Text objects
-- =============================================================================
--  No expr here: with expr the rhs is evaluated as a Vimscript *expression*, so
--  'i[' parsed as the variable `i` and raised "E121: Undefined variable: i".
--  They stay noremap so 'i.' reaches the builtin 'is' (sentence) rather than the
--  'is' remapped just above it.
map({ 'x', 'o' }, 'is', 'i[', { desc = "Inner square brackets" })
map({ 'x', 'o' }, 'as', 'a[', { desc = "Outer square brackets" })
map({ 'x', 'o' }, 'ic', [[i{]], { desc = "Inner curly brackets" })
map({ 'x', 'o' }, 'ac', [[a}]], { desc = "Outer curly brackets" })
map({ 'x', 'o' }, 'i.', [[is]], { desc = "Inner sentence" })
map({ 'x', 'o' }, 'a.', [[as]], { desc = "Outer sentence" })

map({ 'x', 'o' }, 'iq', function()
  return "i" .. func.smartQuote()
end, { expr = true, desc = "Smart inner quotes" })

map({ 'x', 'o' }, 'aq', function()
  return "a" .. func.smartQuote()
end, { expr = true, desc = "Smart outer quotes" })

-- =============================================================================
--  Surround
-- =============================================================================
map("n", "s", function() sur.applySurround(false) end, { desc = "Surround word" })
map("v", "s", function() sur.applySurround(true) end, { desc = "Surround selection" })
-- Function surround is on S, not sf: sf made every s wait 500 ms. The builtin
-- S is a synonym for cc, so nothing is lost.
map("n", "S", function() sur.surroundFunction(false) end, { desc = "Surround with function" })
map("v", "S", function() sur.surroundFunction(true) end, { desc = "Surround with function" })
map("n", "ds", sur.deleteSurround, { desc = "Delete surround" })
map("n", "cs", sur.changeSurround, { desc = "Change surround" })

-- =============================================================================
--  Editing
-- =============================================================================
map('n', "<leader>p", '"*p', func.getOpts(opts, "Paste from clipboard"))
map("x", "<leader>p", [["_dP]], func.getOpts(opts, "Paste over without yanking"))
map({ 'n', 'v' }, "<leader>y", '"*y', func.getOpts(opts, "Yank to clipboard"))
map({ 'n', 'v' }, "<leader>D", '"_d', func.getOpts(opts, "Delete without yanking"))
map('n', "<leader>r", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
  { desc = "Rename word under cursor" })

map('v', "<leader>s", [[:s/\%V]], { desc = "Substitute inside selection" })
map('v', "<leader>n", [[:norm]], func.getOpts(opts, "Run normal command on selection"))
map('v', "<leader>v", [[:s/\v]], func.getOpts(opts, "Substitute, very magic"))

-- =============================================================================
--  Code
-- =============================================================================
map('n', "<leader>cc", fzf.CompilerCommand, func.getOpts(opts, "Run compiler command"))
map('n', "<leader>ct", 'oTODO:<esc>:normal gcc<cr>A', func.getOpts(opts, "Insert TODO comment"))
map('n', "<leader>cl", func.toggleHighlightSearch, func.getOpts(opts, "Clear search highlight"))
map("n", "<leader>xs", "<cmd>so<cr>", func.getOpts(opts, "Source current file"))
map("n", "<leader>xx", "<cmd>!chmod +x %<CR>", func.getOpts(opts, "Make file executable"))

-- =============================================================================
--  Windows, splits and tabs
-- =============================================================================
map('n', "<leader>vh", "<C-w>h", func.getOpts(opts, "Focus window left"))
map('n', "<leader>vj", "<C-w>j", func.getOpts(opts, "Focus window below"))
map('n', "<leader>vk", "<C-w>k", func.getOpts(opts, "Focus window above"))
map('n', "<leader>vl", "<C-w>l", func.getOpts(opts, "Focus window right"))

map('n', "<leader>sv", "<cmd>vsplit<CR>", func.getOpts(opts, "Split vertically"))
map('n', "<leader>sh", "<cmd>split<CR>", func.getOpts(opts, "Split horizontally"))
map('n', "<leader>+", "<cmd>resize +5<CR>", func.getOpts(opts, "Taller window"))
map('n', "<leader>-", "<cmd>resize -5<CR>", func.getOpts(opts, "Shorter window"))
map('n', "<leader>,", "<cmd>vertical resize +5<CR>", func.getOpts(opts, "Wider window"))
map('n', "<leader>.", "<cmd>vertical resize -5<CR>", func.getOpts(opts, "Narrower window"))

map('n', "<leader>wn", "<cmd>tabnew<CR>", func.getOpts(opts, "New tab"))
map('n', "<leader>wl", "<cmd>tabnext<CR>", func.getOpts(opts, "Next tab"))
map('n', "<leader>wh", "<cmd>tabprevious<CR>", func.getOpts(opts, "Previous tab"))
map('n', "<leader>wq", "<cmd>tabclose<CR>", func.getOpts(opts, "Close tab"))
map('n', "<leader>wo", "<cmd>tabonly<CR>", func.getOpts(opts, "Close other tabs"))

-- =============================================================================
--  Buffers
-- =============================================================================
map('n', "<leader>bn", "<cmd>bnext<CR>", func.getOpts(opts, "Next buffer"))
map('n', "<leader>bp", "<cmd>bprevious<CR>", func.getOpts(opts, "Previous buffer"))
map('n', "<leader>bq", "<cmd>bdelete<CR>", func.getOpts(opts, "Delete buffer"))
map('n', "<leader>bv", "<cmd>buffers<CR>", func.getOpts(opts, "List buffers"))
map('n', "<leader>bo", "<cmd>%bd|e#<cr>", func.getOpts(opts, "Close all but current"))

-- =============================================================================
--  Explore  (<leader>e)
-- =============================================================================
map('n', '<leader>ee', function() explore(here())() end, func.getOpts(opts, "Explore current directory"))
map('n', '<leader>E', explore(dirs['~']), func.getOpts(opts, "Explore home"))
map('n', '<leader>e.', explore(dirs['.']), func.getOpts(opts, "Explore ~/.config"))
map('n', '<leader>en', explore(dirs.n), func.getOpts(opts, "Explore nvim config"))
map('n', '<leader>em', explore(dirs.m), func.getOpts(opts, "Explore Obsidian vault"))

-- =============================================================================
--  Find  (<leader>f)
-- =============================================================================
map('n', '<leader><leader>', function() fzf.fuzzySearch(vim.fn.expand('%:p:h:h:h:h') .. '/') end,
  func.getOpts(opts, "Find files, four levels up"))
map('n', '<leader>ff', function() fzf.fuzzySearch(vim.fn.expand('%:p:h:h') .. '/') end,
  func.getOpts(opts, "Find files, two levels up"))
map('n', '<leader>f~', inDir(fzf.fuzzySearch, dirs['~']), func.getOpts(opts, "Find in home"))
map('n', '<leader>f.', inDir(fzf.fuzzySearch, dirs['.']), func.getOpts(opts, "Find in ~/.config"))
map('n', '<leader>fn', inDir(fzf.fuzzySearch, dirs.n), func.getOpts(opts, "Find in nvim config"))
map('n', '<leader>fa', inDir(fzf.fuzzySearch, dirs.m), func.getOpts(opts, "Find in Atlas, the Obsidian vault"))

map('n', "<leader>fg", function() fzf.fuzzyGrep(vim.fn.expand('%:p:h:h')) end, func.getOpts(opts, "Grep"))
map('n', "<leader>f/", fzf.fuzzyOldfiles, func.getOpts(opts, "Recent files"))
map('n', "<leader>fh", fzf.fuzzyHelp, func.getOpts(opts, "Help tags"))
map('n', "<leader>fb", fzf.fuzzyBuffers, func.getOpts(opts, "Buffers"))
map('n', "<leader>fj", fzf.fuzzyJump, func.getOpts(opts, "Jump list"))
map('n', '<leader>fc', fzf.fuzzyColorscheme, func.getOpts(opts, "Colorschemes"))

-- =============================================================================
--  New file  (<leader>n)
-- =============================================================================
map("n", "<leader>nf", function() fzf.NewFile(vim.fn.expand('%:p:h:h') .. '/') end,
  func.getOpts(opts, "New file, two levels up"))
map("n", "<leader>nh", inDir(fzf.NewFile, dirs['~']), func.getOpts(opts, "New file in home"))
map("n", "<leader>n.", inDir(fzf.NewFile, dirs['.']), func.getOpts(opts, "New file in ~/.config"))
map("n", "<leader>nn", inDir(fzf.NewFile, dirs.n), func.getOpts(opts, "New file in nvim config"))
map("n", "<leader>nm", inDir(fzf.NewFile, dirs.m), func.getOpts(opts, "New file in Obsidian vault"))
map('n', '<leader>nz', zet.insertTemplate, func.getOpts(opts, "Insert zettel template"))

-- =============================================================================
--  Git
-- =============================================================================
map('n', "<leader>gl", fzf.fuzzyGit, func.getOpts(opts, "Git log"))
map('n', "<leader>gg", fzf.fuzzyGitGrep, func.getOpts(opts, "Git grep"))
map('n', "<leader>gd", func.gitDiffToggle, func.getOpts(opts, "Toggle git diff"))

-- =============================================================================
--  LSP
-- =============================================================================
map('n', 'K', lsp.hover, func.getOpts(opts, "LSP hover"))
map('n', 'gd', lsp.definition, func.getOpts(opts, "LSP definition"))
-- No 'gr' here: it made the builtin grr/grn/gra/gri/grt/grx wait 500 ms, and
-- grr already lists references.
map('n', '<leader>la', lsp.code_action, func.getOpts(opts, "LSP code action"))
map('n', '<leader>lr', lsp.rename, func.getOpts(opts, "LSP rename"))
map('n', '<leader>ls', lsp.workspace_symbol, func.getOpts(opts, "LSP workspace symbols"))
map('i', '<up>', lsp.signature_help, func.getOpts(opts, "LSP signature help"))

-- =============================================================================
--  Diagnostics
-- =============================================================================
map('n', '<leader>dd', diag.open_float, func.getOpts(opts, "Show diagnostic"))
map('n', '[d', diag.get_prev, func.getOpts(opts, "Previous diagnostic"))
map('n', ']d', diag.get_next, func.getOpts(opts, "Next diagnostic"))

-- =============================================================================
--  Toggles  (<leader>o)
-- =============================================================================
--  Kept out of <leader>l so that group is LSP only; mixing them is what made
--  <leader>lr (rename) wait for <leader>lrn (relativenumber).
--  <leader>ox (transparency) is defined in themes/colorschemes.lua.
map('n', '<leader>od', func.toggleDiagnostics, func.getOpts(opts, "Toggle diagnostics"))
map('n', '<leader>oz', func.toggleZenMode, func.getOpts(opts, "Toggle zen mode"))
map('n', '<leader>os', func.toggleStatusline, func.getOpts(opts, "Toggle statusline"))
map('n', '<leader>ot', func.toggleTabline, func.getOpts(opts, "Toggle tabline"))
map('n', '<leader>oc', func.toggleSigncolumn, func.getOpts(opts, "Toggle signcolumn"))
map('n', '<leader>ow', '<cmd>set wrap!<cr>', func.getOpts(opts, "Toggle wrap"))
map('n', '<leader>oi', func.toggleInlayHints, func.getOpts(opts, "Toggle inlay hints"))
map('n', '<leader>op', func.toggleCopilot, func.getOpts(opts, "Toggle Copilot"))
map('n', '<leader>oh', func.toggleWordHighlight, func.getOpts(opts, "Toggle word highlight"))
map({ 'n', 'v' }, '<leader>or', func.toggleRelativenumber, func.getOpts(opts, "Toggle relativenumber"))
map({ 'n', 'v' }, '<leader>on', function()
  func.toggleNumber()
  func.toggleRelativenumber()
end, func.getOpts(opts, "Toggle line numbers"))

-- =============================================================================
--  Jumps, folds, undotree
-- =============================================================================
map('n', '<leader>jl', '<C-i>', func.getOpts(opts, "Jump forward"))
map('n', '<leader>jh', '<C-o>', func.getOpts(opts, "Jump back"))

map('n', '<leader>zz', 'za', func.getOpts(opts, "Toggle fold"))
map('n', '<leader>zo', 'zR', func.getOpts(opts, "Open all folds"))
map('n', '<leader>zc', 'zM', func.getOpts(opts, "Close all folds"))

map('n', '<leader>u', function()
  vim.cmd('packadd nvim.undotree')
  vim.cmd('Undotree')
end, func.getOpts(opts, "Undotree"))

-- =============================================================================
--  Terminal
-- =============================================================================
map('n', '<leader>tt', term.toggleTerminal, func.getOpts(opts, "Toggle terminal"))
map('n', '<leader>tg', function() term.toggleTerminal("gemini") end,
  func.getOpts(opts, "Toggle Gemini terminal"))
map('t', '<S-esc>', [[<C-\><C-n>]], func.getOpts(opts, "Leave terminal mode"))
--  <S-Esc> only reaches Neovim on terminals reporting it as a distinct key
--  (CSI-u style); most send a plain <Esc>. <Esc><Esc> works everywhere and still
--  leaves a single <Esc> for the shell and for TUIs running inside it.
map('t', '<Esc><Esc>', [[<C-\><C-n>:q<CR>]], func.getOpts(opts, "Close terminal"))

-- =============================================================================
--  Debug
-- =============================================================================
map({ 'n', 'v' }, '<leader>in', ':Inspect<cr>', func.getOpts(opts, "Inspect highlight under cursor"))
map('v', '<leader>ldb', 'y:lua print(<C-r>")<cr>', func.getOpts(opts, "Print selection via lua"))

-- =============================================================================
--  Completion and snippets
-- =============================================================================
--  Deferred: the <CR> mapping needs copilot.vim's autoload on the runtimepath,
--  which vim.pack only guarantees after this file has run.
vim.schedule(function()
  map('i', '<tab>', function()
    if vim.fn.pumvisible() == 1 then
      return "<C-n>"
    end
    if func.isBlank() then
      return "<tab>"
    end
    if vim.snippet.active({ direction = 1 }) then
      return "<cmd>lua vim.snippet.jump(1)<cr>"
    end
    return "<right>"
  end, { expr = true, replace_keycodes = true, desc = "Complete / jump forward" })

  map('i', '<S-tab>', function()
    if vim.fn.pumvisible() == 1 then
      return "<C-p>"
    end
    if func.isBlank() then
      return "<S-tab>"
    end
    -- was `direction = 1` here too, so the backward jump asked whether a
    -- *forward* jump was possible.
    if vim.snippet.active({ direction = -1 }) then
      return "<cmd>lua vim.snippet.jump(-1)<cr>"
    end
    return "<left>"
  end, { expr = true, replace_keycodes = true, desc = "Complete / jump back" })

  map('i', '<CR>', 'copilot#Accept("\\<CR>")', {
    expr = true,
    replace_keycodes = false,
    desc = "Accept Copilot suggestion",
  })
end)
