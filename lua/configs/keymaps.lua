-- =============================================================================
--  Keymaps
-- =============================================================================
--  Leader is <Space>. The second key groups the action:
--
--    a  llms (ai)
--    b  buffers        e  explore (pickers)   l  lsp             u  undotree
--    c  code           f  find (pickers)      n  new file/folder v  vault (notes)
--    d  diagnostics    g  git                 t  toggles         w  tabs, window view (wv_)
--    m  org notes      M  manim
--    j  jumps          s  split               o  open            x  checkbox state (notes)
--    z  folds
--
--  Non-leader keys come first: motions, text objects, surround.
-- =============================================================================

local map = vim.keymap.set
local func = require('configs.functions')
local fzf = require('pure.fuzzyUtils')
local sur = require('pure.surround')
local term = require('pure.terms')
local lsp = vim.lsp.buf
local diag = vim.diagnostic
local vault = require('pure.vault')
-- Picker targets (explore <leader>e_, find <leader>f_, new file <leader>n_) and their helpers: configs/functions.lua.
local dirs = func.dirs
local file = func.fileDirs
local up = func.up
local here = func.here
local inDir = func.inDir
local opts = { noremap = true, silent = true }

vim.g.mapleader = ' '

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

-- Move lines (the guard by buffer type is explained in func.moveLine)
local moveLine = func.moveLine

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
-- p is for parentheses, not paragraphs: dip deletes inside (...). The
-- paragraph is still there as i} / a}.
map({ 'x', 'o' }, 'ip', [[i(]], { desc = "Inner parentheses" })
map({ 'x', 'o' }, 'ap', [[a(]], { desc = "Outer parentheses" })
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
-- Win+C / Win+V reach nvim as F16 / F15 (kanata layer term + WezTerm), which leaves
-- Ctrl+C (interrupt) and Ctrl+V (visual block) alone.
map({ 'n', 'v' }, "<F16>", '"+y', func.getOpts(opts, "Yank to clipboard"))
map({ 'n', 'v' }, "<F15>", '"+p', func.getOpts(opts, "Paste from clipboard"))
map({ 'i', 'c' }, "<F15>", "<C-r>+", func.getOpts(opts, "Paste from clipboard"))

map({ 'n', 'v' }, "<leader>D", '"_d', func.getOpts(opts, "Delete without yanking"))

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
-- Splits
map('n', "<leader>sh", "<C-w>h", func.getOpts(opts, "Focus split window left"))
map('n', "<leader>sj", "<C-w>j", func.getOpts(opts, "Focus split window below"))
map('n', "<leader>sk", "<C-w>k", func.getOpts(opts, "Focus split window above"))
map('n', "<leader>sl", "<C-w>l", func.getOpts(opts, "Focus split window right"))
map('n', "<leader>sq", "<C-w>q", func.getOpts(opts, "Close split window"))
map('n', "<leader>sn", "<C-w>n", func.getOpts(opts, "New split horizontally"))
map('n', "<leader>sv", "<C-w>v", func.getOpts(opts, "New split vertically"))

-- Resize splits
map('n', "<leader>s=", "<cmd>resize +5<CR>", func.getOpts(opts, "Taller split window"))
map('n', "<leader>s-", "<cmd>resize -5<CR>", func.getOpts(opts, "Shorter split window"))
map('n', "<leader>s,", "<cmd>vertical resize -5<CR>", func.getOpts(opts, "Wider split window"))
map('n', "<leader>s.", "<cmd>vertical resize +5<CR>", func.getOpts(opts, "Narrower split window"))

-- Tabs
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
map('n', '<leader>ee', func.explore(here), func.getOpts(opts, "Explore current directory"))
map('n', '<leader>E' , func.explore(dirs['~']), func.getOpts(opts, "Explore home"))
map('n', '<leader>e.', func.explore(dirs['.']), func.getOpts(opts, "Explore ~/.config"))
map('n', '<leader>en', func.explore(dirs.n), func.getOpts(opts, "Explore nvim config"))
map('n', '<leader>ev', func.explore(dirs.v), func.getOpts(opts, "Explore the vault"))
map('n', '<leader>ep', func.explore(dirs.p), func.getOpts(opts, "Explore the Projects directory"))
-- oil is required on use: plugins/oil.lua loads after this file, so the module is not there yet.
map('n', '<leader>eo', function() require('oil').toggle_float() end, func.getOpts(opts, "Oil Float"))

-- =============================================================================
--  Find  (<leader>f)
-- =============================================================================
map('n', '<leader>ff', function() fzf.fuzzySearch(file["4p"]()) end, func.getOpts(opts, "Find files, four levels up"))
map('n', '<leader><leader>', function() fzf.fuzzySearch(file.pp()) end, func.getOpts(opts, "Find files, two levels up"))
map('n', '<leader>f~', inDir(fzf.fuzzySearch, dirs['~']), func.getOpts(opts, "Find in home"))
map('n', '<leader>f.', inDir(fzf.fuzzySearch, dirs['.']), func.getOpts(opts, "Find in ~/.config"))
map('n', '<leader>fn', inDir(fzf.fuzzySearch, dirs.n), func.getOpts(opts, "Find in nvim config"))
map('n', '<leader>fp', inDir(fzf.fuzzySearch, dirs.p), func.getOpts(opts, "Find in Projects"))
-- <leader>fv is the same picker as <leader>vf (defined with the vault keys below).

map('n', "<leader>fe", function() inDir(fzf.fuzzyExplorer, here())() end,
func.getOpts(opts, "fzf explorer, current directory"))
map('n', "<leader>fg", function() fzf.fuzzyGrep(require('pure.scratch').dir(1)) end, func.getOpts(opts, "Grep"))
map('n', "<leader>f/", fzf.fuzzyOldfiles, func.getOpts(opts, "Recent files"))
map('n', "<leader>fh", fzf.fuzzyHelp, func.getOpts(opts, "Help tags"))
map('n', "<leader>fb", fzf.fuzzyBuffers, func.getOpts(opts, "Buffers"))
map('n', "<leader>fj", fzf.fuzzyJump, func.getOpts(opts, "Jump list"))
map('n', "<leader>ft", fzf.fuzzyTodo, func.getOpts(opts, "TODO: of the repo (or the folder)"))
map('n', '<leader>f"', fzf.fuzzyRegisters, func.getOpts(opts, "Registers (Enter: make it the register p pastes)"))
map('n', "<leader>f'", fzf.fuzzyRegisters, func.getOpts(opts, "Registers (Enter: make it the register p pastes)"))
map('n', '<leader>fl', function() require('pure.notes').backlinks() end, func.getOpts(opts, "Notes linking here (backlinks, also <leader>vb)"))
map('n', '<leader>fc', fzf.fuzzyColorscheme, func.getOpts(opts, "Colorschemes"))

-- =============================================================================
--  New file / folder  (<leader>n)
-- =============================================================================
--  Only <leader>nf asks for a folder. The others already name it, so they
--  go straight there: they ask for the file name, or, with
--  vim.g.pure_new_file_ask_name = false (configs.lua), open an unnamed buffer
--  working in that folder. They used to open a folder picker every time.
map("n", "<leader>nf", function() fzf.NewFile(up(1)) end,
func.getOpts(opts, "New file, pick the folder (from two levels up)"))
map("n", "<leader>ne", function() fzf.NewFileIn(here()) end, func.getOpts(opts, "New file here"))
map("n", "<leader>ns", function() require('pure.scratch').open() end, func.getOpts(opts, "Scratch note"))
map("n", "<leader>nh", inDir(fzf.NewFileIn, dirs['~']), func.getOpts(opts, "New file in home"))
map("n", "<leader>n.", inDir(fzf.NewFileIn, dirs['.']), func.getOpts(opts, "New file in ~/.config"))
map("n", "<leader>nn", inDir(fzf.NewFileIn, dirs.n), func.getOpts(opts, "New file in nvim config"))
-- A seed in the vault's inbox (the quick capture's `s`, <leader>vq s).
map("n", "<leader>nv", function() require('pure.vault').newSeed() end, func.getOpts(opts, "New seed in the vault's inbox"))
map("n", "<leader>nd", function() fzf.NewFolder(here()) end, func.getOpts(opts, "New folder here"))
-- <leader>nt (template) and <leader>nr (rename note) moved to the vault group
-- (the capture menu <leader>vq, and <leader>vr): they act on a note, they do not make a new file.

-- =============================================================================
--  Manim  (<leader>M, pure/manim.lua)
-- =============================================================================
map('n', '<leader>Mm', function() require('pure.manim').toggle() end,
func.getOpts(opts, "Preview the scene, again on every save (toggle)"))
map('n', '<leader>Ms', function() require('pure.manim').pick() end, func.getOpts(opts, "Preview another scene"))
map({ 'n', 'x' }, '<leader>Mp', function() require('pure.manim').part() end,
func.getOpts(opts, "Preview only this part (selection, or the block under the cursor)"))
map('n', '<leader>Mf', function() require('pure.manim').frame() end, func.getOpts(opts, "Picture of the scene at this line"))
map('n', '<leader>Mi', function() require('pure.manim').interactive() end,
func.getOpts(opts, "Live window at this line: mouse camera, Python shell (toggle)"))

-- =============================================================================
--  Vault  (<leader>v, pure/vault.lua)
-- =============================================================================
--  Everything that works on the vault (org), in one group, as Doom's
--  `SPC v`. It replaced the group of the old Markdown vault, which is no
--  longer used: its functions are still in pure/zettelkasten.lua and
--  pure/notes.lua, as commands only. <leader>ev, <leader>fv and <leader>gv
--  follow, beside the other folders of their group.
map('n', '<leader>vf', vault.find, func.getOpts(opts, "Find a note, heading or alias (a title that matches nothing makes a seed)"))
map('n', '<leader>fv', vault.find, func.getOpts(opts, "Find a note, heading or alias (same as <leader>vf)"))
map('n', '<leader>vF', vault.findFile, func.getOpts(opts, "Find a file of the vault"))
map('n', '<leader>vg', vault.grep, func.getOpts(opts, "Grep the vault"))
map('n', '<leader>vN', vault.newNote, func.getOpts(opts, "New note in its own file"))
-- 2026-11-08 (Mia): the capture menu moved from <leader>vt to <leader>vq (vt is gone); n and c are
-- Doom's grow and compost; a new seed is the capture's `s` (n was "new seed"). The quick edit of the
-- linked note, which was <leader>vq, was removed.
map('n', '<leader>vq', vault.capture, func.getOpts(opts, "Quick capture: seed, task, link, journal, source"))
map('n', '<leader>vn', vault.grow, func.getOpts(opts, "Grow the idea: SEED > SPROUT > PLANT > TREE"))
map('n', '<leader>vc', vault.compost, func.getOpts(opts, "Let the idea go: compost"))
map('n', '<leader>vi', vault.insertLink, func.getOpts(opts, "Insert a link to a node"))
map('n', '<leader>vb', vault.backlinks, func.getOpts(opts, "Backlinks (notes linking here)"))
map('n', '<leader>vr', vault.rename, func.getOpts(opts, "Rename this note (title and file)"))
map('n', '<leader>vd', vault.delete, func.getOpts(opts, "Delete this note (to archive/trash/)"))
map('n', '<leader>vj', vault.journalLine, func.getOpts(opts, "Journal line (today)"))
map('n', '<leader>vJ', vault.journalToday, func.getOpts(opts, "Today in the journal"))
map('n', '<leader>ve', vault.explore, func.getOpts(opts, "Explore the vault"))
map('n', '<leader>vs', vault.sync, func.getOpts(opts, "Save the notes and commit (sync if there is an upstream)"))
-- <leader>vp: preview the linked note. Markdown notes keep pure/linkview.lua's
-- global key; in org notes this one wins. (The quick edit, <leader>vq, was removed.)
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'org',
  group = vim.api.nvim_create_augroup('VaultKeys', { clear = true }),
  callback = function(args)
    map('n', '<leader>vp', vault.preview, { buffer = args.buf, desc = 'Preview the linked note' })
  end,
})

