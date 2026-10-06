# Notes and templates (`lua/pure/zettelkasten.lua`)

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

`:ZettelVault` asks again at any time. The vault is used by the `<leader>v`
keys (below), the templates, the Todoist sync and the links between notes
([notes.md](notes.md)), which all follow a change at once.

## The vault's keys: `<leader>v`

| Key | What |
|---|---|
| `<leader>vn` | new note: asks its **name only** and makes it in the inbox (`0-Inbox/`, `vim.g.pure_inbox`); also `<leader>nv` |
| `<leader>vt` | apply a template (below) |
| `<leader>vd` | delete the note: asks, saves it, moves it to the vault's trash (`0-Inbox/Trash`, never over a note already there: "Idea 2") and shows the buffer before it |
| `<leader>vr` | rename the note and fix the links to it ([notes.md](notes.md)) |
| `<leader>vb` | backlinks, with the linking note as preview |
| `<leader>ve` | explore the vault (oil); also `<leader>ev` |
| `<leader>vf` | find a note; also `<leader>fv` |
| `<leader>vg` | grep the vault |
| `<leader>vs` | sync the vault with git (`:VaultSync`); also `<leader>gv` |

## Templates: `<leader>vt`

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
| `{{quote}}` | a line of `9-Archive/Periodic/Quotes.md` (`vim.g.pure_quotes`; lines starting with `- `), a different one each day |
| `{{idea}}` | a `[[link]]` to one of your permanent notes, a different one each day |
| `{{diary}}` | `2026-09-25, sex` (the diary file name format) |

Unknown placeholders are left untouched. Moment tokens supported: `YYYY YY
GGGG GG MMMM MMM MM M Do DDDD DDD DD D dddd ddd dd d HH H hh h mm m ss s WW W
A a`. Day and month names follow `vim.g.pure_templates_locale`: `'en'`
(default) or `'pt'` – set it to Obsidian's language so a template gives the
same text in both.

### Destinations

Kept out of the templates themselves, so they stay clean. The defaults are
below; `vim.g.pure_template_destinations` in `configs.lua` changes any of them
by template name (`false` leaves that template's note where it is). Delete
(the trash) and Permanent (the source of `{{idea}}`) always keep a folder.

| Template | Default folder |
|---|---|
| Delete | `0-Inbox/Trash` |
| Literature | `3-Zettelkasten/Literature` |
| MOC | `4-Maps` |
| Permanent | `3-Zettelkasten/Permanent` |
| Project | `1-Projects/{{title}}` |
| VideoIdeas | `2-Areas/Audiovisual/Ideas` |

The note must have a name to be moved (it need not be saved yet); it is
never moved over an existing note. A note that is **already inside the
template's folder** – anywhere under `1-Projects` for Project – was put there
on purpose before the template, so it **stays where it is**; it is only named
after the title, with `.md`.

## Periodic notes

| Template | Default folder | File name |
|---|---|---|
| `Daily.md` | `9-Archive/Periodic/Daily` | `2026-09-25.md` |
| `Weekly.md` | `9-Archive/Periodic/Weekly` | `2026-W39.md` |
| `Monthly.md` | `9-Archive/Periodic/Monthly` | `2026-09.md` |

`vim.g.pure_periodic_folders` changes the folders, e.g.
`{ Daily = 'Periodic/Daily' }` (periods left out keep their default).

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

**Today's daily note is made when Neovim starts** (with a UI, never in
`--headless`), without opening it, when `vim.g.pure_daily_on_start` is set
(`true` in `configs.lua`): it is there from the start, for Obsidian or a
Claude action that writes in it, not only once it is opened. Same rules as
above: never a second one, and a note with text is left alone. A Neovim left
open past midnight makes the next day's on its next start, or when it is
opened.

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

## Links

Following, completing and renaming links, and backlinks, are in
[notes.md](notes.md) (`pure/notes.lua`). A new note made from `[[Title]]`
is named `Title.md` (`zettelkasten.noteId`).
