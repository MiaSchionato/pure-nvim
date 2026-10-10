# Links between notes (`lua/pure/notes.lua`)

What obsidian.nvim did here, in a few hundred lines: follow links, complete
them, rename notes without breaking them, and list the backlinks. Notes stay
exactly as Obsidian writes and reads them (canvases included), so the same
vault works in both.

It works in any markdown buffer (the `:Todoist` list too); the links resolve
in the vault set with `:ZettelVault`.

Every file of the vault counts, also those its `.gitignore` lists (a
private folder kept out of git can be linked, completed and searched for
backlinks); hidden folders (`.obsidian`, `.trash`) do not. The LLM tools
still honour `.gitignore`, so a model never reads those files.

## Following links: `<CR>`

`<CR>` in markdown, by what is under the cursor:

| Under the cursor | What `<CR>` does |
|---|---|
| `[[Note]]`, `![[Note]]`, `[text](Note.md)` | open the note (`<C-o>` goes back) |
| `[[Note#Heading]]`, `[[Note#^block]]`, `[[#Heading]]` | open it at that heading / block |
| `[[photo.png]]`, `[[file.pdf]]`, a canvas | open it in the system's program |
| `https://…` | open it in the browser |
| a link to a note that does not exist | ask: create it, create it from a template, create it in another folder, or cancel |
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

**With a template**, a template is picked (the periodic ones are left out)
and applied as `<leader>vt` applies it, moves included: the Project template
sends the note to `1-Projects/<title>/`. The note is made only once a template
is picked, so cancelling leaves nothing behind. **In another folder** asks
for a folder of the vault, with completion, starting from the current
note's own, and makes it if it does not exist.

A folder can have a template of its own (`vim.g.pure_folder_templates`,
folder inside the vault = template name): a note made there by **Yes** or
**In another folder** is filled with it at once, and the question says so
(`Create the note "2026-10-08, qui" (template Diary)?`). Here the diary,
`6-Private/Diary`, linked from the daily note. A template missing from the
templates folder is skipped.

A link to a periodic note that does not exist yet, in its folder and named as
its period names it (`[[…/Weekly/2026-W42]]`, the daily's "Next week →"), only
asks **Yes** or **Cancel**: its name is its date, so it is made from its own
template (Daily, Weekly, Monthly) for that date, as opening it would.

## Completing links: `[[`

Typing `[[` lists, as you type and matched loosely (`[[pxt` finds
"Projeto X texto"):

- the vault's **notes** (and canvases) first;
- then its **folders** (`3-Zettelkasten/`, accepted without `]]` so you keep
  typing into it);
- then **attachments** (images, PDFs…), with their extension, as Obsidian
  links them (`![[photo.png]]`).

What you used lately comes first: the open buffers (last used first) and
Neovim's recent files (`:oldfiles`), marked `󰋚` in the menu. Before you
type, they head the list; once you type, only matches are listed, and a
recent one goes up among matches about as good, never above a clearly
better match. The current note is never offered.

Each item says what it is in the menu (`note`, `folder`, `file`). With a
path, `[[3-Zettelkasten/`, it lists what is directly in that folder (case
does not matter), matched by what follows the last `/`. After `[[Note#` it
lists that note's headings. Accepting one writes the link whole, without a
second `]]` (`pure/pairs.lua` already closed the `[[`).

`Tab` / `S-Tab` walk the list even with the `]]` right after the cursor;
`Esc` closes the list, and then `Tab` steps past the `]]`
([editing.md](editing.md)).

A name shared by two notes is listed with its folder (`Areas/Ideia`),
which is how the link has to be written to reach that one. Otherwise
`[[Note]]` is enough, wherever the note is: links resolve by name, as in
Obsidian, so a note a template moves keeps working.

## Renaming and moving: `<leader>vr`, oil

`<leader>vr` (or `:NoteRename [name]`) renames the current note and fixes
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

## Backlinks: `<leader>vb`

`<leader>vb` (also `<leader>fl`, or `:NoteBacklinks`) lists the lines of
other notes that link to the current one, in the fzf picker, with the
linking note shown above as you move (the line of the link highlighted);
picking one opens it there. Useful to
see where a note is used before changing or deleting it, or what a
project's daily mentions are.

## Not included

What obsidian.nvim had and this does not: its own drawing (pure/mdview.lua
draws), rewriting the frontmatter, tags search, pasting images, daily notes
and templates (pure/zettelkasten.lua does those), sync, slides, several
vaults.

The plugin is no longer loaded. To remove its files too:
`:lua vim.pack.del({ 'obsidian.nvim' })`.
