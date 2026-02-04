local map = vim.keymap.set
local term = require('pure.terms')
local func = require('configs.functions')
local fzf = require('pure.fuzzyUtils')
local sur = require('pure.surround')
local zet = require('pure.zettelkasten')
local lsp = vim.lsp.buf
local diag = vim.diagnostic
local opts = {noremap = true, silent = true }
local expr_opts = {expr = true, noremap = true, silent = true }

vim.g.mapleader = ' '

-- SPLIT View
map('n', "<leader>vl", "<C-w>l", func.getOpts(opts,"Windows Movments" ))
map('n', "<leader>vh", "<C-w>h", func.getOpts(opts,"Windows Movments" ))
map('n', "<leader>vj", "<C-w>j", func.getOpts(opts,"Windows Movments" ))
map('n', "<leader>vk", "<C-w>k", func.getOpts(opts,"Windows Movments" ))

-- Basics
-- map({ 'n', 'v' }, ";", ":")
-- map({ 'n', 'v' }, ":", ";")
map('n', "Y", "y$", opts)
map('n', "q;", "q:", opts)
map({'n','v','o'}, "gl", "$", opts)
map({'n', 'v', 'o'}, "gh", "^", opts)
map('n', "ge", "G", opts)

map('n', "=", "<cmd>foldopen<cr>", opts)
map('n', "+", "<cmd>foldclose<cr>", opts)

map("n", "<leader>x", "<cmd>so<cr>", opts)

map("n", "U", "<C-r>", opts)

-- Window Tab mappings
map('n', "<leader>wn", "<cmd>tabnew<CR>", func.getOpts(opts, "New Tab" ))
map('n', "<leader>wl", "<cmd>tabnext<CR>", func.getOpts(opts, "Next Tab" ))
map('n', "<leader>wh", "<cmd>tabprevious<CR>", func.getOpts(opts, "Previous Tab" ))
map('n', "<leader>wq", "<cmd>tabclose<CR>", func.getOpts(opts, "Close Tab" ))
map('n', "<leader>wo", "<cmd>tabonly<CR>", func.getOpts(opts, "Close all other Tabs" ))

-- == Files mappings ==
map('n', '<leader><leader>', fzf.fuzzyExplorer , func.getOpts(opts, "Explore current directory" ))

map('n', '<leader>e', function ()
local ok =  pcall(fzf.yaziExplorer, vim.fn.expand("%:p:h").."/")
  if not ok then
    fzf.fuzzyExplorer(vim.fn.expand("%:p:h").."/")
  end
end, func.getOpts(opts, "Explore current directory" ))

map("n", "<leader>E",function()
local ok = pcall(fzf.yaziExplorer,"/Users/mia/")
  if not ok then
    fzf.fuzzyExplorer("/Users/mia/")
  end
end, func.getOpts(opts, "Explore Home Directory"))

map("n", "<leader>et",function()
local ok = pcall(fzf.fuzzyExplorer,"/tmp/")
if not ok then
  fzf.fuzzyExplorer("/tmp/")
end
end, func.getOpts(opts, "Explore tmp Directory"))

map("n", "<leader>ep",function()
local ok = pcall(fzf.fuzzyExplorer,"/Users/mia/Projects/")
if not ok then
  fzf.fuzzyExplorer("/Users/mia/Projects/")
end
end, func.getOpts(opts, "Explore Projects Directory"))

map("n", "<leader>en",function()
local ok = pcall(fzf.fuzzyExplorer,"/Users/mia/.config/nvim/")
if not ok then
  fzf.fuzzyExplorer("/Users/mia/.config/nvim/")
end
end, func.getOpts(opts, "Explore Nvim config Directory"))

map("n", "<leader>el",function()
local ok = pcall(fzf.fuzzyExplorer,"/Users/mia/Documents/MyJourney/Languages/")
if not ok then
  fzf.fuzzyExplorer("/Users/mia/Documents/MyJourney/Languages/")
end
end, func.getOpts(opts, "Explore Languages Directory"))

