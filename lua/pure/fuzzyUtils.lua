local M = {}
local func = require('configs.functions')
local terms = require('pure.terms')
-- Every path handed to the shell is shellescape()d: this user's home is
-- "C:/Users/Mia Schionato", and an unquoted path broke at the space, so the
-- command died instantly and the floating window just blinked shut.
local cache_dir = vim.fn.stdpath("cache") if vim.fn.isdirectory(cache_dir) == 0 then vim.fn.mkdir(cache_dir, "p") end

-- Directories the pickers never descend into. `fd --hidden` walks straight into
-- .git and buries real results under dozens of internal files, and `ls -a`
-- lists it too. ripgrep already skips it on its own, so fuzzyGrep needs nothing.
--
-- ".obsidian" is the vault's own config directory: it holds hundreds of json
-- and plugin files that drown out the actual notes.
--
-- Override with, for example:
--   vim.g.pure_fuzzy_ignore = { ".git", ".obsidian", "node_modules", "target" }
local function ignoredDirs()
  return vim.g.pure_fuzzy_ignore or { ".git", ".obsidian" }
end

--- Guarantee a single trailing slash.
---
--- The pickers build the final file name with `path .. selection`, so a caller
--- passing ".../Atlas" instead of ".../Atlas/" silently produced
--- ".../Atlasnote.md". Normalising here keeps every call site in keymaps.lua
--- from having to remember the slash.
--- @param path string|nil
--- @return string|nil
local function asDir(path)
  if path == nil or path == "" then
    return path
  end
  return (path:gsub("[/\\]+$", "")) .. "/"
end

--- @return string flags for fd, e.g. --exclude '.git'
local function fdExcludes()
  local parts = {}
  for _, dir in ipairs(ignoredDirs()) do
    table.insert(parts, "--exclude " .. vim.fn.shellescape(dir))
  end
  return table.concat(parts, " ")
end

--- @return string flags for ls, e.g. --ignore='.git'
---
--- Filtering inside ls rather than grepping its output is deliberate:
--- `ls --color=always` emits the reset sequence *between* the name and the
--- trailing slash (".git<ESC>[0m/"), so a plain `grep -v '\.git/$'` never
--- matches. '.' and '..' survive --ignore, so navigation still works.
local function lsIgnores()
  local parts = {}
  for _, dir in ipairs(ignoredDirs()) do
    table.insert(parts, "--ignore=" .. vim.fn.shellescape(dir))
  end
  return table.concat(parts, " ")
end--- The name a tool goes by on this system. Debian and Ubuntu, and so
--- Raspberry Pi OS, ship fd as "fdfind" and bat as "batcat" because other
--- packages had taken the short names; asking for "fd" there found nothing.
--- @param name string
--- @param alt string
--- @return string
local function tool(name, alt)
  if vim.fn.executable(name) == 0 and vim.fn.executable(alt) == 1 then
    return alt
  end
  return name
end

--- Whether `ls` is GNU's. --color and --ignore are GNU only: macOS ships BSD
--- ls, where the explorer's listing failed with "unrecognized option".
--- Asked once. On Windows the pickers run through Git bash, whose ls is GNU's.
local gnu_ls
local function isGnuLs()
  if gnu_ls == nil then
    if vim.fn.has("win32") == 1 then
      gnu_ls = true
    else
      local ok, res = pcall(function() return vim.system({ "ls", "--version" }):wait() end)
      gnu_ls = ok and res.code == 0
    end
  end
  return gnu_ls
end

--- The explorer's listing: hidden files included, "/" after directories, the
--- ignored directories left out.
--- @return string
local function lsList()
  if isGnuLs() then
    return "ls -ap --color=always " .. lsIgnores()
  end
  -- BSD ls has no --ignore, so grep drops them instead. Without colours: grep
  -- can only match a whole name when no escape sequence surrounds it.
  local parts = {}
  for _, dir in ipairs(ignoredDirs()) do
    table.insert(parts, "-e " .. vim.fn.shellescape(dir .. "/"))
  end
  if #parts == 0 then return "ls -ap" end
  return "ls -ap | grep -vxF " .. table.concat(parts, " ")
