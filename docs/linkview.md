# Link view (`lua/pure/linkview.lua`)

Look at a linked note without leaving the one you are writing.

| Key | What |
|---|---|
| hover | **Preview** the note the link under the cursor points to when the cursor rests on it (600 ms): a small read-only window next to the cursor, like the suggestion menu (same colours and border, it never takes the focus), without the note's frontmatter. `[[Note#Heading]]` shows just that section (down to the next heading of the same or a higher level), `[[Note#^id]]` just that block. Moving the cursor closes it. Shows what is not saved yet if the note is open. |
| `<leader>vp` | The same preview on a key (toggles it). |
| `<leader>vq` | **Quick edit** the linked note: the note itself (the real buffer, not a copy) in a floating window, at the section the link names. `:w` saves; `q` or `<Esc>` in normal mode closes the window, saving what changed, and unloads the note again if it was not open before. |

Both work on `[[wikilinks]]` and `[text](Note.md)` links, the same ones `K`
follows (see [notes.md](notes.md)); a note that does not exist yet says so
(follow the link with `K` to create it).

## Settings (`configs/configs.lua`)

```lua
-- 'auto' (default): the preview shows after the cursor rests on a link (and
-- on its key). 'key': only on the key. 'off': no preview and no quick edit.
vim.g.linkview_preview = 'auto'
-- With 'auto': milliseconds the cursor rests before the preview shows.
vim.g.linkview_delay = 600
-- The most the preview takes: columns and rows.
vim.g.linkview_size = { width = 64, rows = 12 }
-- The keys; give only the one you change.
vim.g.linkview_keys = { preview = '<leader>vp', edit = '<leader>vq' }
```

The same note can be in several quick edits at once (A opens B, which opens
A again): `q` / `<Esc>` close the window you are in, and the mapping goes
away with the last one.
