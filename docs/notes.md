# Links between notes (`lua/pure/notes.lua`)

What obsidian.nvim did here, in a few hundred lines: follow links, complete
them, rename notes without breaking them, and list the backlinks. Notes stay
exactly as Obsidian writes and reads them (canvases included), so the same
vault works in both.

It works in any markdown buffer (the `:Todoist` list too); the links resolve
in the vault set with `:ZettelVault`.

## Following links: `<CR>`

`<CR>` in markdown, by what is under the cursor:

| Under the cursor | What `<CR>` does |
|---|---|
| `[[Note]]`, `![[Note]]`, `[text](Note.md)` | open the note (`<C-o>` goes back) |
| `[[Note#Heading]]`, `[[Note#^block]]`, `[[#Heading]]` | open it at that heading / block |
| `[[photo.png]]`, `[[file.pdf]]`, a canvas | open it in the system's program |
| `https://…` | open it in the browser |
| a link to a note that does not exist | ask, then create it (empty) |
| inside a ```` ```todoist ```` block | open its tasks |
| a checkbox line | toggle it |
| a heading | fold / unfold it |

**`K`** follows the link under the cursor too, and is LSP hover everywhere
else. In other files (code) it follows only web links (`https://…`), since
`[[x]]` there is not a note.

In the `:Todoist` list, `<CR>` on a `[[link]]` in a task's text opens the
note; anywhere else on the line it toggles the task.

Links resolve as in Obsidian:

- case does not matter;
- `[[Note]]` is `Note.md` anywhere in the vault; with two of them, the one in
  the same folder as the note the link is in, else the shortest path;
- `[[folder/Note]]` and `[text](folder/Note.md)` are paths, from the vault's
  root or from the note's folder (`./`, `../`);
- a file that is not markdown keeps its extension (`[[photo.png]]`).

**New notes** get the name written in the link (made safe for Windows file
names), and go where Obsidian's own setting says (Settings → Files and
links → Default location for new notes, read from `.obsidian/app.json`):
the vault root, the current note's folder, or the chosen folder. A path in
the link (`[[Projects/New]]`) puts it there.

## Completing links: `[[`

Typing `[[` lists the vault's notes (and canvases) as you type, matched
loosely (`[[pxt` finds "Projeto X texto"). After `[[Note#` it lists that
note's headings. Accepting one writes the link whole, without a second `]]`
(`pure/pairs.lua` already closed the `[[`).

A name shared by two notes is listed with its folder (`Areas/Ideia`),
which is how the link has to be written to reach that one.

## Renaming and moving: `<leader>nr`, oil

`<leader>nr` (or `:NoteRename [name]`) renames the current note and fixes
every link to it in the vault. A bare name keeps the folder; a name with
`/` is a path from the vault's root (`Areas/New name`; `./Name` for the
root). The buffer follows the file.

**In oil** it is the same: renaming or moving a note, a picture or a whole
folder inside the vault (and saving with `:w`, as always in oil) fixes the
links to everything that moved.

What is fixed, each in the form it was written in:

| Link | After renaming `Projects/Old.md` to `Areas/New.md` |
|---|---|
| `[[Old]]`, `[[Old#Head\|alias]]`, `![[Old]]` | `[[New]]`, `[[New#Head\|alias]]`, `![[New]]` (or `[[Areas/New]]` when another note is also called New) |
| `[[Projects/Old]]` | `[[Areas/New]]` |
| `[x](Projects/Old.md)`, `[x](../Projects/Old.md)` | `[x](Areas/New.md)`, `[x](../Areas/New.md)` (spaces as `%20`) |
| relative links inside the moved note itself | recomputed from its new folder |
| a canvas card of that file | its new path |

Links inside code blocks are left alone. Before writing anything it lists
the files and how many links in each and asks (Enter = yes). Notes open in
Neovim are changed in their buffer and saved, unless they had unsaved
changes: those are changed and left for you to save. Line endings (CRLF)
are kept.

## Backlinks: `<leader>fl`

`<leader>fl` (or `:NoteBacklinks`) lists the lines of other notes that link
to the current one, in the fzf picker; picking one opens it there. Useful to
see where a note is used before changing or deleting it, or what a
project's daily mentions are.

## Not included

What obsidian.nvim had and this does not: its own drawing (pure/mdview.lua
draws), rewriting the frontmatter, tags search, pasting images, daily notes
and templates (pure/zettelkasten.lua does those), sync, slides, several
vaults.

The plugin is no longer loaded. To remove its files too:
`:lua vim.pack.del({ 'obsidian.nvim' })`.
