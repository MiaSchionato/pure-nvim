-- =================================================================
--  Keymaps
-- =============================================================================
--  Leader is <Space>. The second key groups the action:
--
--    a  llms (ai)
--    b  buffers        e  explore (pickers)   l  lsp             u  undotree
--    c  code           f  find (pickers)      n  new file/folder v  vault (notes)
--    d  diagnostics    g  git                 o  toggles         w  tabs, window view (wv_)
--    m  manim
--    j  jumps          s  split               t  term, todoist   x  checkbox state (notes)
--    z  folds
--
--  <leader>v was window focus; it became the vault's group (Improvment.md in
--  the vault asked for it) and window focus moved to <leader>wv h/j/k/l.
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

-- Group names shown by the key hint window (pure/keyhint.lua) after <leader>.
vim.g.pure_keyhint_groups = {
  ['<leader>a'] = 'AI (LLMs)',
  ['<leader>b'] = 'Buffers',
  ['<leader>c'] = 'Code',
  ['<leader>d'] = 'Diagnostics',
  ['<leader>e'] = 'Explore',
  ['<leader>f'] = 'Find',
  ['<leader>g'] = 'Git',
  ['<leader>j'] = 'Jumps',
  ['<leader>l'] = 'LSP',
  ['<leader>m'] = 'Manim',
  ['<leader>n'] = 'New file / folder',
  ['<leader>o'] = 'Toggles',
  ['<leader>s'] = 'Split',
  ['<leader>t'] = 'Terminal, Todoist',
  ['<leader>v'] = 'Vault',
  ['<leader>w'] = 'Tabs, window view',
  ['<leader>wv'] = 'Window focus',
  ['<leader>x'] = 'Checkbox state',
  ['<leader>z'] = 'Folds',
}

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
  -- The Obsidian vault, as set up in pure/zettelkasten.lua (asked for on a
  -- fresh install, or vim.g.pure_vault). A function: it may be chosen only
  -- after this file has run.
  v     = function()
    local vault = zet.vaultPath()
    return vault and (vault .. '/') or nil
  end,
}

--- Directories relative to the current file. Functions, not strings: a string
--- would be expanded once at startup and keep pointing at the first file.
local file = {
  p      = function() return vim.fn.expand('%:p:h') .. '/' end,
  pp     = function() return vim.fn.expand('%:p:h:h') .. '/' end,
  ["3p"] = function() return vim.fn.expand('%:p:h:h:h') .. '/' end,
  ["4p"] = function() return vim.fn.expand('%:p:h:h:h:h') .. '/' end,
}

--- Run `picker` on `dir`, saying so when the directory simply is not there.
--- Without this the picker opens, the shell fails on a missing path, and the
--- floating window blinks shut with nothing explaining why.
local function inDir(picker, dir)
  return function()
    -- Not `type(dir) == 'function' and dir() or dir`: when dir() returns nil
    -- (no vault yet) that idiom falls through to `or dir`, the function itself.
    local path = dir
    if type(dir) == 'function' then path = dir() end
    if not path then
      return vim.notify('No Obsidian vault set: run :ZettelVault', vim.log.levels.WARN)
    end
    if vim.fn.isdirectory(path) == 0 then
      return vim.notify('Directory does not exist: ' .. path, vim.log.levels.WARN)
    end
    picker(path)
  end
end

