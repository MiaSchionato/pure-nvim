-- =============================================================================
--  Settings
-- =============================================================================
--  The one file to change this configuration to your taste. It is split in
--  two parts, each in sections with a header:
--
--    1. Neovim         the editor's own options (vim.opt / vim.g)
--                        Interface · Editing · Search · Completion · Files
--                        · Windows · Folds · Netrw · Performance
--    2. Plugins        the settings of this configuration's modules (lua/pure/,
--                      all vim.g.pure_*), one section per plugin
--                        Vault · New files · Markdown · Todoist · Calendar
--                        · LLMs · Dashboard · Key hints · Indent guide
--                        · Terminal · Neovide · Advanced
--
--  Every line says what it does. For a plugin setting the comment also gives
--  its default; the ones changed from it say "Changed". A commented-out line
--  is a setting left unset, with what unset means.
--
--  Keys are not here: they are in configs/keymaps.lua (and docs/keymaps.md).
--  Nothing personal goes in this file: tokens, credentials and the vault's
--  path live in stdpath('data'), outside the repository.
--
--  (Asked for in the vault's Improvment.md: every default written down and
--  explained, the file organised by plugin.)
-- =============================================================================

local o = vim.opt

-- #############################################################################
--  1. NEOVIM
-- #############################################################################

-- -----------------------------------------------------------------------------
--  Interface
-- -----------------------------------------------------------------------------
-- Tabline only with 2+ tabs (0 never, 1 with several tabs, 2 always), drawn by
-- configs/functions.lua; the statusline is pure/statusline.lua.
o.showtabline = 1
o.tabline = "%!v:lua.require('configs.functions').MyTabline()"
o.statusline = "%!v:lua.require('pure.statusline').MyStatusLine()"
-- Keys being typed (a count, an operator waiting) shown in the statusline.
o.showcmd = true
o.showcmdloc = "statusline"
o.showmode = false          -- the mode is in the statusline already
o.cmdheight = 0             -- no command line row when not typing a command

o.number = true             -- line numbers
o.relativenumber = true     -- ... relative to the cursor line
o.cursorline = false        -- no highlight of the cursor line
o.signcolumn = "auto"       -- the sign column only when there are signs
o.termguicolors = true      -- 24-bit colours
o.winborder = "rounded"     -- border of floating windows
o.winblend = 0              -- floating windows opaque
o.wrap = true               -- long lines wrap
o.list = false              -- no markers for tabs and trailing spaces...
o.listchars:append({ extends = "⟩", precedes = "⟨" }) -- ...these when 'list' is on
o.scrolloff = 5             -- lines kept above / below the cursor
o.showmatch = true          -- briefly jump to the matching bracket when typed
o.mouse = ""                -- mouse off

