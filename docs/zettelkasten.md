# Notes and templates (`lua/pure/zettelkasten.lua`)

Obsidian-compatible notes: the vault is set once, templates use the syntax of
Obsidian's **core** Templates plugin (no Templater), and daily / weekly /
monthly notes are opened or created with one key.

## The vault

Asked for on the first start (Yes / Later / Never ask) and remembered in
`stdpath('data')/obsidian_vault`, outside the repository. In order of
precedence:

1. the Markdown vault of `vim.g.pure_vaults` (the entry with `format = 'md'`);
2. `vim.g.pure_vault`, the older single-vault setting;
3. the default vault of `vim.g.pure_vaults` (`vim.g.pure_vault_default`);
4. the `OBSIDIAN_VAULT` environment variable;
5. the saved answer.

## Several vaults (`vim.g.pure_vaults`, `pure/vault.lua`)

One entry per vault, in `configs.lua`:

```lua
g.pure_vaults = {
  name = {
    dir = '~/folder',
    format = 'org',            -- or 'md'
    notes = { inbox = 'inbox', nursery = 'garden/nursery' },  -- without extension
    readonly = false,          -- true: nothing writes into it
  },
}
g.pure_vault_default = 'name'  -- the vault outside every vault's folder
```

A command (`<leader>v_`, `<leader>o_`) works in the vault holding the current file, else in the default
one. The notes are named without extension (the format adds `.org` or `.md`; a name ending in `/` is a
folder) and a name left out keeps its default: `inbox`, `garden/nursery`, `tasks`, `journal`,
`archive/compost`, `sources/books`, `sources/quotes`, `sources/concepts`, the folders `garden/`, `sources/`
and `archive/trash/`. In a read-only vault find, grep and open work; grow, compost, move, capture, rename and
delete say it is read-only. What is a format's own is in `pure/vault/org.lua` (org.nvim, `:ID:` links) and
`pure/vault/md.lua`. A folder of `vim.g.pure_llm_private` named without a path is private in every vault.

In this configuration the vault in use is a Markdown vault (`g.pure_vaults.md`, read by its Obsidian too),
and the org vault ([org.md](org.md)) is kept read-only next to it (`g.pure_vaults.org`); it was the one in use from 2026-11-05 to 2026-11-18.
The templates, periodic notes and trash below were made for the Markdown vault;
with the org one their automatic parts are off (`pure_periodic_on_start = {}`,
`pure_trash_cleanup = false`).

`:ZettelVault` asks again at any time. The vault is used by the `<leader>v`
keys (below), the templates, the Todoist sync and the links between notes
([notes.md](notes.md)), which all follow a change at once.

A vault that is not an absolute path to an existing folder counts as not set:
nothing is created inside it. That covers a vault not cloned yet, and a path
from another system (`C:/...` is relative on Linux, so the `mkdir -p` calls
used to build it under the current directory).

## The vault's keys: `<leader>v`

| Key | What |
|---|---|
| `<leader>vn` | new note: asks its **name only** and makes it in the inbox (`0-Inbox/`, `vim.g.pure_inbox`); also `<leader>nv` |
| `<leader>vN` | new note **of a kind**: picks the template first, then the title, and the note is born in that template's folder (Fleeting stays in the inbox) |
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
| `{{quote}}` | a line of `6-Archive/Periodic/Quotes.md` (`vim.g.pure_quotes`; lines starting with `- `), a different one each day |
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
| Decupagem | `2-Permanent` |
| Delete | `0-Inbox/Trash` |
| Literature | `1-Literature/{{browse}}` (asks which sub-folder) |
| MOC | `4-Maps` |
| Media | `1-Literature/Audiovisual/{{browse}}` |
| Permanent | `2-Permanent` |
| Project | `3-Projects/{{choose:Personal|Clients}}/{{title}}` (asks which) |
| Seed | `2-Permanent` |
| VideoIdeas | `4-Maps/Audiovisual/Ideas` |

`{{browse}}` at the end of a destination lists the sub-folders of the folder
before it, one level at a time (`Here (...)` first, so Enter confirms, then the
folders, then `New folder...`), and goes down until you pick `Here`. A folder
without sub-folders is taken at once, without asking. Hidden folders and
`attachments` are not listed. Literature starts at `1-Literature` (Books,
People, Audiovisual...); Media starts inside `Audiovisual`, so it is Enter to
confirm. `{{choose:A|B}}` in a folder asks which one when the note moves.
Cancelling any of these leaves the note where it is.

**A template moves the note from anywhere except the folders it keeps**: a
note in `3-Projects`, `4-Maps`, `6-Archive`, `7-Templates` or `8-AI` is only
filled and **stays where it is**, named after the title, with `.md`; a note
anywhere else is moved (so a Literature note in `2-Permanent`, or a
wrong choice, can be fixed by applying the right template).
`vim.g.pure_template_keep` changes that list. The Delete template always
moves (it is the trash). Until 2026-10-17 only notes in the inbox or the
vault's root were moved.

The note must have a name to be moved (it need not be saved yet); it is
never moved over an existing note.

## Periodic notes

| Template | Default folder | File name |
|---|---|---|
| `Daily.md` | `6-Archive/Periodic/Daily` | `2026-09-25.md` |
| `Weekly.md` | `6-Archive/Periodic/Weekly` | `2026-W39.md` |
| `Monthly.md` | `6-Archive/Periodic/Monthly` | `2026-09.md` |

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