-- =============================================================================
--  LLMs: Claude, Ollama, agy  (<leader>a, pure/llm.lua)
-- =============================================================================
local function llm(fn)
  return function() require('pure.llm')[fn]() end
end
map({ 'n', 'x' }, '<leader>ai', llm('write'), func.getOpts(opts, "Write here (visual: rewrite)"))
map({ 'n', 'x' }, '<leader>aa', llm('ask'), func.getOpts(opts, "Chat: show / hide"))
map({ 'n', 'x' }, '<leader>ac', llm('review'), func.getOpts(opts, "Review the code"))
map({ 'n', 'x' }, '<leader>ar', llm('repeatLast'), func.getOpts(opts, "Repeat the last request"))
map('n', '<leader>ah', llm('history'), func.getOpts(opts, "Past answers"))
map('n', '<leader>as', llm('stop'), func.getOpts(opts, "Stop"))
-- Frees the GPU without quitting (Improvment.md): what quitting does.
map('n', '<leader>aq', llm('shutdown'), func.getOpts(opts, "Quit the AI: stop, unload models, close Ollama"))
map('n', '<leader>am', llm('selectModel'), func.getOpts(opts, "Select model (Ollama / Claude / agy)"))
map('n', '<leader>at', llm('toggleThinking'), func.getOpts(opts, "Thinking of <leader>ai (show / hide)"))
-- The file about you that every request reads (outside any git repository).
map('n', '<leader>au', func.openUserContext, func.getOpts(opts, "User context file (what the LLMs know about you)"))
map({ 'n', 'x' }, '<leader>ax', llm('pickAction'), func.getOpts(opts, "Actions (the folder vim.g.pure_llm_actions)"))
map('n', '<leader>ab', llm('runBlockAtCursor'), func.getOpts(opts, "Run the ```llm block under the cursor"))
map('n', '<leader>ad', function() require('pure.llm').runNamed('Daily note') end,
func.getOpts(opts, "Daily note: next step and the measured day"))
map('n', '<leader>aw', function() require('pure.llm').runNamed('Week review') end,
func.getOpts(opts, "Weekly note: the week in one place"))
map('n', '<leader>ap', llm('pickPersona'), func.getOpts(opts, "Personas: pick one, open its chat"))
map('n', '<leader>aj', function() require('pure.llm').chatWith('job') end,
func.getOpts(opts, "Job assistant: the chat with the /job persona"))

