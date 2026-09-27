# Day stats (`lua/pure/daystats.lua`)

The measured picture of one day, as plain text, for [Claude actions](claude.md)
that ask for it with `context: daystats`. Nothing to call by hand: the action
gets the text at the end of its request, between `<daystats>` tags, and
Claude writes from real numbers instead of guessing.

```
# Measured day 2026-03-14 (now 2026-03-14 18:02)
## Focus (focus log)
- Trailer: rough cut [Work] started 10:05: focus 50 min, completed, 0 pause(s)
- Course: lesson 4 [Study] started 14:30: focus 38 min, ended, not completed, 1 pause(s)
Focus by project: Work 50 min, Study 38 min

## Screen (ActivityWatch)
Active: 5h12, from 09:40 to 18:02
Top apps: firefox.exe 1h55, Adobe Premiere Pro.exe 1h20, nvim.exe 48 min, …
Work apps: 1h20. Claude Design: 0 min
  project Premiere: Trailer: 1h14

## Sleep window
PC closed at 13/03 23:10; first activity at 14/03 09:40.
Estimate: asleep by 23:10-00:10, awake since 07:40-08:40.
```

## Sections

| Section | Where from | Needs |
|---|---|---|
| Focus | a focus log in the vault, one line per timer event | `vim.g.pure_daystats_focus_log` |
| Screen | [ActivityWatch](https://activitywatch.net), running on this machine | the ActivityWatch server |
| Sleep window | ActivityWatch: when the PC was last used the night before, and first used on the day | the ActivityWatch server |

A section whose source is missing says so in one line; the others still come.

**A day** runs from 05:00 to 05:00 the next day (`vim.g.pure_daystats_day_start`),
so a night that goes past midnight still belongs to its day.

**Screen time** counts only the time the PC was in use: ActivityWatch's
"not-afk" periods, merged (its AFK bucket repeats events, so summing them
raw would inflate the total).

**Window titles** are read only for the work apps (Premiere, After Effects,
Resolve, Photoshop, Illustrator, Media Encoder, and Claude's `Design` mode),
to name the project open in them. For every other app, only the total time.

## The focus log

A markdown file, one line per timer event, like:

```
- 2026-03-14 14:30:02 · started · Course: lesson 4 [Study] · planned 50:00
- 2026-03-14 15:08:10 · paused · Course: lesson 4 [Study] · focus 38:08
- 2026-03-14 15:40:44 · ended, not completed · Course: lesson 4 [Study] · focus 38:08 of 50:00 planned
```

A session starts with `started` (or `already running…`) and ends with
`completed` or `ended, not completed`; its focus is the last `focus` value.
The project goes in brackets after the task. Any timer that writes these
lines works; here they come from a small script that reads the PomoDeck timer
every 30 s.

## Settings

```lua
vim.g.pure_daystats_focus_log = '9-Archive/PomoDeck/focus-log.md' -- relative to the vault; unset: no focus section
vim.g.pure_daystats_sleep = { after = 60, before = { 60, 120 } } -- minutes; unset: only the two times
vim.g.pure_daystats_day_start = 5                                 -- hour the day starts
vim.g.pure_daystats_aw = 'http://127.0.0.1:5600'                  -- ActivityWatch server
vim.g.pure_daystats_work_apps = { ['Resolve.exe'] = 'Resolve' }   -- instead of the default list
```

## Notes

- `require('pure.daystats').text()` returns today's report;
  `text('2026-03-14')` another day's.
- Everything stays on this machine: ActivityWatch is read on `127.0.0.1`
  with `curl`, the focus log from the vault. The report goes to Claude only
  inside the action that asked for it.
