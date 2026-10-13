# Link view (`lua/pure/linkview.lua`)

Look at a linked note without leaving the one you are writing.

| Key | What |
|---|---|
| `<leader>vp` | **Preview** the note the link under the cursor points to: a floating, read-only window without the note's frontmatter. `[[Note#Heading]]` shows just that section (down to the next heading of the same or a higher level), `[[Note#^id]]` just that block. Moving the cursor closes it; `<leader>vp` again closes it too. Shows what is not saved yet if the note is open. |
| `<leader>vq` | **Quick edit** the linked note: the note itself (the real buffer, not a copy) in a floating window, at the section the link names. `:w` saves; `q` or `<Esc>` in normal mode closes the window, saving what changed, and unloads the note again if it was not open before. |

Both work on `[[wikilinks]]` and `[text](Note.md)` links, the same ones `K`
follows (see [notes.md](notes.md)); a note that does not exist yet says so
(follow the link with `K` to create it).

## Settings (`configs/configs.lua`)

```lua
-- 'key' (default): the preview only on its key. 'auto': also after the
-- cursor rests on a link. 'off': no preview and no quick edit.
vim.g.linkview_preview = 'key'
-- With 'auto': milliseconds the cursor rests before the preview shows.
vim.g.linkview_delay = 600
-- The keys; give only the one you change.
vim.g.linkview_keys = { preview = '<leader>vp', edit = '<leader>vq' }
```
