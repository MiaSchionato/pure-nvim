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

Everything is under org.nvim's default prefix `<leader>o`, which is also the
Toggles group of `configs/keymaps.lua`. The prefix is still to be decided
(`mappings = { prefix = ... }`).