map('n', "<leader>e.",function()
local ok = pcall(fzf.fuzzyExplorer,"/Users/mia/.config/")
if not ok then
  fzf.fuzzyExplorer("/Users/mia/.config/")
end
end, func.getOpts(opts, "Explore Directory"))

map('n', "<leader>em",function()
local ok = pcall(fzf.fuzzyExplorer,"/Users/mia/Documents/MindGarden/")
if not ok then
  fzf.fuzzyExplorer("/Users/mia/Documents/MindGarden/")
end
end, func.getOpts(opts, "Explore Directory"))


-- == Fuzzy Search ==
-- Fuzzy Search Directories
map("n", "<leader>f~",function()fzf.fuzzySearch("/Users/mia/")end, func.getOpts(opts, "Fuzzy Search Home Directory"))
map("n", "<leader>ff",function()fzf.fuzzySearch(vim.fn.expand("%:p:h:h").."/")end, func.getOpts(opts, "Fuzzy Search Home Directory"))
map("n", "<leader>fp",function()fzf.fuzzySearch("/Users/mia/Projects/")end, func.getOpts(opts, "Fuzzy Search Projects Directory"))
map("n", "<leader>fn",function()fzf.fuzzySearch("/Users/mia/.config/nvim/")end, func.getOpts(opts, "Fuzzy Search Nvim config Directory"))
map("n", "<leader>fl",function()fzf.fuzzySearch("/Users/mia/Documents/MyJourney/Languages/")end, func.getOpts(opts, "Fuzzy Search Languages Directory"))
map('n', "<leader>f.",function()fzf.fuzzySearch("/Users/mia/.config/")end, func.getOpts(opts, "Fuzzy .Config Directory"))
map('n', "<leader>fm",function()fzf.fuzzySearch("/Users/mia/Documents/MindGarden/")end, func.getOpts(opts, "Fuzzy .Config Directory"))

-- Fuzzy Grep
map('n', "<leader>fg", function() fzf.fuzzyGrep(vim.fn.expand('%:p:h:h'))end, func.getOpts(opts, "Fuzzy Grep"))
-- Fuzzy Searchs
map('n', "<leader>f/", function() fzf.fuzzyOldfiles()end,func.getOpts(opts, "Fuzzy Oldfiless"))
map('n', "<leader>fh", function() fzf.fuzzyHelp()end, func.getOpts(opts, "Fuzzy Help"))
map('n', "<leader>fb", function() fzf.fuzzyBuffers()end,func.getOpts(opts, "Fuzzy Buffers"))
map('n', "<leader>fj", function() fzf.fuzzyJump()end,func.getOpts(opts, "Fuzzy Jumps"))
map('n', '<leader>fc', fzf.fuzzyColorscheme, func.getOpts(opts, "Fuzzy Colorschemes"))
map('n', '<leader>fgx', zet.insertTemplate , func.getOpts(opts, "Fuzzy Insert Templates"))
-- map('n', "<leader>fgx", function() fzf.fuzzy_git_grep()end)

-- New File
map("n", "<leader>nf",function () fzf.NewFile("/" .. vim.fn.expand('%:p:h:h')) end, func.getOpts(opts, "Fuzzy New File home dir"))
map("n", "<leader>nh",function () fzf.NewFile("/Users/mia/") end, func.getOpts(opts, "Fuzzy New File home dir"))
map("n", "<leader>nt",function () fzf.NewFile("/tmp/") end, func.getOpts(opts, "Fuzzy New File scratch dir"))
map("n", "<leader>nm",function () fzf.NewFile("/Users/mia/Documents/MindGarden/") end, func.getOpts(opts, "Fuzzy Search Files"))
map("n", "<leader>np",function () fzf.NewFile("/Users/mia/Projects/") end, func.getOpts(opts, "Fuzzy Search Files"))
map("n", "<leader>nn",function () fzf.NewFile("/Users/mia/.config/nvim/") end, func.getOpts(opts, "Fuzzy Search Files"))
map("n", "<leader>n.",function () fzf.NewFile("/Users/mia/.config/") end, func.getOpts(opts, "Fuzzy Search Files"))
map("n", "<leader>nl",function () fzf.NewFile("/Users/mia/Documents/MyJourney/Languages/") end, func.getOpts(opts, "Fuzzy Search Files"))



