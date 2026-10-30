-- =============================================================================
--  Environment checks that :checkhealth reports
-- =============================================================================

-- Locale. The shell here exports LANG=C.UTF-8 and LC_ALL=C.UTF-8; Windows' C library does not know
-- "C.UTF-8", so Neovim stays in the plain "C" locale and :checkhealth says the locale does not
-- support UTF-8. ".UTF-8" is the system default locale with the UTF-8 code page, which it does know.
-- (Only the character classes change; the text was always UTF-8 inside Neovim.)
if vim.v.ctype == 'C' then
  pcall(vim.cmd, 'language ctype .UTF-8')
end

-- Remote-plugin providers nothing here uses. Neither a plugin nor this configuration talks to Neovim
-- through Node, Perl, Python or Ruby hosts (copilot.vim runs its own node server), so the providers
-- are off instead of being reported as missing at every :checkhealth.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

-- A C/C++ compiler for clangd (which asks the compiler for its system headers) and for org-babel's C
-- blocks. MSYS2 is installed on this machine but its compiler is not on the system PATH; it is added to
-- Neovim's own PATH (nothing outside Neovim changes). Nothing happens when a compiler is already found.
if vim.fn.has('win32') == 1 and vim.fn.executable('gcc') == 0 and vim.fn.executable('clang') == 0 then
  local msys = 'C:/msys64/ucrt64/bin'
  if vim.fn.isdirectory(msys) == 1 then
    vim.env.PATH = (msys:gsub('/', '\\')) .. ';' .. vim.env.PATH
  end
end
