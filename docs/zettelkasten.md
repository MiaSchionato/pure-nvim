# Notes and templates (`lua/pure/zettelkasten.lua`, `lua/plugins/obsidian.lua`)

Obsidian-compatible notes: the vault is set once, templates use the syntax of
Obsidian's **core** Templates plugin (no Templater), and daily / weekly /
monthly notes are opened or created with one key.

## The vault

Asked for on the first start (Yes / Later / Never ask) and remembered in
`stdpath('data')/obsidian_vault`, outside the repository. In order of
precedence:

1. `vim.g.pure_vault` in the config;
2. the `OBSIDIAN_VAULT` environment variable;
3. the saved answer.

`:ZettelVault` asks again at any time. The vault is used by `<leader>em`
(explore), `<leader>fa` (find), `<leader>nm` (new note), the templates, the
Todoist sync and obsidian.nvim, which all follow a change at once.

## Templates: `<leader>nz`

Picks a file from `<vault>/Templates` (`vim.g.pure_templates` renames the
folder) and expands it:

- **ordinary templates** go into the current note, above the cursor line (an
  empty note becomes the template);
- **periodic templates** (`Daily`, `Weekly`, `Monthly`) open their own note
  instead – see below;
- a template with a **destination** then moves the note to its folder.

### Placeholders

| Placeholder | Becomes |
|---|---|
| `{{title}}` | the note's file name, without `.md` |
| `{{date}}` | today, `YYYY-MM-DD` |
| `{{time}}` | now, `HH:mm` |
| `{{date:FORMAT}}`, `{{time:FORMAT}}` | a Moment.js format, as in Obsidian: `{{date:dddd, D [de] MMMM}}`; text in `[brackets]` is copied as is |
| `{{week}}` | ISO week, `2026-W39` |
| `{{month}}` | `2026-09` (in a weekly note, the month of its Thursday) |
| `{{start}}` / `{{end}}` | first / last day of the note's period: Monday / Sunday of a week, 1st / last of a month; `{{start:FORMAT}}` takes a format |
| `{{date+1}}`, `{{end+1:MMM D}}` … | a date shifted by that many days; works on `date`, `time`, `start` and `end` |
| `{{days}}` | a list of links to the daily note of each day of the period: `- [[…/2026-09-21\|Mon 21/09]]` |
| `{{worklogs}}` | each day's `Work log` section embedded, as the lines of a callout (`> …`) |
| `{{weeks}}` | a list of links to the weekly note of each ISO week that touches the period |
| `{{prev}}` / `{{next}}` | in a periodic note: the name of the previous / next day, week or month (for navigation links) |
| `{{quote}}` | a line of `9-Archive/Periodic/Quotes.md` (lines starting with `- `), a different one each day |
| `{{idea}}` | a `[[link]]` to one of your permanent notes, a different one each day |
| `{{diary}}` | `2026-09-25, sex` (the diary file name format) |

Unknown placeholders are left untouched. Moment tokens supported: `YYYY YY
GGGG GG MMMM MMM MM M Do DDDD DDD DD D dddd ddd dd d HH H hh h mm m ss s WW W
A a`. Day and month names follow `vim.g.pure_templates_locale`: `'en'`
(default) or `'pt'` – set it to Obsidian's language so a template gives the
same text in both.

### Destinations

In the `destinations` table at the top of `zettelkasten.lua` (the templates
themselves stay clean):

| Template | Folder |
|---|---|
| Delete | `0-Inbox/Trash` |
| Literature | `3-Zettelkasten/Literature` |
| MOC | `4-Maps` |
| Permanent | `3-Zettelkasten/Permanent` |
| Project | `1-Projects/{{title}}` |
| Tester | `2-Areas/Audiovisual/YouTube/Tester channel` |
| VideoIdeas | `2-Areas/Audiovisual/Ideas` |

The note must be saved (have a name) to be moved; it is never moved over an
existing note.

## Periodic notes

| Template | Folder | File name |
|---|---|---|
| `Daily.md` | `9-Archive/Periodic/Daily` | `2026-09-25.md` |
| `Weekly.md` | `9-Archive/Periodic/Weekly` | `2026-W39.md` |
| `Monthly.md` | `9-Archive/Periodic/Monthly` | `2026-09.md` |

Picking one of these opens the note for the current period:

- **it never makes a second one**: the period's folder is checked first, then
  the whole vault (not the trash, templates or hidden folders); a note found
  elsewhere is opened, with a warning saying where it is;
- it is **filled from the template only while blank** – a new note, or an
  empty one made by Obsidian's daily button; a note with any text, saved or
  not, is left as it is;
- dates in it (`{{date}}`, `{{prev}}` …) are those of the note's period, so an
  old daily shows its own neighbours. A week is dated by its **Thursday** – in
  ISO 8601 that decides the week's year and month, so a week from 28 September
  to 4 October belongs to October – and a month by its first day.

Day steps are counted from noon, so a daylight saving change can never turn
"yesterday" into two days ago.

## Syncing the vault: `:VaultSync`

Saves the vault's notes open in Neovim, commits everything that changed
(`Sync from <computer>, <date>`), pulls, and pushes only if the pull worked.
The order is fixed on purpose: the remote is encrypted with git-remote-gcrypt,
whose pushes are always forced, so a push from a machine that had not pulled
would replace what the other machine sent instead of being refused.

- The pull **merges**, whatever `pull.rebase` says, so a conflict leaves one
  state to fix. It lists the files: fix the conflict markers, then
  `:VaultSync` again, which commits the fix and pushes. Nothing is pushed
  while markers are left, and a rebase started by hand is left for you to
  finish.
- git runs in the background; gpg asks for its passphrase in its own window
  (on macOS that needs `pinentry-mac`).
- The branch has to track a remote once: `git push -u <remote> main`.

## Trash

With `vim.g.pure_trash_cleanup` set (`true` in `configs.lua`), everything in
the Delete template's folder (`0-Inbox/Trash`) is deleted each time Neovim
starts with a UI, as Obsidian's TrashCleaner script did. A number instead of
`true` keeps what was modified in the last that many days; `false` turns it
off. Files are deleted for good, not moved to the recycle bin.

It never touches a note open in that Neovim, never runs in `--headless`
(scripts, tests), and only acts on a folder strictly inside the vault.

## obsidian.nvim

Set up for the vault in `lua/plugins/obsidian.lua`, with its own drawing and
frontmatter handling off (markdown is drawn by `pure/mdview.lua`, and
frontmatter is never rewritten). In notes of the vault:

| Key | What |
|---|---|
| `<CR>` | inside a ```` ```todoist ```` block: open its tasks; else obsidian's smart action (follow the link under the cursor, toggle a checkbox…) |
| `K` | on a link, tag, checkbox or heading: smart action; elsewhere LSP hover |

`markdown_oxide` is the language server for notes (link completion,
backlinks, references).