end

--- `ls` for the explorer's preview of a directory, in colour on both kinds.
--- @return string
local function lsPreview()
  return isGnuLs() and "ls -apF --color=always" or "CLICOLOR_FORCE=1 ls -apFG"
end

local function appendFzfOpts(extra)
  local existing = vim.env.FZF_DEFAULT_OPTS
  vim.env.FZF_DEFAULT_OPTS = existing and (existing .. " " .. extra) or extra
end

-- These pickers already run inside a dedicated floating window, so fzf must not
-- size or frame itself again.
--
-- A shell profile that exports FZF_DEFAULT_OPTS for interactive use (this one
-- sets "--height=60% --border") leaked into Neovim: fzf then took 60% of the
-- float and drew its own frame inside Neovim's rounded border, leaving roughly
-- four in every ten lines blank with a doubled outline. Appending wins because
-- fzf honours the last occurrence of a flag.
appendFzfOpts("--height=100% --border=none")

---@param opts table The options for fuzzy logic.
function M.fuzzyLogic(opts)
  local win,buf = func.createWindow(opts.title, opts.ratio)
  local temp = vim.fn.stdpath("cache") .. "/opts_run"
  vim.api.nvim_set_option_value('bufhidden', 'wipe', {buf = buf})
  -- The redirect target must be quoted; stdpath("cache") sits under the home
  -- directory, which contains a space, so "> C:/Users/Mia Schionato/..." was
  -- read by the shell as "> C:/Users/Mia" and every picker failed at once.
  vim.cmd(string.format("terminal %s > %s", opts.cmd, vim.fn.shellescape(temp)))

  -- Arrows reach fzf as an escape sequence (<Esc>[A). On Windows the
  -- terminal can deliver it split when fzf is busy, fzf then reads a lone
  -- <Esc> and quits: the grep picker closed on the first arrow key. Its own
  -- one-byte keys for the same moves cannot be split.
  local term_opts = { buffer = buf, nowait = true }
  vim.keymap.set('t', '<Up>', '<C-k>', term_opts)
  vim.keymap.set('t', '<Down>', '<C-j>', term_opts)

  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    callback = function()
      local data = ""

      if vim.fn.filereadable(temp) == 1 then
        local f = io.open(temp, "r")
        if f then
          local last_line = ""
          for line in f:lines() do
            last_line = line
          end
          f:close()
          os.remove(temp)
          data = last_line:gsub("%s+$", "")
        end
      end

      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end

        local function finish()
          if data ~= "" then
            opts.callback(data)
          elseif opts.on_cancel then
            -- Esc / Ctrl-C in fzf, or nothing matched.
            opts.on_cancel()
          end
        end

        -- Leave terminal mode before handing over. Closing the window does not,
        -- and neither does :stopinsert: Neovim stays in terminal mode until the
        -- next key arrives, so the callback ran with mode() still 't' and the
        -- first key typed afterwards was spent leaving that mode (an input()
        -- prompt opened from the callback could lose it, or be cancelled).
        -- Feed the key that leaves terminal mode, and run the callback once
        -- Neovim reports the mode change.
        if vim.api.nvim_get_mode().mode == "t" then
          vim.api.nvim_create_autocmd("ModeChanged", {
            pattern = "t:*",
            once = true,
            callback = function() vim.schedule(finish) end,
          })
          vim.api.nvim_feedkeys(vim.keycode("<C-\\><C-n>"), "n", false)
        else
          finish()
        end
      end)
    end
    })
  -- Enter terminal mode straight away, then once more on the next tick.
  --
  -- This used to be deferred by 50ms alone, which left the picker sitting in
  -- terminal-normal mode for that window. Arrow keys pressed in it hit the
  -- move-line mappings rather than fzf, so the first keystroke after opening a
  -- picker could be swallowed. The deferred call is kept as a second attempt in
  -- case something steals focus while the job starts.
  vim.cmd("startinsert")
  vim.defer_fn(function()
    if vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_mode().mode ~= "t" then
      vim.cmd("startinsert")
    end
  end, 50)
end

