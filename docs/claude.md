# Claude (`lua/pure/claude.lua`)

Claude Code from keys, not a chat. Each request goes with its context: the
file (path, type, content), the cursor line, the selection and the LSP
diagnostics. Claude runs in the file's git root (or its folder).

Needs [Claude Code](https://claude.com/claude-code) installed and logged in
on that machine: `claude` in the PATH (run `claude` once in a terminal to
log in). Every request uses your Claude plan.

## Write into the buffer: `<leader>ai`

The most common use. Type what you want; the answer goes **straight into
the buffer**:

- normal mode: below the cursor line (or in place of it, when the line is
  blank);
- visual mode: **in place of the selection** ("turn this into a table",
  "fix this", "translate").

While Claude writes, the text shows dimmed where it will go; you can keep
working meanwhile (the place is kept even if lines change above). Then it
becomes real text, as **one change: `u` takes it all back**.

Claude is told to write only the text itself (no explanation, no code fence
around it), in the file's language and style.

## Ask, answer in a window: `<leader>aa`

For questions that write nothing: "what does this do?", "why this error?",
"how do I…". The answer comes in a floating window, drawn as markdown, as it
is written. In visual mode the question is about the selection.

In the window:

| Key | What |
|---|---|
| `a` | ask a follow-up (Claude remembers the conversation) |
| `y` | copy the answer (also to the system clipboard) |
| `q` / `<Esc>` | close (stops it, if still running) |

Here Claude may read other files of the project (Read, Grep, Glob) to
answer, never change them.

## Other keys

| Key | What |
|---|---|
| `<leader>ac` | review the code (or the selection) in the window: bugs, risky cases, simplifications, with line numbers |
| `<leader>ar` | the last request again, with the context of now (another selection, another file) |
| `<leader>ah` | past answers of this session, in the picker; opening one allows follow-ups |
| `<leader>as` | stop everything running |
| `<leader>ab` | run the ```` ```claude ```` block under the cursor (again) |

## Requests in notes: ```` ```claude ```` blocks

A request that runs on its own, written in a note. The answer is written
under it, between two markers (HTML comments, which Obsidian does not show):

````
```claude
Resuma a daily de ontem e liste as tarefas que ficaram abertas.
```
<!-- claude -->
…the answer…
<!-- /claude -->
````

It runs when the note is shown (or saved) and **has no answer yet**, so it
runs once. In Neovim the request and the markers are hidden once there is an
answer; move the cursor onto it to see them. `<leader>ab` (or
`:ClaudeBlock`) on the block runs it again and replaces the answer. For
these requests Claude may read the whole vault (Read, Grep, Glob), never
change it; it is told where the daily / weekly / monthly notes live and
today's date.

Put the block in a template and every note made from it gets its answer:

- **Daily** (`Templates/Daily.md`): *"Summarize yesterday's daily and list
  the tasks left open."* Runs when the day's note is made.
- **Weekly** (`Templates/Weekly.md`), a review at the end of the week:

  ````
  ```claude
  when: sunday
  Review this week: read its dailies and write what was done, what is
  left and what to focus on next week.
  ```
  ````

Options, as the first lines of the block:

| Option | What |
|---|---|
| `when: sunday` | not before that weekday (English or Portuguese: `domingo`, `sexta`…). In a weekly note (`2026-W39`), the weekday of that note's week |
| `run: manual` | never on its own, only with `<leader>ab` |

It never runs:

- in the templates folder or the trash;
- in a note named after a date outside its time: a daily only on its own
  day, a weekly in its week or the week after, a monthly in its month or
  the month after (so opening old notes costs nothing);
- in a note with unsaved changes (it runs once the note is saved);
- while a request still has `{{…}}` placeholders.

The note is saved after the answer is written, unless it had other unsaved
changes by then.

## Settings

```lua
vim.g.pure_claude_model = 'sonnet'  -- default: the claude command's own
vim.g.pure_claude_cmd = 'claude'    -- the command, if not in the PATH
vim.g.pure_claude_blocks = false    -- blocks run only with <leader>ab
```

## Notes

- The requests use `claude -p` (no interactive session). The prompt goes on
  stdin; the answer is read as it streams (`--output-format stream-json`).
- Writes into the buffer run without tools (faster); asks, reviews and
  blocks may read files, never write them or run commands.
- On Windows, an npm install (`claude.cmd`) is run through `cmd.exe`; the
  native install (`claude.exe`) directly.
