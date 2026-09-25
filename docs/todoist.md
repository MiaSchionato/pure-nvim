# Todoist (`lua/pure/todoist.lua`)

Todoist inside Neovim, through the Todoist API v1 and `curl`. Three ways to
use it:

1. **The task list** – `:Todoist`: a buffer you edit like text; `:w` sends
   the changes.
2. **Blocks in notes** – a ```` ```todoist ```` block in any markdown note
   lists the tasks of a filter.
3. **Archive** – a copy of the list and a history of changes, in a folder.

## Token

Todoist → Settings → Integrations → Developer → API token. Then either:

- `:TodoistToken` – hidden input; saved to `stdpath('data')/todoist_token`,
  outside the repository; or
- the `TODOIST_API_TOKEN` environment variable (wins over the file).

Without a token Neovim asks on startup (Yes / Later / Never ask).
**Never type the token in a shell**: shell history files can end up in git.
The token is sent to curl on stdin, so it never shows in the process list.

## 1. The task list: `:Todoist`

| Command / key | What |
|---|---|
| `:Todoist` or `<leader>td` | all active tasks |
| `:Todoist today \| overdue` or `<leader>tD` | any Todoist filter, as in the app |

The buffer is a markdown task list, one `##` section per project:

```markdown
## Work
- [ ] Write the README due:today p1
  - [ ] Sub step due:tomorrow
- [ ] Review PR
```

Edit it as text; `:w` works out the difference and sends it:

| You do | Todoist gets |
|---|---|
| write a new line | a new task |
| delete a line | the task is deleted |
| `[x]` | completed (`[ ]` again reopens it) |
| change the text | renamed |
| `due:<phrase>` at the end | due date, any English Todoist phrase (`due:next monday`) |
| `p1`, `p2`, `p3` as the last word | priority (no `pN` = normal) |
| indent under another line | becomes its subtask |
| move the line under another `##` | moved to that project |
| copy a line | a **new** task (each line ends in a hidden id; a copy is new) |

Keys in that buffer:

| Key | What |
|---|---|
| `<CR>` / `x` | tick / untick the checkbox (`x` does not delete here) |
| `<leader>x` | cycle Obsidian states `[ ] [~] [!] [>] [-] [x]`; only `[x]` reaches Todoist, the others are remembered locally (`todoist_states.json`) |
| `r` | reload from Todoist (asks if there are unsaved edits) |
| `q` / `<Esc>` | close (same) |

**Confirmation before sending** – `vim.g.pure_todoist_confirm`:
`'all'` (every save, default), `'delete'` (only when tasks would be deleted),
`'never'`. The confirmation lists what will change; Enter = Yes, except for
deletions where Enter = No.

The list is fetched in the background at startup, so the first `:Todoist`
opens at once.

## 2. Blocks in notes

In any markdown note, the same syntax as Obsidian's Todoist plugin:

````markdown
```todoist
name: Today
filter: "today | overdue"
```
````

`name` is the title, `filter` any Todoist filter (empty = all tasks). The old
JSON form of the plugin (`{"name": …, "filter": …}`) is read too.

In Neovim the query lines are hidden; moving the cursor into the block shows
them, to edit the filter. With the cursor **inside a block**, `<CR>` (or
`:Todoist` without a filter) opens that filter's task list in a floating
window over the block: go through it line by line, `x` to complete, `:w` to
send, `q` to close.

What appears under the block depends on `vim.g.pure_todoist_sync`:

### Sync on (default in configs.lua): tasks written into the note

```lua
vim.g.pure_todoist_sync = { interval = 10 }   -- minutes
```

The tasks are written **as real text** right under the block, between two
markers (HTML comments, invisible in Obsidian):

````markdown
```todoist
filter: "today | overdue"
```
<!-- todoist -->
- [ ] [Write the README](https://app.todoist.com/app/task/123) · 2026-09-25 · P1 · Work
  - [ ] [Sub step](https://app.todoist.com/app/task/124) · 2026-09-26 · Work
<!-- /todoist -->
````

- Each task links to it in Todoist, then due date · priority · project.
  Dates are written as dates (a phrase like "today" would be wrong
  tomorrow); recurring tasks keep their phrase ("every monday").
- **Only the lines between the markers are ever rewritten**, and only when
  they would change. The rest of the note is never touched.
- **Ticking a box there** (`[x]`, in Neovim with `<leader>tx` or in Obsidian)
  completes the task in Todoist on the next sync, and it leaves the list.
- Any other edit between the markers is overwritten on the next sync: edit
  tasks in Todoist or in the `<CR>` list.

When it syncs: at startup, every `interval` minutes, when a note with a block
is opened or saved, and on `:TodoistSync`.

Which notes: every note of the vault with a block (found with ripgrep), not
the templates folder, the trash (`0-Inbox/Trash`) or hidden folders; plus any
other open note with a block. It never overwrites:

- a note open with **unsaved changes** (it waits until you save);
- a note named after a date other than today (`2026-09-24.md`): **past
  dailies keep the list they had** that day.

If a begin marker has no end marker, that block is left alone (so a broken
marker can never swallow the rest of the note).

### Sync off: tasks drawn, not written

```lua
vim.g.pure_todoist_sync = false
```

The tasks are drawn under the block as virtual lines (not in the file). They
are cached for 5 minutes; `:TodoistRefresh` reloads them.

## 3. Archive

```lua
vim.g.pure_todoist_archive = '~/…/9-Archive/Todoist/'
```

Keeps three files there, written in the background and only when something
changed:

- `tasks.md` – the full list;
- `history.md` – one line per change, with date and time (made here, or
  seen changed in Todoist);
- `tasks.json` – the list as data, used to detect changes.

Unset or `''` turns it off.

## For development

`vim.g.pure_todoist_url` replaces the API address (tests use a fake local
server).
