local mdGroup = vim.api.nvim_create_augroup("PureMarkdown", { clear = true})


vim.api.nvim_create_autocmd("FileType", {
  group = mdGroup,
  pattern =  "markdown",
  callback = function ()
    vim.opt_local.textwidth = 110
    vim.opt_local.formatoptions = "tcnq"
    vim.opt_local.spell = true

    -- Only enable languages whose word list is actually present. A missing one
    -- makes Neovim warn ('Cannot find word list "pt.utf-8.spl"') every single
    -- time a markdown buffer opens, and prompt to download it.
    local wanted = { "pt_br", "en", "it" }
    local available = {}
    for _, lang in ipairs(wanted) do
      local base = lang:gsub("_.*", "")   -- 'pt_br' looks for 'pt.<enc>.spl'
      if vim.fn.globpath(vim.o.runtimepath, "spell/" .. base .. ".*.spl") ~= "" then
        table.insert(available, lang)
      end
    end
    vim.opt_local.spelllang = #available > 0 and available or { "en" }
    -- vim.opt_local.complete:append("kspell")

    -- Keep indentation
    vim.opt_local.autoindent = true
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc" -- Hide in normal and command modes

    -- Style links
    vim.api.nvim_set_hl(0, "PureMdUnchecked", { link = "Comment", default = false })
    vim.api.nvim_set_hl(0, "PureMdChecked", { link = "String", default = false })
    vim.api.nvim_set_hl(0, "@markup.heading.1.markdown", { link = "Title" })
    vim.api.nvim_set_hl(0, "@markup.heading.2.markdown", { link = "Directory" })
    vim.api.nvim_set_hl(0, "@markup.heading.3.markdown", { link = "Type" })
    vim.api.nvim_set_hl(0, "@markup.heading.4.markdown", { link = "Special" })
    vim.api.nvim_set_hl(0, "PureMdChecked", { link = "String", default = true }) vim.api.nvim_set_hl(0, "PureMdUnchecked", { link = "Comment", default = true })

    -- Conceal markers for a cleaner look using Treesitter groups
    vim.fn.matchadd("Conceal", [[^#\+\s]], 10, -1, { conceal = "" })
    vim.fn.matchadd("Conceal", [[^-\ze\s]], 10, -1, { conceal = "•" })
    vim.fn.matchadd("Conceal", [[`]], 10, -1, { conceal = "" })
    vim.fn.matchadd("Conceal", '-\\s\\[\\s\\]', 10, -1, { conceal = "󰄱" })
    vim.fn.matchadd("Conceal", '-\\s\\[[xX]\\]', 10, -1, { conceal = "󰄲" })
    vim.fn.matchadd("Comment", [[^\s*-\s\[[xX]\].*$]], 9, -1)

    -- Keymaps
    vim.keymap.set("n", "<leader>ft", "'[,']!column -t -s '|' -o '|'", {buffer = true}) -- Table format
    vim.keymap.set("n", "<leader>ds", "z=", {buffer = true}) -- Dictionary suggert
    vim.keymap.set("n", "<leader>dg", "zg", {buffer = true}) -- Dictionary Good (Add word to dictionary)
    vim.keymap.set("n", "<leader>dw", "zw", {buffer = true}) -- Dictionary Wrong (word)
    vim.keymap.set("n", "<leader>dp", "[s", {buffer = true}) -- Dictionary previous misspelled word
    vim.keymap.set("n", "<leader>dn", "]s", {buffer = true}) -- Dictionary next misspelled word
    vim.keymap.set("n", "<leader>tx", require('configs.functions').toggleCheckbox, { buffer = true, desc = "Alternar Checkbox" })
  end
})