-- =============================================================================
--  Git
-- =============================================================================
-- pure/git.lua: required on use, like the other pure modules' keys.
local git = function(fn) return function(...) return require('pure.git')[fn](...) end end

map('n', "<leader>gl", fzf.fuzzyGit, func.getOpts(opts, "Git log"))
map('n', "<leader>gg", fzf.fuzzyGitGrep, func.getOpts(opts, "Git grep"))
-- No arguments: map must not hand its own to gitDiffToggle(from, to).
map('n', "<leader>gd", function() func.gitDiffToggle() end, func.getOpts(opts, "Toggle git diff (HEAD~ when everything is committed)"))
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
map('n', "<leader>gv", function() require('pure.vault').sync() end, func.getOpts(opts, "Vault: save the notes and commit"))

-- =============================================================================
--  LSP
-- =============================================================================
map('n', 'K', func.followOrHover, func.getOpts(opts, "Follow link, else LSP hover"))
map('n', 'gd', lsp.definition, func.getOpts(opts, "LSP definition"))
-- No 'gr' here: it made the builtin grr/grn/gra/gri/grt/grx wait 500 ms, and
-- grr already lists references.
map('n', '<leader>la', lsp.code_action, func.getOpts(opts, "LSP code action"))
map('n', '<leader>lr', lsp.rename, func.getOpts(opts, "LSP rename"))
map('n', '<leader>ls', lsp.workspace_symbol, func.getOpts(opts, "LSP workspace symbols"))
map('i', '<up>', func.signatureHelpOrUp, { expr = true, replace_keycodes = true, silent = true, desc = "LSP signature help, else up" })