--- Toggle an oil float on `dir` (a path, or a function returning one).
---
--- The same key closes the float again. That check comes first: inside oil the
--- buffer name is an oil:// URL, so here() would yield a path that isdirectory()
--- rejects and the key would warn instead of closing.
---
--- oil is required lazily: plugins/oil.lua loads after this file, so the module
--- is not on the runtimepath yet when these mappings are defined.
---
local function explore(dir)
  return function()
    local oil = require('oil')
    if vim.w.is_oil_win then
      return oil.close()
    end
    -- Not `type(dir) == 'function' and dir() or dir`: when dir() returns nil
    -- (no vault yet) that idiom falls through to `or dir`, the function itself.
    local path = dir
    if type(dir) == 'function' then path = dir() end
    if not path then
      return vim.notify('No Obsidian vault set: run :ZettelVault', vim.log.levels.WARN)
    end
    if vim.fn.isdirectory(path) == 0 then
      return vim.notify('Directory does not exist: ' .. path, vim.log.levels.WARN)
    end
    oil.open_float(path)
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
-- Tab indents in visual mode only (Improvment.md: indenting belongs to
-- normal / visual, never insert). Not in normal mode: a terminal sends the
-- same key for <Tab> and <C-i>, so it would take away "jump forward". There
-- >> and << indent.
map('x', "<Tab>", ">gv", func.getOpts(opts, "Indent and reselect"))
map('x', "<S-Tab>", "<gv", func.getOpts(opts, "Outdent and reselect"))

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
-- "+ is the system clipboard everywhere; "* is only the same on Windows (on
-- Linux it is the primary selection, not Ctrl+C / Ctrl+V).
map('n', "<leader>p", '"+p', func.getOpts(opts, "Paste from clipboard"))
map("x", "<leader>p", [["_dP]], func.getOpts(opts, "Paste over without yanking"))
map({ 'n', 'v' }, "<leader>y", '"+y', func.getOpts(opts, "Yank to clipboard"))
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
-- Under code rather than <leader>x, which cycles checkbox states in notes;
-- a bare <leader>x next to xs / xx would wait for the second key.
map("n", "<leader>cs", "<cmd>so<cr>", func.getOpts(opts, "Source current file"))
map("n", "<leader>cx", "<cmd>!chmod +x %<CR>", func.getOpts(opts, "Make file executable"))

-- =============================================================================
--  Windows, splits and tabs
-- =============================================================================
-- Window view: <leader>wv + direction. Moved from <leader>v_, which is now the
-- vault's group. Under <leader>w beside the tabs; no bare <leader>wv mapping,
-- so wvh/wvj/... never wait on a shorter key.
map('n', "<leader>wvh", "<C-w>h", func.getOpts(opts, "Focus window left"))
map('n', "<leader>wvj", "<C-w>j", func.getOpts(opts, "Focus window below"))
map('n', "<leader>wvk", "<C-w>k", func.getOpts(opts, "Focus window above"))
map('n', "<leader>wvl", "<C-w>l", func.getOpts(opts, "Focus window right"))

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
map('n', '<leader>ee', explore(here), func.getOpts(opts, "Explore current directory"))
map('n', '<leader>E', explore(dirs['~']), func.getOpts(opts, "Explore home"))
map('n', '<leader>e.', explore(dirs['.']), func.getOpts(opts, "Explore ~/.config"))
map('n', '<leader>en', explore(dirs.n), func.getOpts(opts, "Explore nvim config"))
map('n', '<leader>ev', explore(dirs.v), func.getOpts(opts, "Explore Obsidian vault"))

-- =============================================================================
--  Find  (<leader>f)
-- =============================================================================
map('n', '<leader><leader>', function() fzf.fuzzySearch(file["4p"]()) end,
  func.getOpts(opts, "Find files, four levels up"))
map('n', '<leader>ff', function() fzf.fuzzySearch(file.pp()) end,
  func.getOpts(opts, "Find files, two levels up"))
map('n', '<leader>f~', inDir(fzf.fuzzySearch, dirs['~']), func.getOpts(opts, "Find in home"))
map('n', '<leader>f.', inDir(fzf.fuzzySearch, dirs['.']), func.getOpts(opts, "Find in ~/.config"))
map('n', '<leader>fn', inDir(fzf.fuzzySearch, dirs.n), func.getOpts(opts, "Find in nvim config"))
map('n', '<leader>fv', inDir(fzf.fuzzySearch, dirs.v), func.getOpts(opts, "Find in Atlas, the Obsidian vault"))

map('n', "<leader>fe", function() inDir(fzf.fuzzyExplorer, here())() end,
  func.getOpts(opts, "fzf explorer, current directory"))
map('n', "<leader>fg", function() fzf.fuzzyGrep(vim.fn.expand('%:p:h:h')) end, func.getOpts(opts, "Grep"))
map('n', "<leader>f/", fzf.fuzzyOldfiles, func.getOpts(opts, "Recent files"))
map('n', "<leader>fh", fzf.fuzzyHelp, func.getOpts(opts, "Help tags"))
map('n', "<leader>fb", fzf.fuzzyBuffers, func.getOpts(opts, "Buffers"))
map('n', "<leader>fj", fzf.fuzzyJump, func.getOpts(opts, "Jump list"))
map('n', '<leader>fl', function() require('pure.notes').backlinks() end, func.getOpts(opts, "Notes linking here (backlinks, also <leader>vb)"))
map('n', '<leader>fc', fzf.fuzzyColorscheme, func.getOpts(opts, "Colorschemes"))

-- =============================================================================
--  New file / folder  (<leader>n)
-- =============================================================================
--  Only <leader>nf asks for a folder. The others already name it, so they
--  go straight there: they ask for the file name, or, with
--  vim.g.pure_new_file_ask_name = false (configs.lua), open an unnamed buffer
--  working in that folder. They used to open a folder picker every time.
map("n", "<leader>nf", function() fzf.NewFile(vim.fn.expand('%:p:h:h') .. '/') end,
  func.getOpts(opts, "New file, pick the folder (from two levels up)"))
map("n", "<leader>ne", function() fzf.NewFileIn(here()) end, func.getOpts(opts, "New file here"))
map("n", "<leader>nh", inDir(fzf.NewFileIn, dirs['~']), func.getOpts(opts, "New file in home"))
map("n", "<leader>n.", inDir(fzf.NewFileIn, dirs['.']), func.getOpts(opts, "New file in ~/.config"))
map("n", "<leader>nn", inDir(fzf.NewFileIn, dirs.n), func.getOpts(opts, "New file in nvim config"))
-- The same as <leader>vn: a note in the vault's inbox, asking only its name.
map("n", "<leader>nv", zet.newNote, func.getOpts(opts, "New note in the vault's inbox"))
map("n", "<leader>nd", function() fzf.NewFolder(here()) end, func.getOpts(opts, "New folder here"))
-- <leader>nt (template) and <leader>nr (rename note) moved to <leader>vt and
-- <leader>vr: they act on a note, they do not make a new file.

-- =============================================================================
--  Manim  (<leader>m, pure/manim.lua)
-- =============================================================================
map('n', '<leader>mm', function() require('pure.manim').toggle() end,
  func.getOpts(opts, "Preview the scene, again on every save (toggle)"))
map('n', '<leader>ms', function() require('pure.manim').pick() end, func.getOpts(opts, "Preview another scene"))
map({ 'n', 'x' }, '<leader>mp', function() require('pure.manim').part() end,
  func.getOpts(opts, "Preview only this part (selection, or the block under the cursor)"))
map('n', '<leader>mf', function() require('pure.manim').frame() end, func.getOpts(opts, "Picture of the scene at this line"))
map('n', '<leader>mi', function() require('pure.manim').interactive() end,
  func.getOpts(opts, "Live window at this line: mouse camera, Python shell (toggle)"))

-- =============================================================================
--  Vault  (<leader>v, pure/zettelkasten.lua and pure/notes.lua)
-- =============================================================================
--  Everything that works on the Obsidian vault, in one group. <leader>ev,
--  <leader>fv, <leader>fl and <leader>gv stay too, beside the other folders
--  of their group.
local function notes(fn)
  return function() require('pure.notes')[fn]() end
end
map('n', '<leader>vn', zet.newNote, func.getOpts(opts, "New note (inbox, asks the name only)"))
map('n', '<leader>vN', zet.newNoteFromTemplate, func.getOpts(opts, "New note from a template (born in its folder)"))
map('n', '<leader>vt', zet.insertTemplate, func.getOpts(opts, "Apply a template"))
map('n', '<leader>vd', zet.trashNote, func.getOpts(opts, "Delete note (to the vault's trash)"))
map('n', '<leader>vr', notes('rename'), func.getOpts(opts, "Rename note, fix links to it"))
map('n', '<leader>vb', notes('backlinks'), func.getOpts(opts, "Backlinks (notes linking here)"))
map('n', '<leader>ve', explore(dirs.v), func.getOpts(opts, "Explore the vault"))
map('n', '<leader>vf', inDir(fzf.fuzzySearch, dirs.v), func.getOpts(opts, "Find a note"))
map('n', '<leader>vg', inDir(fzf.fuzzyGrep, dirs.v), func.getOpts(opts, "Grep the vault"))
map('n', '<leader>vs', "<cmd>VaultSync<cr>", func.getOpts(opts, "Sync the vault (git)"))

-- =============================================================================
--  LLMs: Claude, Ollama, agy  (<leader>a, pure/llm.lua)
-- =============================================================================
local function llm(fn)
  return function() require('pure.llm')[fn]() end
end
map({ 'n', 'x' }, '<leader>ai', llm('write'), func.getOpts(opts, "Write here (visual: rewrite)"))
map({ 'n', 'x' }, '<leader>aa', llm('ask'), func.getOpts(opts, "Chat: show / hide (like <leader>tt)"))
map({ 'n', 'x' }, '<leader>ac', llm('review'), func.getOpts(opts, "Review the code"))
map({ 'n', 'x' }, '<leader>ar', llm('repeatLast'), func.getOpts(opts, "Repeat the last request"))
map('n', '<leader>ah', llm('history'), func.getOpts(opts, "Past answers"))
map('n', '<leader>as', llm('stop'), func.getOpts(opts, "Stop"))
-- Frees the GPU without quitting (Improvment.md): what quitting does.
map('n', '<leader>aq', llm('shutdown'), func.getOpts(opts, "Quit the AI: stop, unload models, close Ollama"))
map('n', '<leader>am', llm('selectModel'), func.getOpts(opts, "Select model (Ollama / Claude / agy)"))
map('n', '<leader>at', llm('toggleThinking'), func.getOpts(opts, "Thinking of <leader>ai (show / hide)"))
-- The file about you that every request reads (outside any git repository).
map('n', '<leader>au', function()
  local path = require('pure.llm').userContextFile()
  if not path then return vim.notify('User context is off (vim.g.pure_llm_user_context = false)') end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end, func.getOpts(opts, "User context file (what the LLMs know about you)"))
map({ 'n', 'x' }, '<leader>ax', llm('pickAction'), func.getOpts(opts, "Actions (claude/ folder of the vault)"))
map('n', '<leader>ab', llm('runBlockAtCursor'), func.getOpts(opts, "Run the ```llm block under the cursor"))
map('n', '<leader>ad', function() require('pure.llm').runNamed('Nota do dia') end,
  func.getOpts(opts, "Daily note: next step and the measured day"))
map('n', '<leader>aw', function() require('pure.llm').runNamed('Nota da semana') end,
  func.getOpts(opts, "Weekly note: the week in one place"))
map('n', '<leader>aj', function() require('pure.llm').chatWith('job') end,
  func.getOpts(opts, "Job assistant: the chat with the /job persona"))

-- =============================================================================
--  Git
-- =============================================================================
-- pure/git.lua: required on use, like the other pure modules' keys.
local git = function(fn) return function(...) return require('pure.git')[fn](...) end end

map('n', "<leader>gl", fzf.fuzzyGit, func.getOpts(opts, "Git log"))
map('n', "<leader>gg", fzf.fuzzyGitGrep, func.getOpts(opts, "Git grep"))
map('n', "<leader>gd", func.gitDiffToggle, func.getOpts(opts, "Toggle git diff"))
map('n', "<leader>gs", git('status'), func.getOpts(opts, "Git status (interactive)"))
map('n', "<leader>ga", git('addFile'), func.getOpts(opts, "Git add current file"))
map('n', "<leader>gA", git('addAll'), func.getOpts(opts, "Git add all"))
map('n', "<leader>gu", git('unstageFile'), func.getOpts(opts, "Git unstage current file"))
map('n', "<leader>gr", git('restoreFile'), func.getOpts(opts, "Git discard changes to current file"))
map('n', "<leader>gc", git('commit'), func.getOpts(opts, "Git commit"))
map('n', "<leader>gp", git('push'), func.getOpts(opts, "Git push"))
map('n', "<leader>gP", git('pull'), func.getOpts(opts, "Git pull"))
map('n', "<leader>gb", git('blameLine'), func.getOpts(opts, "Git blame current line"))
map('n', "<leader>gB", git('switchBranch'), func.getOpts(opts, "Git switch branch"))
map('n', "<leader>gv", "<cmd>VaultSync<cr>", func.getOpts(opts, "Git Vault Sync"))

-- =============================================================================
--  LSP
-- =============================================================================
-- On a link, K follows it (pure/notes.lua): in markdown any link, elsewhere
-- only web links, since [[x]] in code is not a note. Else LSP hover.
map('n', 'K', function()
  if require('pure.notes').follow(vim.bo.filetype ~= 'markdown') then return end
  lsp.hover()
end, func.getOpts(opts, "Follow link, else LSP hover"))
map('n', 'gd', lsp.definition, func.getOpts(opts, "LSP definition"))
-- No 'gr' here: it made the builtin grr/grn/gra/gri/grt/grx wait 500 ms, and
-- grr already lists references.
map('n', '<leader>la', lsp.code_action, func.getOpts(opts, "LSP code action"))
map('n', '<leader>lr', lsp.rename, func.getOpts(opts, "LSP rename"))
map('n', '<leader>ls', lsp.workspace_symbol, func.getOpts(opts, "LSP workspace symbols"))
-- Only where a language server can answer: in markdown (no such server) it
-- raised 'method "textDocument/signatureHelp" is not supported' on every
-- press (Improvment.md). Elsewhere <Up> moves up, as it would unmapped.
map('i', '<up>', function()
  if #vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/signatureHelp' }) > 0 then
    return "<Cmd>lua vim.lsp.buf.signature_help()<CR>"
  end
  return "<Up>"
end, { expr = true, replace_keycodes = true, silent = true, desc = "LSP signature help, else up" })

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
map('n', '<leader>h', func.toggleWordHighlight, func.getOpts(opts, "Toggle word highlight (short form)"))
map({ 'n', 'v' }, '<leader>or', func.toggleRelativenumber, func.getOpts(opts, "Toggle relativenumber"))
map('n', '<leader>om', function() require('pure.mdview').toggle() end, func.getOpts(opts, "Toggle markdown rendering"))
map({ 'n', 'v' }, '<leader>on', function()
  func.toggleNumber()
  func.toggleRelativenumber()
end, func.getOpts(opts, "Toggle line numbers"))

-- =============================================================================
--  Jumps, folds, undotree
-- =============================================================================
map('n', '<leader>jl', '<C-i>', func.getOpts(opts, "Jump forward"))
map('n', '<leader>jh', '<C-o>', func.getOpts(opts, "Jump back"))

-- Only a fold that starts on this line (pure/folding.lua): za closed the fold
-- around the line, which in a markdown list was the whole section.
map('n', '<leader>zz', function() require('pure.folding').toggleHere() end,
  func.getOpts(opts, "Toggle the fold starting here"))
-- Tasks by state (Improvment.md); the same key again, or <leader>zr, goes back.
map('n', '<leader>zt', function() require('pure.folding').tasks('done') end,
  func.getOpts(opts, "Fold done tasks (see what is left)"))
map('n', '<leader>zT', function() require('pure.folding').tasks('open') end,
  func.getOpts(opts, "Fold open tasks (see what is done)"))
-- The same on Vim's own z prefix, without <leader> (Improvment.md). They
-- replace Vim's zt / zz ("scroll this line to the top / middle"), which the
-- owner of this configuration does not use and asked to give up.
map('n', 'zt', function() require('pure.folding').tasks('done') end,
  func.getOpts(opts, "Fold done tasks (see what is left)"))
map('n', 'zT', function() require('pure.folding').tasks('open') end,
  func.getOpts(opts, "Fold open tasks (see what is done)"))
map('n', 'zz', function() require('pure.folding').toggleHere() end,
  func.getOpts(opts, "Toggle the fold starting here"))
-- Folds are made automatically (treesitter, or indentation), and those
-- methods refuse zf. Folding a selection by hand switches the window to manual
-- folds -- the automatic ones stay -- and <leader>zr goes back to automatic.
map('x', '<leader>zf', function()
  vim.wo.foldmethod = 'manual'
  vim.cmd('normal! zf')
end, func.getOpts(opts, "Fold selection"))
map('n', '<leader>zd', function()
  local ok, err = pcall(vim.cmd, 'normal! zd')
  if not ok then vim.notify(err:gsub('^.-E%d+: ', ''), vim.log.levels.WARN) end
end, func.getOpts(opts, "Delete fold"))
map('n', '<leader>zr', function() require('pure.folding').auto() end,
  func.getOpts(opts, "Reset folds to automatic"))
-- One key for zR / zM: opens everything if any fold is closed, otherwise
-- closes them all.
map('n', '<leader>za', function()
  for lnum = 1, vim.fn.line('$') do
    if vim.fn.foldclosed(lnum) ~= -1 then return vim.cmd('normal! zR') end
  end
  vim.cmd('normal! zM')
end, func.getOpts(opts, "Toggle all folds"))

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
--  Todoist  (<leader>t, beside the terminals)
-- =============================================================================
map('n', '<leader>td', '<cmd>Todoist<cr>', func.getOpts(opts, "Todoist all tasks"))
map('n', '<leader>tD', '<cmd>Todoist today | overdue<cr>', func.getOpts(opts, "Todoist today and overdue"))

-- =============================================================================
--  Completion and snippets
-- =============================================================================
--  Deferred: the <CR> mapping needs copilot.vim's autoload on the runtimepath,
--  which vim.pack only guarantees after this file has run.
vim.schedule(function()
  --  Tab in insert mode (as asked in the vault's Improvment.md, second
  --  round: Tab must not indent, and walks the suggestions). In order:
  --    the completion menu open           next suggestion (<CR> takes it)
  --    closers right after the cursor     step past all of them: "[[a|]]" -> "[[a]]|"
  --    a snippet with a next field        jump to it
  --    anything else                      a plain Tab, the one way left to
  --                                       type one (<C-v><Tab> works too)
  --  Tab never opens the menu itself ('autocomplete' opens it as you type):
  --  returning <C-n> from this mapping with the menu closed crashed Neovim
  --  0.12.5 (segfault) together with 'lazyredraw' and 'autocomplete'; it
  --  reproduces with --clean, so it is Neovim's bug, not this config's.
  --  The menu wins over a closer (third round, "option b"): inside [[...]]
  --  the ]] is always there, so with the closer first Tab could never pick a
  --  link. Esc closes the menu (below), then Tab steps past the pair.
  --  The first version of this indented a markdown list item (<C-t>); that
  --  was taken out on request. >> and << in normal mode still indent.
  local closers = "[%)%]}>\"'`]"
  local function closersAhead()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local ahead = vim.api.nvim_get_current_line():sub(col + 1)
    return #(ahead:match('^' .. closers .. '+') or '')
  end

  -- Right after a list item's marker ("- [ ] |", "- |", "1. |"), where the
  -- item is still empty: Tab / S-Tab make it a sub-item / take it back out
  -- (Improvment.md, fourth round). Anywhere else Tab never indents.
  local function atItemStart()
    local it = require('pure.lists').item()
    return it ~= nil and vim.api.nvim_win_get_cursor(0)[2] == it.start
  end

  map('i', '<tab>', function()
    if atItemStart() then
      return (vim.fn.pumvisible() == 1 and "<C-e>" or "") .. "<C-t>"
    end
    if vim.fn.pumvisible() == 1 then return "<C-n>" end
    local n = closersAhead()
    if n > 0 then return string.rep("<right>", n) end
    if vim.snippet.active({ direction = 1 }) then
      return "<cmd>lua vim.snippet.jump(1)<cr>"
    end
    return "<tab>"
  end, { expr = true, replace_keycodes = true, desc = "Indent an empty list item / past closing pair / next suggestion / snippet jump" })

  --  Mirrors Tab backwards: previous suggestion, snippet back; else the builtin.
  map('i', '<S-tab>', function()
    if atItemStart() then
      return (vim.fn.pumvisible() == 1 and "<C-e>" or "") .. "<C-d>"
    end
    if vim.fn.pumvisible() == 1 then return "<C-p>" end
    -- was `direction = 1` here too, so the backward jump asked whether a
    -- *forward* jump was possible.
    if vim.snippet.active({ direction = -1 }) then
      return "<cmd>lua vim.snippet.jump(-1)<cr>"
    end
    return "<S-tab>"
  end, { expr = true, replace_keycodes = true, desc = "Outdent an empty list item / previous suggestion / snippet jump back" })

  --  Esc with the completion menu open closes only the menu and stays in
  --  insert mode (Improvment.md): then Tab steps past the pair. A suggestion
  --  picked with Tab is kept (<C-y>); with none picked the typed text stays
  --  (<C-e>). A second Esc leaves insert mode as always.
  map('i', '<Esc>', function()
    if vim.fn.pumvisible() == 0 then return "<Esc>" end
    return vim.fn.complete_info({ 'selected' }).selected ~= -1 and "<C-y>" or "<C-e>"
  end, { expr = true, replace_keycodes = true, desc = "Close the completion menu, else leave insert mode" })

  -- <CR>: a Copilot suggestion on screen is accepted. With the completion menu
  -- open the suggestion is taken: the selected item, or the first one when
  -- none is (completeopt has noselect, so usually none is). Only when the
  -- word typed already is that first item (nothing left to complete) does
  -- <CR> close the menu and make the new line. Otherwise, in a markdown list,
  -- the next item starts (pure/lists.lua), else a plain new line.
  map('i', '<CR>', function()
    local ok, shown = pcall(vim.fn['copilot#GetDisplayedSuggestion'])
    if ok and type(shown) == 'table' and (shown.text or '') ~= '' then
      return vim.fn['copilot#Accept']('')
    end
    local cr = vim.keycode('<CR>')
    if vim.fn.pumvisible() == 1 then
      local info = vim.fn.complete_info({ 'selected', 'items' })
      if info.selected ~= -1 then return vim.keycode('<C-y>') end
      local first = info.items[1] and info.items[1].word or ''
      local col = vim.api.nvim_win_get_cursor(0)[2]
      local before = vim.api.nvim_get_current_line():sub(1, col)
      if first ~= '' and before:sub(-#first) ~= first then
        return vim.keycode('<C-n><C-y>')
      end
      local list = require('pure.lists').enter()
      return vim.keycode('<C-e>') .. (list or cr)
    end
    return require('pure.lists').enter() or cr
  end, {
    expr = true,
    replace_keycodes = false,
    desc = "Accept Copilot suggestion / next list item / new line",
  })
end)