--- Pick one line of `lines` with fzf; `on_pick(line)` gets the choice and
--- `on_cancel()`, when given, runs if nothing was picked.
---
--- Five pickers (jumps, buffers, oldfiles, colorschemes, vim.ui.select) each
--- wrote their list to a fixed temp file and piped it into fzf by hand. The
--- file is now unique per call and always removed, picked or cancelled.
--- @param lines string[]
--- @param opts { title: string, ratio: number?, fzf: string? }  fzf: extra flags
local pick_count = 0
local function pickList(lines, opts, on_pick, on_cancel)
  pick_count = pick_count + 1
  local temp = vim.fn.stdpath("cache") .. "/pick_" .. pick_count
  vim.fn.writefile(lines, temp)
  M.fuzzyLogic({
    title = opts.title,
    ratio = opts.ratio or 0.7,
    cmd = string.format("cat %s | fzf %s", vim.fn.shellescape(temp), opts.fzf or ""),
    callback = function(selection)
      os.remove(temp)
      on_pick(selection)
    end,
    on_cancel = function()
      os.remove(temp)
      if on_cancel then on_cancel() end
    end,
  })
end

function M.fuzzySearch(path)
  if path == nil then path = vim.uv.os_homedir():gsub("\\", "/") .. "/" end
  path = asDir(path)
  local fd = tool("fd", "fdfind") .. " --hidden " .. fdExcludes() .. " --type file . --strip-cwd-prefix --base-directory  "
  local fzf = "fzf --keep-right --tiebreak=end"

  M.fuzzyLogic({
    title = "Fuzzy Search",
    ratio = 0.6,
    cmd = string.format("%s %s | %s", fd, vim.fn.shellescape(path), fzf),
    callback = function(selection)
      vim.cmd("edit! " .. vim.fn.fnameescape(path .. selection))
      vim.cmd("filetype detect")
    end

  })
end


--- Live grep: ripgrep runs again on every change of the query, and fzf only
--- shows its results. It used to pipe `rg .` into fzf -- every line of every
--- file under `path`, twice (the "." was given two times), all loaded before
--- the first key. Nothing is listed until something is typed.
function M.fuzzyGrep(path)
  path = asDir(path)
  local rg = "rg --column --line-number --no-heading --color=always --smart-case"
  -- fzf wants input on stdin even with --disabled; give it an empty one.
  -- By shell, not by OS: the windows branch runs these through Git bash.
  local empty = vim.o.shell:lower():match("cmd%.exe$") and "type nul" or "true"
  local fzf = "fzf --ansi --disabled --delimiter :"
    -- An empty query would match every line; list nothing instead. POSIX
    -- test: fzf runs reload through sh (Git bash on the windows branch).
    .. string.format(" --bind %s", vim.fn.shellescape("change:reload:[ -z {q} ] || " .. rg .. " -- {q}"))
    .. " --preview '" .. tool("bat", "batcat") .. " --style=numbers --color=always --highlight-line {2} {1}' --preview-window 'up,60\\%,border-bottom,+{2}+3/3'"

  M.fuzzyLogic({
    title = "Fuzzy Grep",
    ratio = 0.8,
    -- Run from inside `path` so ripgrep prints relative names. Given an
    -- absolute path its output starts with the drive letter, and fzf splitting
    -- on ":" then made {1} the bare "C" and {2} the path, so bat was handed a
    -- path where it wanted a line number. Counting fields from the end is not
    -- an option here, unlike fuzzyJump: the matched text can contain colons.
    cmd = string.format("cd %s && %s | %s", vim.fn.shellescape(path), empty, fzf),
    callback = function(selection)
      local rel, line, col = selection:match("^(.-):(%d+):(%d+)")
      if not (rel and line and col) then return end
      -- Those names are relative to the cd above, so rebuild the full one.
      local full_path = path .. (rel:gsub("^%.[/\\]", ""))
      vim.cmd("edit! " .. vim.fn.fnameescape(full_path))
      -- ripgrep's column is 1-based, the cursor's 0-based: without the -1
      -- the cursor landed one character right of the match.
      vim.api.nvim_win_set_cursor(0, {tonumber(line), tonumber(col) - 1})
      vim.cmd("filetype detect")
    end
  })