-- =============================================================================
--  Diagnostics
-- =============================================================================
map('n', '<leader>dd', diag.open_float, func.getOpts(opts, "Show diagnostic"))
map('n', '[d', diag.get_prev, func.getOpts(opts, "Previous diagnostic"))
map('n', ']d', diag.get_next, func.getOpts(opts, "Next diagnostic"))

-- =============================================================================
--  Toggles
-- =============================================================================
map('n', '<leader>tx', func.toggleTransparency, func.getOpts(opts, "Toggle transparency"))
map('n', '<leader>td', func.toggleDiagnostics, func.getOpts(opts, "Toggle diagnostics"))
map('n', '<leader>tz', func.toggleZenMode, func.getOpts(opts, "Toggle zen mode"))
map('n', '<leader>ts', func.toggleStatusline, func.getOpts(opts, "Toggle statusline"))
map('n', '<leader>tt', func.toggleTabline, func.getOpts(opts, "Toggle tabline"))
map('n', '<leader>tc', func.toggleSigncolumn, func.getOpts(opts, "Toggle signcolumn"))
map('n', '<leader>tw', func.toggleWrap, func.getOpts(opts, "Toggle wrap"))
map('n', '<leader>tH', func.toggleHeadingBand, func.getOpts(opts, "Toggle the heading background bar"))
map('n', '<leader>ti', func.toggleInlayHints, func.getOpts(opts, "Toggle inlay hints"))
map('n', '<leader>tp', func.toggleCopilot, func.getOpts(opts, "Toggle Copilot"))
map('n', '<leader>th', func.toggleWordHighlight, func.getOpts(opts, "Toggle word highlight"))
map('n', '<leader>h', func.toggleWordHighlight, func.getOpts(opts, "Toggle word highlight (short form)"))
map({ 'n', 'v' }, '<leader>tr', func.toggleRelativenumber, func.getOpts(opts, "Toggle relativenumber"))
map('n', '<leader>tm', func.toggleNoteRendering, func.getOpts(opts, "Toggle note rendering (markdown, org)"))
map('n', '<leader>tM', func.toggleBigHeadings, func.getOpts(opts, "Toggle big headings (OSC 66 / DECDHL; off by default)"))
map('n', '<leader>tT', func.toggleTableShrink, func.getOpts(opts, "Toggle shrinking of wide org tables (width cookies)"))
map('n', '<leader>tW', func.toggleTableWrap, func.getOpts(opts, "Toggle wrapping of wide org tables into extra rows (changes the text)"))
map('n', '<leader>tR', function() require('pure.reading').toggle() end, func.getOpts(opts, "Toggle reading mode (wide margins)"))
map({ 'n', 'v' }, '<leader>tn', function()
  func.toggleNumber(true)
  func.toggleRelativenumber(true)
  vim.notify('Line numbers ' .. (vim.o.number and 'on' or 'off'))
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
map('n', '<leader>zd', func.deleteFold, func.getOpts(opts, "Delete fold"))
map('n', '<leader>zr', function() require('pure.folding').auto() end,
func.getOpts(opts, "Reset folds to automatic"))
map('n', '<leader>za', func.toggleAllFolds, func.getOpts(opts, "Toggle all folds"))

map('n', '<leader>u', function()
  vim.cmd('packadd nvim.undotree')
  vim.cmd('Undotree')
end, func.getOpts(opts, "Undotree"))

-- =============================================================================
--  Next level keymaps (Care, powerfull wizardry)
-- =============================================================================
map("x", "@", [[:<C-u>execute "'<,'>normal @".nr2char(getchar())<CR>]], func.getOpts(opts, "Apply macro to selection"))

map('n', "<leader>r", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], func.getOpts(opts, "Rename word under cursor"))

