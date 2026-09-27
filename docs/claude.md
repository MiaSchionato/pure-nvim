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
| `<leader>ax` | the actions of the vault's `claude` folder (below) |
| `<leader>ab` | run the ```` ```claude ```` block under the cursor (again) |

## Actions: `<leader>ax`

The requests you make often, one markdown file each, in the `claude` folder
of the vault (any case: `Claude/` works; another folder with
`vim.g.pure_claude_actions = 'Pasta'`, or an absolute path). `<leader>ax`
lists them in the fzf picker, with the file as preview; the one you pick
runs with the context of now (the note, the selection, the cursor).

A file is an action when its frontmatter has a `description`; every other
file of the folder (your own notes) is left alone. They sync with the vault
and are edited like any note, in Neovim or Obsidian.

```markdown
---
description: Revisar ortografia e gramática
output: replace
tools: Read, Grep
---
Revise a ortografia e a gramática do texto (português do Brasil).
Mantenha o estilo e a formatação markdown.
```

The text is the request. `$ARGUMENTS` in it is asked for when the action
runs ("Traduzir para $ARGUMENTS").

`context` brings what the buffer does not have: data only a script can
gather (an API on this machine, a log, a database). Each name is either a
**Lua file of the actions folder** (`stats.lua`) or a module of `lua/pure/`
(`todoist`); either returns a table with a `text()` function. The text is
added at the end of the request, between tags named after it (`<stats>`),
so the action works from real data without needing `Bash`. A source that
fails puts one line saying so in its place, and the action still runs.

A Lua file of the actions folder is the place for a personal script: it
lives and syncs with the vault, out of this configuration, and is read
again each time the action runs. It runs with Neovim's rights, like any
Lua, so keep there only files you wrote.

```markdown
---
description: Preparar a nota do dia
output: notify
tools: Read, Glob, Grep, Edit
context: stats.lua
---
Escreva na nota de hoje um próximo passo pequeno a partir dos números do
dia, que vêm no fim deste pedido, em <stats>.
```

```lua
-- stats.lua, next to the action
local M = {}
function M.text()
  return 'Focus today: …'  -- whatever the action should know
end
return M
```

| Key | What | Default |
|---|---|---|
| `description` | the name in the list (required) | |
| `output` | `insert`: into the buffer below the cursor · `replace`: over the selection, or the whole note without one · `window`: the answer window (follow-ups with `a`) · `notify`: Claude works on its own and sends a short summary of what it did as a notification | `notify` when it may change files, else `window` |
| `tools` | what Claude may use: `Read`, `Grep`, `Glob` read; `Edit`, `Write`, `Bash` change files (accepted without asking) | none for insert/replace; reading for window |
| `dirs` | where it may change files: `vault`, `file` (the note's folder), or paths (`~/Downloads`); the first is where it runs | `vault` |
| `confirm` | `auto`: ask before running only when one of the `dirs` is not in a git repository · `always` · `never` | `auto` |
| `model` | the model for this action (`haiku`, `sonnet`, `opus`) | the usual one |
| `key` | its own key, in normal and visual mode (`<leader>a1`). To keep every key in `keymaps.lua` instead, map `require('pure.claude').runNamed('File name')` there | none |
| `context` | more context for the request, added at its end: the `text()` of a Lua file of the actions folder (`stats.lua`) or of a module `lua/pure/<name>`, between tags named after it (see above) | none |

Inside the vault nothing needs asking: it is a git repository (`:VaultSync`),
so a change is undone from its history. Open notes an action changed on disk
are reloaded when it ends. `<leader>ar` repeats the last action; its answers
are in `<leader>ah`.

It is the format of Claude Code's own commands (`.claude/commands/*.md`),
whose other keys are ignored here.

**Examples.** `:ClaudeActionsExamples` (or `<leader>ax` while the folder has
no actions) writes five into the folder, never over an existing file:

| File | What |
|---|---|
| Revisar texto | spelling and grammar of the selection (`replace`) |
| Virar tarefas | loose text into `- [ ]` tasks (`replace`) |
| Sugerir links | looks for related notes in the vault, adds `## Relacionadas` (`insert`) |
| Resumir | the note or the selection in topics (`window`) |
| Nota permanente | the selection becomes its own note in `3-Resources`, replaced by a sentence and its `[[link]]` (`replace`, with `Write`) |

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
