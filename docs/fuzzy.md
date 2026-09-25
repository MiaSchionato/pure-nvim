# Pickers (`lua/pure/fuzzyUtils.lua`)

Every picker is [fzf](https://github.com/junegunn/fzf) running in a floating
terminal; the choice comes back to Neovim when fzf exits. Needs `fzf`, `fd`,
`rg` and `bat` (preview) installed. On Windows they run through Git bash (the
`windows` branch sets that up).

In any picker: type to filter, arrows or `Ctrl-j` / `Ctrl-k` to move, `Enter`
to pick, `Esc` to cancel. (Arrows are turned into `Ctrl-k` / `Ctrl-j`
before they reach fzf: on Windows an arrow's escape sequence could arrive
split and make fzf quit.)

| Key | Picker | Searches |
|---|---|---|
| `<leader>ff` | files | two folders above the current file |
| `<leader><leader>` | files | four folders above |
| `<leader>fn` / `f.` / `f~` / `fa` | files | nvim config / `~/.config` / home / the Obsidian vault |
| `<leader>fg` | **live grep** | two folders above; see below |
| `<leader>gg` | git grep | the repository of the current file |
| `<leader>fb` | buffers | open buffers |
| `<leader>f/` | recent files | `:oldfiles` |
| `<leader>fj` | jump list | with a preview of the spot |
| `<leader>fh` | help | Neovim's help files and every section of these docs (`pure todoist › …`) |
| `<leader>fc` | colorschemes | the choice is remembered across restarts |
| `<leader>fe` | explorer | walk folders; type a new name to create a file, or `name/` for a folder |
| `<leader>gl` | git log | shows the picked commit in a split (`q` closes) |
| `<leader>n…` | new file | same targets as `<leader>f…`: type the name |

**Live grep** (`<leader>fg`): nothing is listed until you type; ripgrep runs
again on every change of the query (a regular expression; case-sensitive
only if you type a capital letter). The preview shows the match in its file;
`Enter` opens it at that line and column.

**`vim.ui.select`** – any plugin asking to pick from a list (code actions,
obsidian.nvim, the template picker…) gets this same fzf window.
**`vim.ui.input`** – questions get a small floating window (`Enter` answers,
`Esc` / `q` cancels).

## Settings

```lua
-- folders never listed by the file pickers
vim.g.pure_fuzzy_ignore = { '.git', '.obsidian', 'node_modules' }
```

## Adding a picker

`M.fuzzyLogic({ title, ratio, cmd, callback, on_cancel })` runs any shell
pipeline ending in fzf and calls `callback(line)` with the choice. For a
plain list of strings, `pickList(lines, { title }, on_pick)` does the rest
(temporary file included).
