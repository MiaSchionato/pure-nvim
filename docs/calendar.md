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

## Where the appointments come from

For now from a built-in sample month, to try the grid. Next: two-way sync
with Google Calendar (edits in the grid create, change, move and delete
events), with the same rules as the Todoist sync: asked for on start,
`vim.g.pure_calendar_confirm` for when to ask before sending, past months
frozen, templates never filled.