end

--- Neovim's help files, and every section of this config's own docs/ pages
--- ("pure todoist › Sync on …"): picking a section opens its page in a split
--- at that heading, drawn by mdview.
function M.fuzzyHelp()
  local entries, targets = {}, {}

  -- The one-file build (scripts/bundle.lua) unpacks them elsewhere.
  local docs = (vim.g.pure_bundle_dir or vim.fn.stdpath("config")) .. "/docs"
  for _, name in ipairs(vim.fn.isdirectory(docs) == 1 and vim.fn.readdir(docs) or {}) do
    local file = docs .. "/" .. name
    if name:match("%.md$") then
      local page = name == "README.md" and "index" or name:gsub("%.md$", "")
      local in_code = false
      for lnum, line in ipairs(vim.fn.readfile(file)) do
        -- Headings inside code blocks are examples, not sections.
        if line:match("^%s*```") then in_code = not in_code end
        local heading = not in_code and line:match("^#+%s+(.+)")
        if heading then
          local entry = ("pure %s › %s"):format(page, heading)
          if not targets[entry] then
            table.insert(entries, entry)
            targets[entry] = { file = file, lnum = lnum }
          end
        end
      end
    end
  end

  for _, name in ipairs(vim.fn.readdir(vim.fn.expand("$VIMRUNTIME/doc"))) do
    if name:match("%.txt$") then table.insert(entries, name) end
  end

  pickList(entries, { title = "Help" }, function(selection)
    local target = targets[selection]
    if not target then return vim.cmd("help " .. vim.fn.fnameescape(selection)) end
    vim.cmd("split " .. vim.fn.fnameescape(target.file))
    vim.api.nvim_win_set_cursor(0, { target.lnum, 0 })
    vim.cmd("normal! zt")
  end)
end

function M.fuzzyGit()
  local path = vim.fn.expand("%:p:h")

  local fzf = "fzf --ansi --preview 'git show --color=always {1}' --preview-window 'up,60\\%,wrap,border-bottom'"
  local git = "git log --oneline --color=always "

  M.fuzzyLogic({
    title = "Fuzzy Git log",
    ratio = 0.8,
    cmd = string.format("cd %s && %s | %s", vim.fn.shellescape(path), git, fzf),
    -- The selection is "abc1234 commit message"; it used to be passed to
    -- :edit, which opened an empty file named after the commit. Show the
    -- commit instead, in a scratch split (q closes it).
    callback = function (selection)
      local sha = selection:match("^(%x+)")
      if not sha then return end
      local out = vim.fn.systemlist({ "git", "-C", path, "show", "--stat", "--patch", sha })
      vim.cmd("botright new")
      local buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
      vim.bo[buf].filetype = "git"
      vim.bo[buf].modifiable = false
      vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
    end
  })
end


function M.fuzzyGitGrep()
  local git_grep = "git grep --line-number --column"
  local fzf = "fzf --ansi --delimiter : --preview '" .. tool("bat", "batcat") .. " --style=numbers --color=always --highlight-line {2} {1}' --preview-window 'up,60\\%,border-bottom,+{2}+3/3'"
  -- Already cd's below, so git grep prints relative names and {1}/{2} line up.
  local path = asDir(vim.fn.expand("%:p:h"))

  M.fuzzyLogic({
    title = "Fuzzy Git Grep",
    ratio = 0.8,
    cmd = string.format("cd %s && %s . | %s", vim.fn.shellescape(path), git_grep, fzf),
    callback = function(selection)
      local rel, line, col_str = selection:match("^(.-):(%d+):(%d+)")
      if not rel then return end
      local col = tonumber(col_str)
      -- Relative to the cd above, so opening it as-is only worked when Neovim's
      -- own cwd happened to match. Rebuild the full name instead.
      local full_path = path .. (rel:gsub("^%.[/\\]", ""))

      vim.cmd("edit! " .. vim.fn.fnameescape(full_path))
      if line and col then
        vim.api.nvim_win_set_cursor(0, {tonumber(line), col - 1}) -- git grep's column is 1-based
      end
      vim.cmd("filetype detect")
    end
  })