-- Concealed markup (e.g. markdown's ** and `): shown as is by default;
-- markdown buffers turn conceal on for themselves (pure/render-md.lua).
o.conceallevel = 0
o.concealcursor = ""

-- -----------------------------------------------------------------------------
--  Editing
-- -----------------------------------------------------------------------------
o.tabstop = 4               -- a tab is 4 columns
o.shiftwidth = 4            -- >> and << move 4 columns
o.softtabstop = 4           -- <Tab> / <BS> count 4 columns
o.expandtab = true          -- spaces instead of tabs
o.smartindent = true        -- indent after { and the like (markdown turns it off)
o.autoindent = true         -- a new line keeps the indentation of the last
o.backspace = "indent,eol,start" -- <BS> deletes over indentation, line ends, inserts
o.iskeyword:append("-")     -- "foo-bar" is one word for w, *, completion
o.undofile = true           -- undo history kept after closing a file...
-- ...in the state folder, outside the configuration's git repository.
o.undodir = vim.fn.stdpath("state") .. "/undo"
vim.fn.mkdir(vim.o.undodir, "p")

-- -----------------------------------------------------------------------------
--  Search
-- -----------------------------------------------------------------------------
o.ignorecase = true         -- case-blind...
o.smartcase = true          -- ...unless the search has a capital letter
o.hlsearch = false          -- matches not left highlighted (<leader>cl toggles)
o.incsearch = true          -- show the match while typing the search
o.path:append("**")         -- :find looks in subfolders too
o.wildignore:append("*/node_modules/*", "*/.git/*", "*/tmp/*", "*/dist/*", "*/build/*")

-- -----------------------------------------------------------------------------
--  Completion
-- -----------------------------------------------------------------------------
-- The menu with one match too, nothing inserted or selected until Tab picks
-- (see configs/keymaps.lua: Tab, <CR>, Esc).
o.completeopt = { "menu", "menuone", "noinsert", "noselect" }
-- Completion as you type (Neovim 0.12). Sources in order: 'o' the omnifunc
-- (the language server, or the [[links]] of the vault in notes), then words
-- of this buffer, other windows, other buffers, unloaded buffers.
o.autocomplete = true
o.complete = "o,.,w,b,u"
o.pumheight = 10            -- at most 10 items shown
o.pumborder = "rounded"     -- border of the menu
o.pumblend = 0              -- menu opaque

-- -----------------------------------------------------------------------------
--  Files and buffers
-- -----------------------------------------------------------------------------
o.swapfile = false          -- no .swp files
o.autoread = true           -- reload a file changed outside, if not edited here
o.autowrite = false         -- never save by itself
o.hidden = true             -- a changed buffer may be left without saving
o.errorbells = false        -- no bell
-- The working directory follows the current file.
o.autochdir = true

-- -----------------------------------------------------------------------------
--  Timing
-- -----------------------------------------------------------------------------
o.updatetime = 250          -- ms without typing before CursorHold (not completion)
o.timeoutlen = 500          -- ms to wait for the rest of a mapping (<leader>...)
o.ttimeoutlen = 0           -- no wait after <Esc> for a key code

-- -----------------------------------------------------------------------------
--  Windows
-- -----------------------------------------------------------------------------
o.splitbelow = true         -- :split opens below
o.splitright = true         -- :vsplit opens to the right

-- -----------------------------------------------------------------------------
--  Folds (see also the Markdown section and pure/folding.lua)
-- -----------------------------------------------------------------------------
-- A closed fold shows its first line and how many lines it holds.
o.foldtext = "v:lua.PureFoldText()"
o.fillchars = { fold = " " }
-- Everything open when a file opens; folds are made automatically
-- (treesitter, or indentation; pure/folding.lua picks per buffer).
o.foldlevel = 99
o.foldlevelstart = 99
o.foldenable = true
o.foldcolumn = "0"          -- no fold column
o.foldmethod = "indent"

-- -----------------------------------------------------------------------------
--  Netrw (the built-in file explorer; oil.nvim is the one mapped to keys)
-- -----------------------------------------------------------------------------
vim.g.netrw_winsize = 25    -- width in %, as a split
vim.g.netrw_banner = 0      -- no help banner
vim.g.netrw_keepdir = 0     -- the working directory follows netrw's

-- -----------------------------------------------------------------------------
--  Performance
-- -----------------------------------------------------------------------------
-- No redraw while a macro runs. (Known Neovim 0.12.5 bug with it and
-- 'autocomplete': a mapping sending <C-n> with the menu closed crashed it;
-- configs/keymaps.lua avoids that.)
o.lazyredraw = true
o.redrawtime = 10000        -- ms syntax highlighting may take before giving up
o.maxmempattern = 20000     -- memory (KB) a search pattern may use

-- #############################################################################
--  2. PLUGINS (lua/pure/)
-- #############################################################################

-- -----------------------------------------------------------------------------
--  Vault and notes  (pure/zettelkasten.lua, pure/notes.lua, <leader>v)
-- -----------------------------------------------------------------------------
-- The Obsidian vault. Unset (default): asked for on a fresh install and
-- remembered in stdpath('data'); :ZettelVault changes it. Setting it here
-- overrides that.
-- vim.g.pure_vault = '~/Atlas'

-- Folder of the templates, inside the vault. Default: 'Templates'.
vim.g.pure_templates = 'Templates'

-- Language of day and month names in template dates: 'en' (default) or 'pt'.
vim.g.pure_templates_locale = 'en'

-- Where new notes go (<leader>vn / <leader>nv), inside the vault.
-- Default: '0-Inbox'.
vim.g.pure_inbox = '0-Inbox'

-- Folders of the periodic notes (Daily, Weekly, Monthly templates), inside
-- the vault. Only the periods listed change; the others keep their default.
-- Default: 9-Archive/Periodic/Daily, .../Weekly, .../Monthly.
-- Changed: 7-Archive (the vault's 9-Archive was renamed on 2026-10-01).
vim.g.pure_periodic_folders = {
  Daily   = '7-Archive/Periodic/Daily',
  Weekly  = '7-Archive/Periodic/Weekly',
  Monthly = '7-Archive/Periodic/Monthly',
}

-- The list the daily note's quote of the day comes from ({{quote}}).
-- Default: '9-Archive/Periodic/Quotes.md'. Changed: 7-Archive, as above.
vim.g.pure_quotes = '7-Archive/Periodic/Quotes.md'

-- Folder each template moves its note to (<leader>vt), by template name.
-- {{title}} becomes the note's title. Only the names listed change; false
-- leaves that template's note where it is. Delete is also the trash
-- (<leader>vd, vim.g.pure_trash_cleanup) and Permanent is where the daily
-- note's resurfaced notes come from, so those two always keep a folder.
-- Default:
-- vim.g.pure_template_destinations = {
--   Delete     = '0-Inbox/Trash',
--   Literature = '3-Zettelkasten/Literature',
--   MOC        = '4-Maps',
--   Permanent  = '3-Zettelkasten/Permanent',
--   Project    = '1-Projects/{{title}}',
--   Seed       = '3-Zettelkasten/Seeds',
--   VideoIdeas = '2-Areas/Audiovisual/Ideas',
-- }

-- Empty the vault's trash (0-Inbox/Trash, where <leader>vd and the Delete
-- template send notes) each time Neovim starts, as Obsidian's TrashCleaner
-- did. true: everything; a number: only what was not modified for that many
-- days; false: never. Deleted for good, not moved to the recycle bin.
-- Default: false. Changed: true.
vim.g.pure_trash_cleanup = true

-- Make today's daily note (from the Daily template) each time Neovim starts,
-- without opening it, so it is there before it is first opened. false: only
-- when it is opened (d on the dashboard). Default: false. Changed: true.
vim.g.pure_daily_on_start = true

-- -----------------------------------------------------------------------------
--  New files and pickers  (pure/fuzzyUtils.lua, <leader>n, <leader>f)
-- -----------------------------------------------------------------------------
-- <leader>n. / nn / nh / ne ask for the new file's name. false: an unnamed
-- buffer working in that folder instead (":w name" saves it there).
-- Default: true.
vim.g.pure_new_file_ask_name = true

-- Folders the fuzzy pickers never list. Default: { '.git', '.obsidian' }.
vim.g.pure_fuzzy_ignore = { '.git', '.obsidian' }

-- -----------------------------------------------------------------------------
--  Markdown  (pure/render-md.lua, pure/mdview.lua, pure/lists.lua,
--             pure/folding.lua)
-- -----------------------------------------------------------------------------
-- Spell checking languages; only those with a word list installed are used.
-- Default: { 'pt_br', 'en', 'it' }. <C-l> in insert mode fixes the last
-- misspelled word.
vim.g.pure_spelllang = { 'pt_br', 'en', 'it' }

-- The bullet drawn for each nesting level, repeating after the last.
-- Default: { '•', '◦', '▪', '▫' }.
vim.g.pure_md_bullets = { '•', '◦', '▪', '▫' }

-- Checkbox states that count as done for zt / zT (fold the done / the open
-- tasks); every other state ([ ], [~], [!], [>]...) is open. Default: 'xX-'.
vim.g.pure_tasks_done = 'xX-'

-- -----------------------------------------------------------------------------
--  Todoist  (pure/todoist.lua, <leader>td; the token: :TodoistToken)
-- -----------------------------------------------------------------------------
-- When :w in the task list asks before sending: 'all' (every save), 'delete'
-- (only when tasks would be deleted) or 'never'. Default: 'all'.
-- Changed: 'never'.
vim.g.pure_todoist_confirm = 'never'

-- Folder where the task list and a timestamped history of every change are
-- kept (tasks.md, history.md, tasks.json), relative to the vault so it moves
-- with it. Unset or '' (default): no archive. Changed: set (7-Archive since
-- the vault's 9-Archive was renamed on 2026-10-01).
vim.g.pure_todoist_archive = '7-Archive/Todoist/'

-- Write the tasks of each ```todoist block into its note as text, refreshed
-- every `interval` minutes. false (default): drawn, not written.
-- Changed: every 10 minutes.
vim.g.pure_todoist_sync = { interval = 10 }

-- A synced list starts folded: 'subtasks' (each task with subtasks as one
-- line), 'list' (the whole list as one line) or false (nothing folded).
-- Default: 'subtasks'.
vim.g.pure_todoist_fold = 'subtasks'

-- -----------------------------------------------------------------------------
--  Google Calendar  (pure/calendar.lua, pure/gcal.lua, ```calendar blocks)
-- -----------------------------------------------------------------------------
-- Width of a day's box in the month grid, in columns. Default: 25.
vim.g.pure_calendar_cell_width = 25

-- Length of an appointment written with only its start time, in minutes.
-- Default: 60.
vim.g.pure_calendar_duration = 60

-- Language of the grid's day names: 'pt' (default) or 'en'.
vim.g.pure_calendar_locale = 'pt'

-- When a save asks before sending to Google: 'delete' (only before deleting,
-- default), 'all' (every save) or 'never'.
vim.g.pure_calendar_confirm = 'delete'

-- Sync every `interval` minutes, besides at start, when a note with a block
-- is opened or saved, and on :CalendarSync. false: never on a timer.
-- Default: { interval = 15 }.
vim.g.pure_calendar_sync = { interval = 15 }

-- -----------------------------------------------------------------------------
--  LLMs: Claude, Ollama, agy  (pure/llm.lua, <leader>a)
-- -----------------------------------------------------------------------------
-- The model when none was picked with <leader>am (a pick is remembered and
-- wins): 'claude:default', 'claude:sonnet', 'ollama:qwen3.5:9b', 'agy:', ...
-- Unset (default): 'claude:default'.
-- vim.g.pure_llm_model = 'ollama:gemma4:e4b'

-- Claude's command (Claude Code). Default: 'claude'.
vim.g.pure_claude_cmd = 'claude'

-- ```claude blocks in notes run by themselves when due. false: only with
-- <leader>ab. Default: true.
vim.g.pure_llm_blocks = true

-- Folder of the actions (<leader>ax), inside the vault. Default: 'claude'.
-- Changed: 'AI' (the vault's Claude/ folder was renamed on 2026-10-01).
vim.g.pure_llm_actions = 'AI'

-- Folders (inside the vault, or absolute) no cloud model (Claude, agy) may
-- see; local models (Ollama) may. A request holding a note from one, or whose
-- folders reach one, is not sent to a cloud model. Claude still works in the
-- vault's root when the vault's .claude/settings.json denies Read(<folder>/**).
-- Default: none. Changed: the private folder.
vim.g.pure_llm_private = { '6-Private' }

-- Folder of the personas (/name), inside the actions folder. Default: 'Personas'.
-- vim.g.pure_llm_personas = 'Personas'

-- A model's thinking: 'show' (dimmed while it thinks, folded after: t in the
-- chat, <leader>at for <leader>ai) or 'hide'. Default: 'show'.
vim.g.pure_llm_thinking = 'show'

-- The file about you that every request reads (<leader>au opens it).
-- Unset (default): stdpath('data')/llm_user.md, outside every git
-- repository. false: no such file.
-- vim.g.pure_llm_user_context = '~/notes/about-me.md'

-- Models may add what they learn about you to that file (<remember>); a fact
-- already there is not written again. false: read only. Default: true.
vim.g.pure_llm_memory = true

-- Ollama's address. Default: 'http://localhost:11434'.
vim.g.pure_ollama_url = 'http://localhost:11434'

-- The largest context an Ollama request may get, in tokens. Each request is
-- sized as small as it allows (8192, doubled as needed): on an 8 GB card a
-- 9B model with a 32K context runs half as fast. Default: 32768.
vim.g.pure_ollama_num_ctx = 32768

-- Let Ollama models think before answering (qwen3.5, deepseek-r1...).
-- false (default): they answer straight away, which on an 8 GB card was 5 to
-- 30 times faster with answers as good for everyday requests. true: for hard
-- problems; models that cannot think just answer.
vim.g.pure_ollama_think = false

-- Ollama found down when a request needs it: 'ask' to start it (default),
-- true to start it without asking, false never. Started from here, it stops
-- when Neovim quits.
vim.g.pure_ollama_autostart = 'ask'

-- Start Ollama in the background when Neovim opens (with a UI), without
-- asking, if it is not running already. Default: false.
vim.g.pure_ollama_start_with_nvim = false

-- Minutes without any Ollama request after which the models used here are
-- unloaded from the GPU and the Ollama started here is closed (as <leader>aq
-- does). The next request starts it again (see pure_ollama_autostart).
-- false or 0: never. Default: 15.
vim.g.pure_ollama_idle_minutes = 15

-- Models folder for the Ollama started from here. Unset (default):
-- OLLAMA_MODELS, or ~/.ollama/models when OLLAMA_MODELS holds no models.
-- vim.g.pure_ollama_models = 'D:/Models'

-- -----------------------------------------------------------------------------
--  Dashboard  (pure/dashboard.lua)
-- -----------------------------------------------------------------------------
-- Size of the drawing: 'auto' (as large as the window fits, default) or a
-- fixed scale (1, 2, ...).
vim.g.pure_dashboard_scale = 'auto'

-- -----------------------------------------------------------------------------
--  Key hints  (pure/keyhint.lua: the window listing the keys after <leader>)
-- -----------------------------------------------------------------------------
-- false: off. Default: true.
vim.g.pure_keyhint = true

-- Milliseconds before it shows. Default: 1000.
vim.g.pure_keyhint_delay = 1000

-- The prefixes it shows for, as { mode, keys } pairs.
-- Default: { { 'n', '<leader>' }, { 'x', '<leader>' } }.
-- (Its group names, vim.g.pure_keyhint_groups, are in configs/keymaps.lua,
-- next to the keys.)
vim.g.pure_keyhint_triggers = { { 'n', '<leader>' }, { 'x', '<leader>' } }

-- -----------------------------------------------------------------------------
--  Indent guide  (pure/indentscope.lua)
-- -----------------------------------------------------------------------------
-- true: off everywhere (vim.b.pure_indentscope_disable turns it off in one
-- buffer). Default: false.
vim.g.pure_indentscope_disable = false

-- -----------------------------------------------------------------------------
--  Terminal  (pure/terms.lua, <leader>tt)
-- -----------------------------------------------------------------------------
-- The shell. Unset (default): on Windows the first of nu, pwsh, powershell
-- found; elsewhere 'shell'.
-- vim.g.pure_terminal_shell = 'cmd.exe'

-- -----------------------------------------------------------------------------
--  Neovide (the GUI)
-- -----------------------------------------------------------------------------
vim.g.neovide_normal_opacity = 1 -- window opacity (0 to 1)
-- vim.g.neovide_transparency = 1

-- -----------------------------------------------------------------------------
--  Advanced: tests and the one-file version (no need to set)
-- -----------------------------------------------------------------------------
-- vim.g.pure_calendar_source = 'mock'         a sample month instead of Google
-- vim.g.pure_calendar_api_url / _auth_url / _token_url   Google's endpoints
-- vim.g.pure_todoist_url                      Todoist's API endpoint
-- vim.g.pure_bundle_dir, vim.g.pure_portable  set by the single-file build
--                                             (scripts/bundle.lua)