**The current periodic notes are made when Neovim starts** (with a UI, never
in `--headless`), without opening them: each period listed in
`vim.g.pure_periodic_on_start` (empty in `configs.lua` since the vault is
org; it was `{ 'Daily', 'Weekly', 'Monthly' }`) gets today's, this week's or this month's note. They are there
from the start, for Obsidian, for the daily's links to its week and month, or
a Claude action that writes in them, not only once opened. It is the
*current* one, not a trigger on the exact day: a week whose Monday Neovim was
not opened gets its note on the first start of that week. Past weeks and
months are not made. Same rules as above: never a second one, a note with
text is left alone, and a period without a template is skipped. The older
`vim.g.pure_daily_on_start = true` makes the daily alone. A Neovim left open
past midnight makes the next day's on its next start, or when it is opened.

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

With `vim.g.pure_trash_cleanup` set (`false` in `configs.lua` since the vault
is org), everything in
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

## A Markdown vault (`pure/vault/md.lua`)

The `<leader>v` keys in a vault with `format = 'md'` work on the Markdown its Obsidian reads (the vault's
`garden.js` and `capture.js` are the same commands there):

- **A seed is a line** (since 2026-11-20): one list item at the end of `inbox.md`, date and time first, its tags
  inline, its body (if any) a paragraph of its own: an empty line, then the lines indented with a tab. A block id
  `^xxxxxx` ends the first line only when something links to it (the captures add none):
  `- 2026-11-20 14:05 The idea #tag1 #tag2`. A captured note is `garden/<Title>.md` with YAML properties
  (`tags:` its state and the title's `#tags`, `created: YYYY-MM-DD HH:mm`). The captures below write these;
  grow, compost and move still work on the older shape:
- **The atom is a heading.** Its state is a tag on the line right under it (`#seed`, `#sprout`, `#plant`,
  `#tree`, `#fruit`, `#compost`; other tags stay on that line), then `key:: value` properties, then the body.
  An `id::` line under a linked heading is never changed or copied: it moves with its heading.
- `<leader>vn` grow: a `#seed` of the inbox becomes a `#sprout` and moves to the nursery; a `#sprout` becomes a
  `#plant` in a note of its own (`garden/<title>.md`); a plant becomes a tree in place.
- `<leader>vc` compost (asks, No by default): a seed or sprout moves to `archive/compost.md`; a plant, tree or
  fruit stays in its note, only `#compost`.
- `<leader>vm` move: to the note of `sources/` its `type::` names, else one picked in the list.
- A heading moved by these takes its links along: every `[[note#Heading]]` of the vault (embeds, `|text`
  kept) is rewritten to its new note. A heading renamed by hand is the vault's Obsidian's (`headlinks.js`).
- `<leader>vt` the state menu: on a heading the six garden states and "no state"; on a checkbox the six task
  states.
- **Tasks are checkboxes** of the Tasks plugin. In a note of a Markdown vault the checkbox keys (`<leader>x`,
  the state menu, a selection) write its dates: done adds ` ✅ <today>`, cancelled ` ❌ <today>`, leaving them
  takes the date away (before a ` ^block` id; `⏳ 📅 ➕ 🔁` untouched). The Todoist list and Markdown outside the
  vaults keep only the box.
- `<leader>vq` captures, in a floating draft (`:w` or `<C-c><C-c>` stores, `<C-c><C-k>` drops; a draft left
  empty is dropped): `n` node (`type::` says where it goes: seed or none a seed line in the inbox (properties
  filled in go into its body as `key: value` lines), sprout / plant / tree / fruit a note of its own
  `garden/<Title>.md` (` 2`, ` 3`... when the name is taken; filled properties become YAML properties),
  compost a seed line in the compost note, the name of a note of `sources/` that note (still a heading with
  `key::` lines and `created::`); empty properties are dropped), `t` task and `T` task + deadline (a checkbox in the tasks note:
  `- [ ] title ➕ <today> ⏳ <scheduled> 📅 <deadline>`, dates in words: today, amanhã, domani, fri, +3d,
  2026-11-20; a time goes in an indented `scheduled::` line, the body indented under the task), `l` link (the
  clipboard's address, a seed line in the inbox), `j` journal (`journal.md`: `# year` / `## YYYY-MM Month` /
  `### YYYY-MM-DD Weekday`, made when missing, the entry at the end of its day).
- `<leader>vf` find: a note is its file name, its aliases those of the front matter. `<leader>vJ` today's
  heading in the journal. `<leader>vr` rename, `<leader>vb` backlinks: `pure/notes.lua`. `<leader>vN` a new
  note at the root. The agenda is org's only.

### Renamed headings: the vault's Obsidian fixes their links (`pure/vault/obsidian.lua`)

A heading renamed or moved by hand keeps its links through its `id::` line, but the rewrite is the vault's
Obsidian's (`files/config/scripts/headlinks.js` there): one implementation, not two. Obsidian open sees a note
saved here at once. With Obsidian closed, a save that changes a heading with an id is noted, and
`:VaultFixLinks`, or quitting Neovim, starts Obsidian on the vault, waits until it has written its state file
(the end of its start: the links are fixed; at most a minute) and closes it again (only when it was started
here). grow, compost and move rewrite the links of what they move themselves, and tell the state file, so
they start nothing. The vault's entry names Obsidian's vault and its state file:

```lua
md = { dir = '~/folder', format = 'md', obsidian = { vault = 'Name', state = 'files/config/headlinks.json' } },
```