end

function M.fuzzyJump()
  local jumps = {}
  for _, jump in ipairs(vim.fn.getjumplist()[1]) do
    local path = vim.api.nvim_buf_get_name(jump.bufnr)
    if path ~= "" then
      table.insert(jumps, string.format("%s:%d:%d", path, jump.lnum, jump.col))
    end
  end

  -- Fields are counted from the END. These lines are "path:line:col", and on
  -- Windows the path starts with a drive letter, so splitting on ":" made {1}
  -- the bare letter "C" and {2} the path -- which bat received where it wanted
  -- a line number, hence "[bat error]: invalid digit found in string".
  -- {-2} is the line and {1..-3} rejoins the whole path, drive letter included.
  pickList(jumps, {
    title = "fuzzy jumps",
    ratio = 0.8,
    fzf = "--ansi --delimiter : --preview '" .. tool("bat", "batcat") .. " --style=numbers --color=always --highlight-line {-2} {1..-3}' --preview-window 'up,60\\%,border-bottom,+{-2}+3/3'",
  }, function(selection)
    -- Windows paths start with a drive letter, so a '^([^:]+):' pattern would
    -- stop at the 'C:' colon; the lazy '.-' matches up to ':line:col'.
    local full_path, line, col = selection:match("^(.-):(%d+):(%d+)")
    if not full_path then return end
    vim.cmd("edit! " .. vim.fn.fnameescape(full_path))
    vim.api.nvim_win_set_cursor(0, { tonumber(line), tonumber(col) })
    vim.cmd("filetype detect")
  end)
end


function M.fuzzyBuffers()
  local buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted and name ~= "" then
      table.insert(buffers, vim.fn.fnamemodify(name, ":."))
    end
  end
  pickList(buffers, { title = "Fuzzy buffers", fzf = "--keep-right --tiebreak=end" }, function(selection)
    vim.cmd("edit " .. vim.fn.fnameescape(selection))
    vim.cmd("filetype detect")
  end)
end

function M.fuzzyOldfiles()
  local oldfiles = vim.tbl_filter(function(f)
    return vim.fn.filereadable(f) == 1
  end, vim.v.oldfiles)
  pickList(oldfiles, { title = "Oldfiles" }, function(selection)
    vim.cmd("edit " .. vim.fn.fnameescape(selection))
    vim.cmd("filetype detect")
  end)
end

function M.fuzzyColorscheme()
  pickList(vim.fn.getcompletion("", "color"), { title = "Colorschemes" }, function(theme)
    vim.cmd("colorscheme " .. vim.fn.fnameescape(theme))
    vim.g.MY_THEME = theme
    if vim.g.neovide then
      vim.api.nvim_set_hl(0, 'Normal', { bg = "#060b1e" })
    end
  end)
end

function M.setup()
  vim.ui.select = function(items, opts, selected)
    opts = opts or {}
    if #items == 0 then
      selected(nil, nil)
      return
    end

    local choices = {}
    for i, item in ipairs(items) do -- Check if table or plain text
      if opts.format_item then
        choices[i] = opts.format_item(item)
      else
        choices[i] = tostring(item)
      end
    end

    -- on_choice(nil, nil) on cancel, as vim.ui.select promises.
    pickList(choices, { title = opts.prompt or "Select" }, function(selection)
      for i, choice in ipairs(choices) do
        if choice == selection then return selected(items[i], i) end
      end
      selected(nil, nil)
    end, function() selected(nil, nil) end)
  end

  vim.ui.input = function(opts, callback)
    opts = opts or {}
    local prompt = opts.prompt or "Input: "
    local win, buf = func.createWindow(prompt, 0.8)
    vim.api.nvim_win_set_height(win, 1)

    if opts.default then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {opts.default})
      vim.cmd("startinsert!")
    end

    local confirmed = false

    local function submit()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      confirmed = true
      local input = table.concat(lines, "\n")
      -- <CR> in insert mode submits: leave insert mode, or the window
      -- underneath is left in it.
      vim.cmd("stopinsert")
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
      callback(input)
    end

    local function cancel()
      -- Marked as handled before the buffer goes: deleting it fires the
      -- BufWipeout below, which called back with nil a second time.
      confirmed = true
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
      callback(nil)
    end

    local opts_map = {noremap = true, silent = true, nowait = true, buffer = buf}
    vim.keymap.set('i', '<CR>', submit, opts_map)
    vim.keymap.set('n', '<CR>', submit, opts_map)

    vim.keymap.set('n', 'q', cancel, opts_map)
    vim.keymap.set('n', '<Esc>', cancel, opts_map)

    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      callback = function()
        if not confirmed then
          callback(nil)
        end
      end
    })


    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
            if opts.default then
                vim.cmd("startinsert!")
            else
                vim.cmd("startinsert")
            end
        end
    end, 10)
  end