-- Git stuff
map('n', "<leader>gl", fzf.fuzzyGit, func.getOpts(opts,"Git Fuzzy Logs"))
map('n', "<leader>gg", fzf.fuzzyGitGrep, func.getOpts(opts,"Git Grep"))
map('n', "<leader>gd", func.gitDiffToggle, func.getOpts(opts,"Git Diff"))

-- == Visual mode mappings ==
map('v', "<leader>s", [[:s/\%V]], {desc =  "Substitute selected" })
map('v', "<leader>n", [[:norm]], func.getOpts(opts, "Norm mode" ))
map('v', "<leader>v", [[:s/\v]], func.getOpts(opts, "Very magic mode" ))
map('n', "vv", 'viw', func.getOpts(opts, "Select line" ))

map('v', "J", '5j', func.getOpts(opts, "Down 5 lines " ))
map('v', "K", '5k', func.getOpts(opts, "Up 5 lines " ))
-- Better indenting in visual mode
map('v', "<", "<gv", func.getOpts(opts, "Indent left and reselect" ))
map('v', ">", ">gv", func.getOpts(opts, "Indent right and reselect" ))

-- == Normal mode mappings ==
map('n', "<leader>p", '"*p', func.getOpts(opts, "Clipboard Paste" ))
map("x", "<leader>p", [["_dP]])
map({ 'n', "v" }, "<leader>y", '"*y', func.getOpts(opts, "Clipboard Paste" ))
map({ 'n', "v" },"<leader>dd", '"D', func.getOpts(opts, "Delete without yanking" ))

map("n", "<leader>xf", "<cmd>!chmod +x %<CR>", {})
map('n', "<leader>r", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], {desc = "Rename selected word"})
map("n", "gj", "<C-d>")
map("n", "gk", "<C-u>")

map('n', '<C-f>', '<C-d>', opts)
map('n', '<', 'V<', opts)
map('n', '>', 'V>', opts)

-- == Insert mode mappings ==
-- map('i', "jf", "<Esc>", func.get_opts(opts, "Normal mode with jf" ))

-- Comments
map('n', "<leader>ct", 'oTODO:<esc>:normal gcc<cr>A')

-- Code 
map('n', "<leader>cc", fzf.CompilerCommand)

-- Buffer navigation
map('n', "<leader>bn", "<cmd>bnext<CR>", func.getOpts(opts, "Next buffer" ))
map('n', "<leader>bp", "<cmd>bprevious<CR>", func.getOpts(opts, "Previous buffer" ))
map('n', "<leader>bq", "<cmd>bdelete<CR>", func.getOpts(opts, "Delete buffer" ))
map('n', "<leader>bv", "<cmd>buffers<CR>", func.getOpts(opts, "View buffer" ))
map('n', "<leader>bo", "<cmd>%bd|e#<cr>", func.getOpts(opts, "Close all buffers and reload previous" ))

-- Surround mappings
map("n", "s", function() sur.applySurround(false) end, { desc = "Surround word" })
map("v", "s", function() sur.applySurround(true) end, { desc = "Surround selection" })
-- functions
map("n", "sf", function() sur.surroundFunction(false) end, { desc = "Surround with function" })
map("v", "sf", function() sur.surroundFunction(true) end, { desc = "Surround with function" })
-- delete surrounds
map("n", "ds", sur.deleteSurround, { desc = "Delete surround" })
-- changing surrounds
map("n", "cs", sur.changeSurround, { desc = "Change surround" })

-- Splitting & Resizing
map('n', "<leader>sv", "<cmd>vsplit<CR>", func.getOpts(opts, "Split window vertically" ))
map('n', "<leader>sh", "<cmd>split<CR>", func.getOpts(opts, "Split window horizontally" ))
map('n', "<leader>+", "<cmd>resize +5<CR>", func.getOpts(opts, "Increase window height" ))
map('n', "<leader>-", "<cmd>resize -5<CR>", func.getOpts(opts, "Decrease window height" ))
map('n', "<leader>.", "<cmd>vertical resize -5<CR>", func.getOpts(opts, "Decrease window width" ))
map('n', "<leader>,", "<cmd>vertical resize +5<CR>", func.getOpts(opts, "Increase window width" ))

-- Move lines up/down
map('n', "<up>", ":m .-2<CR>==", func.getOpts(opts, "Move line up" ))
map('n', "<down>", ":m .+1<CR>==", func.getOpts(opts, "Move line down" ))
map('v', "<up>", ":m '<-2<CR>gv=gv", func.getOpts(opts, "Move selection up" ))
map('v', "<down>", ":m '>+1<CR>gv=gv", func.getOpts(opts, "Move selection down" ))

-- Better J behavior
map('n', "J", "mzJ`z", func.getOpts(opts, "Join lines and keep cursor position" ))

-- ==== Terminal mappings ===
-- TODO: make a bottom terminal that can be toggled
-- TODO: make different terminals instances (like tab or split terminals)
map('n', '<leader>tt', term.toggleTerminal, func.getOpts(opts, 'Toggle bottom terminal'))
map('n', '<leader>tg',function () term.toggleTerminal("gemini")end, func.getOpts(opts, 'Toggle Gemini terminal'))
map('t', '<S-esc>', [[<C-\><C-n>]], func.getOpts(opts, 'Close on terminal mode'))


-- LSP actions
map('n', 'K', lsp.hover, func.getOpts(opts, 'LSP Hover' ))
map('n', 'gd', lsp.definition, func.getOpts(opts, 'LSP Definition' ))
map('n', 'gr', lsp.references, func.getOpts( opts,'LSP References' ))
map('n', '<leader>la', lsp.code_action, func.getOpts(opts, 'LSP Code Action' ))
map('n', '<leader>lr', lsp.rename, func.getOpts( opts,'LSP Rename' ))
map("i", "<up>", lsp.signature_help, func.getOpts( opts,'C-h is set as left on my wezterm config' ))
map("n", "<leader>ws",  lsp.workspace_symbol, func.getOpts(opts,' Search workspace symbols') )
map("n", "<leader>d", diag.open_float, func.getOpts(opts,'Open diagnostic\'s floating Window'))

-- Diagnostics
map("n", "[d",  diag.get_prev)
map("n", "]d", diag.get_next)
map('n', '<leader>ld', func.toggleDiagnostics, func.getOpts(opts, 'Toggle Diagnostics' ))

-- Toggles
map('n', '<leader>lz', func.toggleZenMode, func.getOpts(opts, 'Toggle Zen Mode' ))
map('n', '<leader>ls', func.toggleStatusline, func.getOpts(opts,'Toggle Statusline' ))
map('n', '<leader>lt', func.toggleTabline, func.getOpts(opts,'Toggle Tabline'))
map('n', '<leader>lc', func.toggleSigncolumn, func.getOpts(opts,'Toggle Signcolumn'))
map('n', '<leader>lw', '<cmd>set wrap!<cr>',func.getOpts(opts,'Toggle Signcolumn'))
map('n', '<leader>li', func.toggleInlayHints, func.getOpts(opts,'Toggle Inlay Hints'))
map('n', '<leader>tp', func.toggleCopilot, func.getOpts(opts,'Toggle GitHub Copilot'))

-- highlights
map('n', '<leader>h', func.toggleWordHighlight, {desc = "Toggle Word Highlight"})
map('n', "<leader>cl", func.toggleHighlightSearch, func.getOpts(opts, "Clear search highlights" ))

 -- toggle number / relative line number 
map({ 'n', 'v' }, '<leader>lrn', func.toggleRelativenumber, func.getOpts(opts, ' Toggle relativenumber'))
map({ 'n', 'v' }, '<leader>ln', function () func.toggleNumber() func.toggleRelativenumber() end, func.getOpts(opts, 'Toggle relativenumber'))

-- Snippets
-- map('i', '<Right>', func.snippetJumpNext, func.getOpts(expr_opts, 'Jump to the next arg on snippets'))
-- map('i', '<Left>', func.snippetJumpPrev, func.getOpts(expr_opts, ' Jump to the previous arg on snippets'))
-- map('i', '<Esc>', func.snippetStop, func.getOpts(opts, 'Close snippet'))
map("n", "<leader>ie", "oif err != nil {<CR>}<Esc>Oreturn err<Esc>")


--  Undotree
map( 'n' , '<leader>u',
function ()
  vim.cmd('packadd nvim.undotree')
  vim.cmd('Undotree')
end, func.getOpts(opts, "Builtin Undotree plugin"))



-- Folding
vim.keymap.set("n", "<Space>zz", "za", { desc = "Alternar Dobra" })       -- Abre/Fecha atual
vim.keymap.set("n", "<Space>zo", "zR", { desc = "Abrir Todas Dobras" })  -- Open All
vim.keymap.set("n", "<Space>zc", "zM", { desc = "Fechar Todas Dobras" }) -- Close All




-- debug
map({ 'v', 'n' }, '<leader>in', ':Inspect<cr>')
map('v', '<leader>ldb', 'y:lua print(<C-r>")<cr>')
map('n', '<leader>cn', ':colorscheme nightfly<cr>')

-- teste
map('n', '<leader>fx', fzf.fuzzyColorscheme )





-- ============================================================================================================
-- textobjects
-- ============================================================================================================

map({'x', 'o'}, 'is', 'i[',{expr = true, desc = "Inner Square Brackets []"})
map({'x', 'o'}, 'as', 'a[',{expr = true, desc = "Outer Square Brackets []"})

map({'x', 'o'}, 'ic',[[i{]],{expr = true, desc = "Inner Curly Brackets []"})
map({'x', 'o'}, 'ac',[[a}]],{expr = true, desc = "Outer Curly Brackets []"})

map({'x', 'o'}, 'i.',[[is]],{expr = true, desc = "Inner Sentence "})
map({'x', 'o'}, 'a.',[[as]],{expr = true, desc = "Outer Sentence "})

map('n', '<C-p>',[[%]] )


map({'x', 'o'}, 'iq',function ()
  return "i" .. func.smartQuote()
end, {expr = true, desc = "Smart Inner Quotes"})

map({'x', 'o'}, 'aq',function ()
  return "a" .. func.smartQuote()
end, {expr = true, desc = "Smart Outer Quotes"})

-- ============================================================================================================
-- Smart Tab and auto-completes
-- ============================================================================================================


vim.schedule( function()

  map('i', '<tab>', function()
  local pum = vim.fn.pumvisible()
    if pum == 1 then
      return "<C-n>"
    end

    if func.isBlank() then
      return "<tab>"
    end

    if vim.snippet.active({direction = 1}) then
      return "<cmd>lua vim.snippet.jump(1)<cr>"
    end

      return "<right>"
    end, { expr = true, replace_keycodes = true})

  map('i', '<S-tab>', function()
    local pum = vim.fn.pumvisible()
    if pum == 1 then
      return "<C-p>"
    end

    if func.isBlank() then
      return "<S-tab>"
    end

    if vim.snippet.active({direction = 1}) then
      return "<cmd>lua vim.snippet.jump(-1)<cr>"
    end

      return "<left>"
    end, { expr = true, replace_keycodes = true})


  map('i', '<CR>', 'copilot#Accept("\\<CR>")', {
    expr = true,
    replace_keycodes = false
  })
end)

-- vim.keymap.set("i", "<CR>", function()
--   if vim.fn.pumvisible() == 1 then
--     -- Pega os dados do item selecionado antes de fechar o menu
--     local item = vim.fn.complete_info({ "selected" }).items[1]
--
--     -- Se houver algo selecionado e for um snippet (ou vier do scls)
--     if item and item.word ~= "" then
--       vim.schedule(function()
--         -- Tenta expandir o que foi inserido usando o motor nativo
--         -- O scls envia o snippet no corpo, o Neovim 0.10+ detecta automaticamente
--         -- mas as vezes precisa desse trigger se o 'kind' for snippet.
--         vim.snippet.expand(item.word) 
--       end)
--     end
--     return "<C-y>"
--   end
--   return "<CR>"
-- end, { expr = true })
-- ============================================================================================================
--                                                 test
-- ============================================================================================================
