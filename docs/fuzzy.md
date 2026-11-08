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
| `<leader>ft` | **TODO:** | every `TODO:` of the repository (walks up to a `.git`; with none, the folder and 3 levels down); see below |
| `<leader>f"` | registers | every register with text; `Enter` makes it the unnamed register (the one `p` pastes) |
| `<leader>fh` | help | Neovim's help files and every section of these docs (`pure todoist › …`) |
| `<leader>fc` | colorschemes | the choice is remembered across restarts; **omarchy** (first) follows the Omarchy theme |
| `<leader>fe` | explorer | walk folders; type a new name to create a file, or `name/` for a folder |
| `<leader>gl` | git log | shows the picked commit in a split (`q` closes) |
| `<leader>n…` | new file | straight into its folder, asking only the name (`nh` home, `n.` ~/.config, `nn` nvim, `ne` here; `vim.g.pure_new_file_ask_name = false`: an unnamed buffer there instead). `nf` picks the folder first; `nv` is a note in the vault's inbox; `nd` a new folder here |

**One look for every picker** (`lua/pure/pickerstyle.lua`): the style of `<leader>vf` (the vault
finder). The name is in colour on the left (`PureNoteFile`), then, dim to the right (`PureNoteSep`),
its folder and how long ago it was written. What you type matches the name, the folder and the age.
The full path (and the line) ride along as hidden fields. Files (`ff`, `fn`, `f.`, `f~`), recent files
(`f/`), buffers (most recently used first), the jump list, help (page › section), registers and
colorschemes draw their lines this way. In the file search the age column is the tier the file is in
(`<1h ago`, `<1d ago`, `<7d ago`, `7d+ ago`; see "Recent first" below), not the exact time: reading the
time of every file took minutes in a big tree and froze the picker. Buffers and recent files show the
exact time (`2h 0m ago`, as Dired does). The file search line is drawn by an `awk` at the end of the
`fd` pipe. Live grep colours ripgrep's
output with the same groups: the file in the name colour, the numbers dim, the match in the alias
colour. The git log and the explorer keep the colours of `git` and `ls`.

**TODO:** (`<leader>ft`): lists every `TODO:` (the plain text a snippet puts in code or notes; not
org.nvim's keyword, so each note and file keeps its own). The scope is the repository: from the folder
of the current file it walks up to a `.git` and searches the whole repo. With no repository it
searches the folder of the file and the subfolders down to `vim.g.pure_todo_depth` levels (3). The
files written last come first. Each line is the text of the TODO, then the file, the line and how long
ago the file changed; typing filters all of that, the preview shows the spot, `Enter` jumps to it.
`vim.g.pure_todo_pattern` is the regex (`'TODO:'`; `'TODO:|FIXME:'` adds another).

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
`vim.ui.select` also takes `sort = true` (rank the matches by fzf's score instead of
the caller's order: `<leader>vm`'s long list of notes). Both take an extra `ratio` in their options (the size of the window, as
`createWindow`'s): the org capture passes one so its lists, questions and capture
buffer have the same width and top edge ([org.md](org.md)). Unset, nothing changes.

## Settings

```lua
-- folders never listed by the file pickers
vim.g.pure_fuzzy_ignore = { '.git', '.obsidian', 'node_modules' }
-- besides vim.g.pure_fuzzy_ignore, these are never listed either (default: node_modules, __pycache__,
-- .venv, venv, site-packages and **/pkg/mod, the Go module cache); {} for none
vim.g.pure_fuzzy_ignore_extra = { 'node_modules', '__pycache__', '.venv', 'venv', 'site-packages', '**/pkg/mod' }
-- the file pickers list what changed within these limits first, tier by tier ({ '1h', '1d', '7d' } is the
-- default, a single string works too; false: off)
vim.g.pure_fuzzy_recent = { '1h', '1d', '7d' }
```

**Recent first.** In the file pickers the files edited lately are on top, then all the others (so with
nothing typed you see what you were working on; when you type, the best match still wins and, between
equal matches, the earlier one in the list wins). fd cannot sort and reading the time of every file takes
minutes, so the list is made in tiers, one fd run each (`--changed-within 1h`, then changed within 1d and
before 1h, ... then everything older than the last limit); fzf shows the first tier at once while the
others are still being listed. Inside a tier the order is the one of the folder walk. Buffers (last used
first), recent files and the vault finder (`<leader>vf`, notes written last first) are sorted exactly.
The whole home folder (17 000 files) is listed in under a second; an earlier version that read the time
of every recent file took over a minute.

**The folder a picker starts from** is that of the current file (`<leader>ff` four levels up, `<leader>fg`
and `<leader>nf` one level up, the TODO, git log and git grep pickers the folder itself). In the scratch
note (it lives in Neovim's data folder, nowhere to search) the window remembers the folder it was
opened from: that of the file the window showed before, or of the previous tab's file for a new tab, or
the working folder (`pure/scratch.lua`, `require('pure.scratch').dir(levels)`).

## Adding a picker

`M.fuzzyLogic({ title, ratio, cmd, callback, on_cancel })` runs any shell
pipeline ending in fzf and calls `callback(line)` with the choice. For a
plain list of strings, `pickList(lines, { title }, on_pick)` does the rest
(temporary file included).