map('v', "<leader>r", [["hy:%s/<C-r>h/<C-r>h/gI<Left><Left><Left>]], func.getOpts(opts, "Rename visual selection"))

-- -- Add undo break-points for punctuation in insert mode
local chars = { ",", ".", "!", "?", ";" }
for _, char in ipairs(chars) do
  vim.keymap.set("i", char, char .. "<c-g>u", { desc = "Undo breakpoint" })
end

-- Prevent overwriting the default register when deleting empty lines
map("n", "dd", func.smartDd, { expr = true, desc = "Smart dd" })

-- =============================================================================
-- Open
-- =============================================================================
-- Terminal
map('n', '<leader>ot', term.toggleTerminal, func.getOpts(opts, "Toggle terminal"))
map('n', '<leader>oc', function() term.toggleTerminal("claude") end, func.getOpts(opts, "Toggle terminal Claude"))
map('n', '<leader>om', "<CMD>tabnew | terminal nu<CR>i", func.getOpts(opts, "New tab on terminal mode"))
map('t', '<S-Del>', [[<C-\><C-n>]], func.getOpts(opts, "Leave terminal mode"))

--  Todoist
map('n', '<leader>od', '<cmd>Todoist<cr>', func.getOpts(opts, "Todoist all tasks"))
map('n', '<leader>oD', '<cmd>Todoist today | overdue<cr>', func.getOpts(opts, "Todoist today and overdue"))

-- Vault
map('n', '<leader>oi', function() vim.cmd('edit ' .. vim.fn.fnameescape(dirs.inbox())) end, func.getOpts(opts, "Open the vault's inbox"))

-- =============================================================================
--  Debug
-- =============================================================================
map({ 'n', 'v' }, '<leader>in', ':Inspect<cr>', func.getOpts(opts, "Inspect highlight under cursor"))
map('v', '<leader>ldb', 'y:lua print(<C-r>")<cr>', func.getOpts(opts, "Print selection via lua"))

-- =============================================================================
--  Completion and snippets
-- =============================================================================
--  Deferred: the <CR> mapping needs copilot.vim's autoload on the runtimepath,
vim.schedule(function()
  --  The behaviour of each key (completion menu, closing pairs, snippets, list items, Copilot) is explained
  --  in configs/functions.lua, next to the functions.
  map('i', '<tab>', func.insertTab,
  { expr = true, replace_keycodes = true, desc = "Indent an empty list item / past closing pair / next suggestion / snippet jump" })
  map('i', '<S-tab>', func.insertShiftTab,
  { expr = true, replace_keycodes = true, desc = "Outdent an empty list item / previous suggestion / snippet jump back" })
  map('i', '<Esc>', func.insertEsc,
  { expr = true, replace_keycodes = true, desc = "Close the completion menu, else leave insert mode" })
  map('i', '<CR>', func.insertEnter, {
    expr = true,
    replace_keycodes = false,
    desc = "Accept Copilot suggestion / next list item / new line",
  })
end)