end

function M.NewFile(path)
  path = asDir(path)
  local fd = tool("fd", "fdfind") .. " --hidden " .. fdExcludes() .. " --type directory . --strip-cwd-prefix --base-directory  "
  local fzf = "fzf --keep-right --tiebreak=end"
  M.fuzzyLogic({
    title = "Select New File Path",
    ratio = 0.6,
    cmd = string.format("%s %s | %s", fd, vim.fn.shellescape(path), fzf),
    callback = function(selection)
      vim.ui.input({prompt = "New file name: "}, function(input)
        if input and input ~= "" then
          vim.cmd("edit! " .. vim.fn.fnameescape(path .. selection .. "/" .. input))
        else
          -- was `path .. selection` .. "Untitled" -> ".../dirUntitled"
          vim.cmd("edit! " .. vim.fn.fnameescape(path .. selection .. "/Untitled"))
        end
      end)
    end
  })
end

function M.CompilerCommand()
  vim.ui.input({prompt = "Compiler Command:"}, function(input)
    if input and input ~= "" then
      terms.toggleTerminal(input, 0.6)
    end
  end)
end

---@param path string|nil The directory path to explore. If nil, uses current working directory.
function M.fuzzyExplorer(path)
  if path == nil then path = vim.fn.getcwd() end

  -- Use ls -ap to show hidden files and classify with indicators (/ for dirs)
  local list_cmd = lsList()

  -- Preview command for fzf. It's executed in `path` directory.
  -- Added --line-range to bat to avoid lagging on large files.
  -- POSIX 'if/then/fi'. This was fish syntax ("if ...; ...; else ...; end"),
  -- which the bash 'shell' set in init.lua rejects, so the preview pane only
  -- ever rendered a syntax error.
  local preview_cmd = "if [ -d {} ]; then " .. lsPreview() .. " {}; else " .. tool("bat", "batcat")
    .. " --color=always --style=numbers --line-range :500 {}; fi"
  local fzf_cmd = string.format("fzf --ansi --preview='%s' --print-query", preview_cmd)

  M.fuzzyLogic({
    title = "Explorer: " .. path,
    ratio = 0.8,
    cmd = string.format("cd %s && %s | %s", vim.fn.shellescape(path), list_cmd, fzf_cmd),
          callback = function(selection)
            if not selection or selection == "" or selection == "./" then
              return -- Do nothing
            end
    
            local new_path = vim.fn.resolve(path .. "/" .. selection)
    
            if selection:sub(-1) == '/' then
              -- User intends to create/enter a directory
              if vim.fn.isdirectory(new_path) == 0 then
                -- Directory doesn't exist, create it
                vim.fn.mkdir(new_path, "p")
              end
              -- Enter the directory
              M.fuzzyExplorer(new_path)
            else
              -- User intends to open/create a file
              if vim.fn.isdirectory(new_path) == 1 then
                -- It's an existing directory, but no trailing slash was typed
                -- so we enter it instead of trying to edit it as a file.
                M.fuzzyExplorer(new_path)
              else
                -- It's a file (new or existing)
                vim.cmd("edit! " .. vim.fn.fnameescape(new_path))
              end
            end
          end  })
end

-- Exposed for tests.
M._lsList, M._lsPreview, M._tool = lsList, lsPreview, tool
M._setGnuLs = function(v) gnu_ls = v end

return M

