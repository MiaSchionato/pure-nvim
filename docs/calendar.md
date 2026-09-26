# Calendar (`lua/pure/calendar.lua`)

A month as a grid in a note, one box per day, like a wall calendar. Only
one-off appointments: what repeats (work, dailies) is left out.

````markdown
```calendar
month: 2026-10          (default: the note's name when it is YYYY-MM, else this month)
calendars: primary      (which calendars; the main one by default)
exclude: recurring
```
````

Under the block the plugin writes the grid (between `<!-- calendar -->`
markers, inside a code block). In Neovim only the grid shows: the query, the
markers and the ```` ``` ```` lines are hidden (moving the cursor onto them
shows them), and it has no code shading. In Obsidian it is a monospaced
block, so the boxes stay aligned there too.

```
┌───────────────────────────┬───────────────────────────┬─ … ─┐
│            Seg            │            Ter            │     │
╞═══════════════════════════╪═══════════════════════════╪═ … ═╡
│ 05                        │ 06                        │     │
│                           │ 14:30 Dentista            │     │
│                           │                           │     │   ← a spare line per week
├───────────────────────────┼───────────────────────────┼─ … ─┤
```

A box is 25 columns wide (`vim.g.pure_calendar_cell_width`), which makes the
grid 197 columns. Today is marked `◀ hoje`.

## Writing in a box

| In a box | Means |
|---|---|
| `14:30 Dentista` | an appointment; 1 hour (`vim.g.pure_calendar_duration`, in minutes) |
| `14:30–16:00 Dentista` (or `-`) | with its end |
| `Feriado` | all day |
| `@ Rua X, 10` | the place of the appointment above |
| `  ` (two spaces) at the start | continues the line above |
| `Viagem →` / `← Viagem` | an event of several days (read only) |
| text after a day number (`06  14:30 Dentista`) | an appointment of that day |

Write anywhere, as crooked as it comes out: **`:w` reads the grid back and
redraws it aligned**, one day at a time in time order, with long text
wrapped onto the next line of the same box. Rows are found by their `│`
borders, so text that pushed a border is fine; a border deleted by mistake,
a missing week separator and a `│` typed inside a title are understood too.
A line it cannot place in a day is **never dropped**: it is kept under the
grid, with a warning, to be moved into the right day.

While typing in the grid the automatic line break (`textwidth`) is off: a
grid line is wider than a note's 110 columns.

## Keys in the grid

A line of the file crosses the whole week, so inside the grid these work on
the **day under the cursor**; outside they are the usual ones:

| Key | What |
|---|---|
| `dd` | delete only the appointment under the cursor (its wrapped lines and place too) |
| `o` | a new line for the day under the cursor |
| `cc` | replace the appointment under the cursor |

## Commands

| Command | What |
|---|---|
| `:CalendarRefresh` | draw the grid of blocks that have none, and tidy all |
| `:CalendarSync` | sync every grid with Google now |
| `:CalendarAuth` | connect Google Calendar (again) |

## Google Calendar (two-way)

### Connecting (once)

Google has no personal token like Todoist: reading and writing your
calendars takes OAuth. One time, about 10 minutes:

1. [console.cloud.google.com](https://console.cloud.google.com): create a
   project and enable **Google Calendar API**.
2. **OAuth consent screen**: External; add your own address as a test user.
   Then **Publish app** ("In production"): while it stays in "Testing", the
   authorization expires every 7 days. Google warns the app is not
   verified; for your own use, continue anyway.
3. **Credentials → Create credentials → OAuth client ID → Desktop app**.
   Keep the client ID and the client secret.
4. In Neovim: on start it asks, like the Todoist token (Yes / Later / Never
   ask), or `:CalendarAuth` any time. Paste the client ID and secret; the
   browser opens, you allow access, done.

Kept in `stdpath('data')`, never in the repository: `google_calendar.json`
(client ID, secret and the refresh token), `google_calendar_no_prompt`
("never ask"), `calendar_sync.json` (what the last sync wrote). Secrets reach
curl on stdin, never on its command line.

Not connected, a block gets an empty month: a manual calendar, tidied on
save, that syncs nothing.

### What syncs

The grid is rewritten from Google, and what was **edited in the grid** since
the last sync is sent first:

| In the grid | In Google Calendar |
|---|---|
| a new line in a day | a new event, in the block's first calendar (the main one by default) |
| changed text, time, end or `@ place` | the event is changed |
| the same appointment moved to another day | the event moves (not deleted and made again) |
| a line deleted | the event is deleted |

Events that repeat stay out (`exclude: recurring`), and several-day events
are read only. An event changed in Google and not in the grid just takes
Google's version.

`calendars: primary, Trabalho` names calendars by their name as Google shows
it (or their id); an unknown name is reported, and that grid is not
rewritten. Times are local, daylight saving included.

**When:** at start, every 15 minutes (`vim.g.pure_calendar_sync = {
interval = 15 }`; `false`: never on a timer), when a note with a block is
opened or saved, and on `:CalendarSync`.

**Never:** past months (they keep what they showed), templates, the trash, a
note with unsaved changes. A failed fetch leaves the grid as it was.

**Asking first:** `vim.g.pure_calendar_confirm` = `'delete'` (default: asks
before deleting), `'all'` (before sending anything), `'never'`. Enter is No
when something would be deleted; saying no redraws the grid from Google,
undoing those edits.

The first sync of a grid only reads: it has nothing to compare with yet.

### For tests

`vim.g.pure_calendar_auth_url`, `vim.g.pure_calendar_token_url` and
`vim.g.pure_calendar_api_url` replace Google's addresses (a local fake);
`vim.g.pure_calendar_source = 'mock'` fills unconnected grids with a sample
month.
