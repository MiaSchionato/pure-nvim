# Pickers (`lua/pure/fuzzyUtils.lua`)

Every picker is [fzf](https://github.com/junegunn/fzf) running in a floating
terminal; the choice comes back to Neovim when fzf exits. Needs `fzf`, `fd`,
`rg` and `bat` (preview) installed. On Windows they run through Git bash (the
`windows` branch sets that up).

In any picker: type to filter, arrows or `Ctrl-j` / `Ctrl-k` to move, `Enter`
to pick, `Esc` to cancel (a single `Esc` always closes the picker, even with a global terminal-mode `Esc` that leaves terminal mode). (Arrows are turned into `Ctrl-k` / `Ctrl-j`
before they reach fzf: on Windows an arrow's escape sequence could arrive
split and make fzf quit.)

| Key | Picker | Searches |
|---|---|---|
| `<leader>ff` | files | four folders above the current file |
| `<leader><leader>` | files | two folders above |
| `<leader>fn` / `f.` / `f~` / `fa` | files | nvim config / `~/.config` / home / the Obsidian vault |
| `<leader>fg` | **live grep** | two folders above; see below |
| `<leader>gg` | git grep | the repository of the current file |
| `<leader>fb` | buffers | open buffers |
| `<leader>f/` | recent files | `:oldfiles` |
| `<leader>fj` | jump list | with a preview of the spot |
| `<leader>f"` | registers | every register with text; `Enter` makes it the unnamed register (the one `p` pastes) |
| `<leader>fh` | help | Neovim's help files and every section of these docs (`pure todoist › …`) |
| `<leader>fc` | colorschemes | the choice is remembered across restarts; **omarchy** (first) follows the Omarchy theme |
| `<leader>fe` | explorer | walk folders; type a new name to create a file, or `name/` for a folder |
| `<leader>gl` | git log | shows the picked commit in a split (`q` closes) |
| `<leader>n…` | new file | straight into its folder, asking only the name (`nh` home, `n.` ~/.config, `nn` nvim, `ne` here; `vim.g.pure_new_file_ask_name = false`: an unnamed buffer there instead). `nf` picks the folder first; `nv` is a note in the vault's inbox; `nd` a new folder here |

**One look for every picker** (`lua/pure/pickerstyle.lua`): the style of `<leader>vf` (the Flora
finder). The name is in colour on the left (`PureNoteFile`), then, dim to the right (`PureNoteSep`),
its folder and how long ago it was written. What you type matches the name, the folder and the age.
The full path (and the line) ride along as hidden fields. Files (`ff`, `fn`, `f.`, `f~`), recent files
(`f/`), buffers (most recently used first), the jump list, help (page › section), registers and
colorschemes draw their lines this way. In the file search the age is the time since the last
modification (`2h 0m ago`, `3d 2h ago`, as Dired does), but only for the recently changed files
(`vim.g.pure_fuzzy_recent`, below): reading the time of every file takes minutes in a big tree, so
the older ones read `14d+ ago`. The line is drawn by an `awk` at the end of the `fd` pipe. Live grep colours ripgrep's
output with the same groups: the file in the name colour, the numbers dim, the match in the alias
colour. The git log and the explorer keep the colours of `git` and `ls`.

**Live grep** (`<leader>fg`): nothing is listed until you type; ripgrep runs
again on every change of the query (a regular expression; case-sensitive
only if you type a capital letter). The preview shows the match in its file;
`Enter` opens it at that line and column.

In the vault (`<leader>vf`, `<leader>vg`, `<leader>fv`) the pickers ignore
the vault's `.gitignore`, so a private folder kept out of git is still
found. Everywhere else `.gitignore` is honoured (no `node_modules`).

**Hidden files** (the file search and the folder picker of `<leader>nf`):
what is under a folder starting with `.` (`.cache`, `.local`…) and dotfiles
are left out, except `.config`, which is always listed. Start the query with
`.` and the list switches to everything, hidden included (the prompt
becomes `.>`); erase the `.` and it switches back. `.git` and
`vim.g.pure_fuzzy_ignore` stay out either way.

**Symlinked folders** (`~/windows`, `~/D` in WSL): a link sitting directly in
the folder searched, or in its `.config`, is followed three levels deep, and
the link itself is offered as a folder. Deeper is left out on purpose: such a
link can lead to a whole Windows home or a whole drive; open the picker
inside it (`<leader>nf`, `<leader>fe`) to go further.

**`vim.ui.select`** – any plugin asking to pick from a list (code actions,
the template picker…) gets this same fzf window.
**`vim.ui.input`** – questions get a small floating window (`Enter` answers,
`Esc` / `q` cancels).

## Settings

```lua
-- folders never listed by the file pickers
vim.g.pure_fuzzy_ignore = { '.git', '.obsidian', 'node_modules' }
-- the file pickers list what changed within this time first, the newest on top ('14d' default; false: off)
vim.g.pure_fuzzy_recent = '14d'
```

**Recent first.** In the file pickers the files edited lately are on top, the newest first, then all
the others (so with nothing typed you see what you were working on; when you type, the best match
still wins and, between equal matches, the newer file wins). fd cannot sort, so it lists what
changed within `vim.g.pure_fuzzy_recent` (`fd --changed-within`) through `ls -t`, then the rest. The
recent files, buffers (last used first) and the Flora finder (`<leader>vf`, notes written last first)
already worked this way.

## Adding a picker

`M.fuzzyLogic({ title, ratio, cmd, callback, on_cancel })` runs any shell
pipeline ending in fzf and calls `callback(line)` with the choice. For a
plain list of strings, `pickList(lines, { title }, on_pick)` does the rest
(temporary file included).
