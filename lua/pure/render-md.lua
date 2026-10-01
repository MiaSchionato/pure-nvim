local M = {}

local mdGroup = vim.api.nvim_create_augroup("PureMarkdown", { clear = true})

-- While typing, **bold** and `code` flashed back to their raw marks for one
-- key (Improvment.md). Since Neovim 0.11 treesitter parses asynchronously
-- once a parse takes over 3 ms, which a note with its inline markdown does;
-- the screen was drawn in between, with no highlight yet. Parsing
-- synchronously (vim.g._ts_force_sync_parsing, Neovim's own switch) is only
-- turned on in markdown buffers: notes are small, while a large code file
-- could make every key wait for the parse.
-- FileType too: a buffer made markdown after it was entered (:set ft=markdown)
-- got it only on the next BufEnter. Only for the current buffer, or a buffer
-- loaded in the background would decide for the one being edited.
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
  group = mdGroup,
  callback = function(args)
    if args.buf ~= vim.api.nvim_get_current_buf() then return end
    vim.g._ts_force_sync_parsing = vim.bo[args.buf].filetype == "markdown" or nil
  end,
})

--- <C-l> in insert mode (mapped below): the last really misspelled word
--- before the cursor on this line becomes the first spelling suggestion.
function M.fixLastWord()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before = line:sub(1, col)
  -- vim.spell.check gives { word, type, 1-based start col }; type 'bad'
  -- only: 'rare', 'local' and 'caps' are left alone.
  local last
  for _, hit in ipairs(vim.spell.check(before)) do
    if hit[2] == 'bad' then last = hit end
  end
  if not last then return vim.notify('No misspelled word before the cursor') end
  local word, start = last[1], last[3] - 1
  local fix = vim.fn.spellsuggest(word, 1)[1]
  if not fix then return vim.notify('No suggestion for "' .. word .. '"') end
  vim.api.nvim_buf_set_text(0, row - 1, start, row - 1, start + #word, { fix })
  vim.api.nvim_win_set_cursor(0, { row, col + #fix - #word })
end


vim.api.nvim_create_autocmd("FileType", {
  group = mdGroup,
  pattern =  "markdown",
  callback = function(args)
    vim.opt_local.textwidth = 110
    vim.opt_local.formatoptions = "tcnq"
    vim.opt_local.spell = true

    -- Only enable languages whose word list is actually present. A missing one
    -- makes Neovim warn ('Cannot find word list "pt.utf-8.spl"') every single
    -- time a markdown buffer opens, and prompt to download it.
    -- Brazilian Portuguese: with the region, European spellings ("facto")
    -- are marked as regional words. vim.g.pure_spelllang overrides the list.
    local wanted = vim.g.pure_spelllang or { "pt_br", "en", "it" }
    local available = {}
    for _, lang in ipairs(wanted) do
      local base = lang:gsub("_.*", "")   -- 'pt_br' looks for 'pt.<enc>.spl'
      if vim.fn.globpath(vim.o.runtimepath, "spell/" .. base .. ".*.spl") ~= "" then
        table.insert(available, lang)
      end
    end
    vim.opt_local.spelllang = #available > 0 and available or { "en" }
    -- Better suggestions: "best" ranks by closeness across the three
    -- languages, and 9 keeps z= on one screen. camel checks each part of
    -- camelCase words instead of flagging the whole word.
    vim.opt_local.spellsuggest = "best,9"
    vim.opt_local.spelloptions = "camel"
    -- No "kspell" in 'complete': with autocomplete on, every word typed would
    -- open a menu of dictionary words, and <CR> now takes its first item.

    -- Keep indentation
    vim.opt_local.autoindent = true
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc" -- Hide in normal and command modes

    -- Style links
    vim.api.nvim_set_hl(0, "@markup.heading.1.markdown", { link = "Title" })
    vim.api.nvim_set_hl(0, "@markup.heading.2.markdown", { link = "Directory" })
    vim.api.nvim_set_hl(0, "@markup.heading.3.markdown", { link = "Type" })
    vim.api.nvim_set_hl(0, "@markup.heading.4.markdown", { link = "Special" })
    -- Checkbox colours are fixed in pure/mdview.lua (PureMdTask*), not here.

    -- Headings, bullets, checkboxes and the rest are drawn by pure/mdview.lua.
    -- The regex conceals that used to be here matched inside code blocks too,
    -- and matchadd() is per window, so they piled up on every FileType.

    -- Keymaps
    vim.keymap.set("n", "<leader>ft", "'[,']!column -t -s '|' -o '|'", {buffer = true}) -- Table format
    vim.keymap.set("n", "<leader>ds", "z=", {buffer = true}) -- Dictionary suggert
    vim.keymap.set("n", "<leader>dg", "zg", {buffer = true}) -- Dictionary Good (Add word to dictionary)
    vim.keymap.set("n", "<leader>dw", "zw", {buffer = true}) -- Dictionary Wrong (word)
    vim.keymap.set("n", "<leader>dp", "[s", {buffer = true}) -- Dictionary previous misspelled word
    vim.keymap.set("n", "<leader>dn", "]s", {buffer = true}) -- Dictionary next misspelled word
    -- Autocorrect on demand: <C-l> in insert mode replaces the last misspelled
    -- word before the cursor, on this line, with the first suggestion, and
    -- the cursor stays where it was (moved by the length difference). Undo
    -- (u) takes back just the correction, thanks to the <C-g>u around it.
    -- Added for Improvment.md in the vault: a fix meant leaving insert mode.
    --
    -- The first version was <Esc>[s1z=`]a, which did not work well: [s also
    -- stops on rare and regional words (many, with three languages on) and
    -- "fixed" correct ones; with no bad word on the line it wrapped around
    -- the file and changed a word far away; and leaving insert mode moved
    -- the cursor. This only looks at this line, before the cursor, at words
    -- that are really wrong.
    vim.keymap.set("i", "<C-l>", function()
      return "<C-g>u<Cmd>lua require('pure.render-md').fixLastWord()<CR><C-g>u"
    end, { buffer = true, expr = true, desc = "Fix the last misspelled word" })
    vim.keymap.set("n", "<leader>tx", require('configs.functions').toggleCheckbox, { buffer = true, desc = "Alternar Checkbox" })
    -- Obsidian's extra states, in notes only: the Todoist list is markdown too
    -- (a buffer with buftype set), but Todoist knows just [ ] and [x].
    if vim.bo[args.buf].buftype == "" then
      vim.keymap.set("n", "<leader>x", require('configs.functions').cycleCheckbox,
        { buffer = args.buf, desc = "Cycle checkbox state" })
    end
  end
})


return M
