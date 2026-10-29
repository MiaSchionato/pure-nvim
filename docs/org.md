# Org notes (`lua/plugins/org.lua`)

[org.nvim](https://github.com/xheisenbugx/org.nvim) on the Flora vault
(`~/Flora`), set up to behave like the Doom Emacs of the same vault. It is
independent of the Markdown modules (`notes`, `zettelkasten`): those act on
`markdown` buffers, org.nvim on `org` ones. Neovim 0.11 or newer.

## What is configured

| Setting | Value |
|---|---|
| Agenda files | `tasks.org`, `inbox.org`, `projects/**/*.org` (as `my/garden-agenda-files` in Doom) |
| Task states | `TODO NEXT DOING WAITING \| DONE CANCELLED` |
| Idea stages | `SEED SPROUT PLANT TREE FLOWER \| COMPOST` (keywords must be declared, or a node title would start with `PLANT`) |
| Keyword colours | the Ethereal palette |
| Roam directory | the whole vault, except `journal/` |
| Daily notes | `journal/<year>.org`, one entry per day in its date tree |

## Capture (`<leader>oc`, then a key)

The keys of the quick capture (Win+Q) of the Emacs side:

| Key | Goes to |
|---|---|
| `s` | a `SEED` in `inbox.org` |
| `t` | a `TODO` in `tasks.org`; asks for a date first, Enter = none (`today`, `+3d`, `fri`, `2026-11-02`) |
| `T` | a `TODO` with a `DEADLINE` (date picked in the calendar) |
| `l` | a link in `inbox.org` (the clipboard is the default address) |
| `f` | a source in `sources/<kind>.org`; asks the kind, the title, author and status |
| `j` | a line `* HH:MM text` in `journal/<year>.org`, under today's date |

## Org-roam

The `roam` extension of org.nvim, not a separate plugin. It indexes the vault
into a JSON file (`stdpath('data')/org/roam-index.json`), not into SQLite, so
Doom's `org-roam.db` is untouched; the note format is the same, so both
editors can share the vault. A node is a file or a headline with an `:ID:`.
Keys are under `<leader>om` (find `f`, insert link `i`, backlinks `l`,
capture `c`, graph `g`) and `<leader>omd` for the daily notes (`t` today).

## Keys

org.nvim's keys are under its default prefix `<leader>o`, which is also the
Toggles group of `configs/keymaps.lua` (and `<leader>om` is the render toggle,
which is also org.nvim's roam group). The prefix is still to be decided
(`mappings = { prefix = ... }`).

## Rendering

org.nvim's own drawing over the text (concealed links, star bullets,
checkbox icons, indent) is off in `lua/plugins/org.lua`: the rendering is
`lua/pure/render-org.lua`'s, so it can be toggled and follows the terminal.
Its syntax colours stay. The file is the org twin of `render-md.lua` (settings,
view, bigger headlines) and uses the same colours (`pure/notecolors.lua`, which
follow the colorscheme). The text is never changed; marks are drawn over it.

`<leader>om` turns the drawing on and off, in markdown and in org notes. In an
org note it also waits for `timeoutlen`, because org.nvim's own roam keys start
with `<leader>om` (decision pending, see Keys).

| In the note | On screen |
|---|---|
| `* Headline` | icon instead of the stars and a coloured band; `*` and `**` bigger where the terminal can (below) |
| `- item` | bullet per level: • ◦ ▪ ▫ (`vim.g.pure_md_bullets`); `1.` stays |
| `- [ ]` `- [X]` `- [-]` | checkbox icons; done items dimmed |
| `#+begin_src lua` … `#+end_src` | shaded block, the language as a label (any `#+begin_xxx`); quote blocks get a bar |
| `-----` | a full-width line |
| `\| tables \|` | box-drawing borders |
| `[[target][text]]`, `[[target]]` | only the text (or the target); the link under the cursor stays raw |
| `*bold*` `/italic/` `_u_` `=verbatim=` `~code~` `+strike+` | the marks around are hidden (`vim.g.pure_org_emphasis = false` keeps them) |
| `:PROPERTIES:` and `:LOGBOOK:` drawers | hidden; they come back while the cursor is on them |
| `#+title: Name` | drawn as a first-level title |

Blocks and drawers are read first, so a `*` or a link inside a src block is plain text.

### Bigger headlines

Where the terminal can: kitty draws `*` (3x) and `**` (2x) with OSC 66, WezTerm with the
double-height lines (DECDHL, only when the window spans the terminal's width), the others
draw the icon and band. Same checks as the markdown headings: `vim.g.pure_org_headings`
(or `vim.g.pure_md_headings` when nil): `auto`, `osc66`, `decdhl`, `off`;
`:PureOrgHeadings [auto|osc66|decdhl|off]` changes it while Neovim runs. In WSL set it to
`decdhl` for WezTerm, as for markdown. The terminal code is a copy of `render-md.lua`'s.

Not tested with a real terminal: the escape sequences were not drawn on a screen here,
only the marks, the reserved lines and the choice of mode.

## Flora keys (`<leader>v`, `lua/pure/flora.lua`)

The group of the old Atlas vault now works on Flora, like Doom's `SPC v`:
find a node (`f`), a file (`F`), grep (`g`), new seed (`n`), new note (`N`),
capture templates (`t`), insert a link (`i`), backlinks (`b`), rename (`r`),
delete to `archive/trash/` (`d`), journal line (`j`), today (`J`), explore (`e`),
save and commit (`s`), preview and quick edit the linked note (`p`, `q`, in org
notes). The list is in [keymaps.md](keymaps.md). Links are by `:ID:`, so renaming
or moving a note breaks none. The Atlas functions are left in
`pure/zettelkasten.lua` and `pure/notes.lua` as commands, without keys.

## Find (`<leader>vf`)

One picker for the whole vault, a port of Doom's `SPC v f` (`vault-open.el`), in
`lua/pure/flora.lua` (fzf, coloured). A note (a file, named by its `#+title`) reads
`Note name`; a heading (down to level 4) reads `Note name › Heading`, the heading in the
colour of its level; an alias (`:ROAM_ALIASES:`, of a note or a heading) reads
`Alias → Note name › Heading`, in italics. On the right, dim: the path and how long ago the
note was written. The newest notes come first and `archive/` last; any part of the name,
the path or an alias matches, words in any order. Enter opens the note at the heading; a
title that matches nothing makes a seed in `inbox.org`.

The colours (`pure/notecolors.lua`) follow the colorscheme; in Ethereal they are Doom's
exactly: note `#4f8a96`, alias `#c89dc1`, separators and path `#6d7db6`, headings the
level colours. It lists every note and heading, not only the ones with an `:ID:`
(org-roam's `roam_node_find` is still `<leader>omf`).
