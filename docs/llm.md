# LLMs: Claude, Ollama, agy (`lua/pure/llm.lua`)

Language models from keys. (It was `pure/claude.lua` while Claude was its
only model; that name still works as an alias.) Each request goes with its context: the
file (path, type, content), the cursor line, the selection and the LSP
diagnostics. The request runs in the file's git root (or its folder).

Three backends, picked with `<leader>am` (see "Models" below):

- **Claude** – [Claude Code](https://claude.com/claude-code) installed and
  logged in on that machine: `claude` in the PATH (run `claude` once in a
  terminal to log in). Every request uses your Claude plan.
- **Ollama** – local models, free and offline. Started on demand if it is
  not running.
- **agy** – Antigravity's CLI (Gemini, Claude and GPT-OSS models of that
  service), when `agy` is installed.

## Write into the buffer: `<leader>ai`

The most common use. Type what you want; the answer goes **straight into
the buffer**:

- normal mode: below the cursor line (or in place of it, when the line is
  blank);
- visual mode: **in place of the selection** ("turn this into a table",
  "fix this", "translate").

While it works, a dimmed line under the place says what the model is doing
and for how long (`qwen3.5:9b is thinking… 3s`, then `is writing… 7s`), and
the text shows dimmed where it will go; you can keep working meanwhile (the
place is kept even if lines change above). Then it becomes real text, as
**one change: `u` takes it all back**. The same status line with its seconds
shows for ```` ```llm ```` blocks and for actions working on their own.

The model is told to write only the text itself (no explanation, no code
fence around it), in the file's language and style.

A model that thinks first (qwen3.5, deepseek-r1…) shows the last lines of its
thinking in the dimmed lines while it thinks; it is never written into the
buffer. `<leader>at` shows all of it (and hides it again) while it writes,
and afterwards opens the last write's thinking in a window.

## Chat: `<leader>aa`

For questions that write nothing: "what does this do?", "why this error?",
"how do I…". `<leader>aa` works like `<leader>tt` for the terminal:

- no chat yet: an empty one opens, with the cursor in the **box at its
  bottom**; type the question there and `Enter`;
- the chat on screen: it is **hidden**, with its conversation kept (an answer
  still coming keeps coming);
- the chat hidden: it is shown again as it was.

The answer comes as it is written, drawn as markdown, and the window keeps
its end in view (a long line too). Move the cursor up in the answer to read
and it stops following; back on the last line (`G`), or with your next
question, it follows again. The question goes with the context of the
buffer the chat was opened (or last shown) from; in visual mode, the
selection.

A conversation stays in the folder (project) it began in, also when the
chat is shown again from a file of another project, and when an older
answer is reached with `[`: Claude Code resumes a session only from there.
The next new chat (`n`) starts in the folder of the buffer it was last
shown from.

The title shows what the model is doing and the seconds since you asked
(`thinking… 3s`). Each answer ends with its time and tokens, small and grey
on the right (not copied with `y`): `5.4s · 5.2k↑ 40↓`, tokens sent (the note
and the instructions included, which is most of it) and received. When done,
the title has the chat's totals, follow-ups included. Writing into the
buffer and actions that notify say their tokens in the notification.

A model's thinking shows dimmed above its answer while it thinks, then folds
into one line, `▸ thought for 6s`.

In the box (it takes the cursor when an answer is in):

| Key | What |
|---|---|
| `Enter` | send (the first question, or a follow-up: the model remembers the conversation) |
| `<C-u>` / `<C-d>` | scroll the answer |
| `Esc` | up to the answer |

In the answer:

| Key | What |
|---|---|
| `a` / `i` | down to the box |
| `r` | reply to a part of the answer: the selection (visual mode) or the cursor line goes, quoted, with your next question (the box says `Reply to «…»`); another `r` replaces it |
| `[` / `]` | the previous / next answer of this session, in the same window (the title says which, `2/5`); a follow-up then continues that one |
| `n` | a new chat (the old one stays reachable with `[`) |
| `t` | show / hide the thinking of every answer |
| `y` | copy the answer (also to the system clipboard) |
| `Esc` | hide the chat (its key shows it again: `<leader>aa`, or a persona's, see "Personas") |
| `q` | close it for good (stops an answer still coming) |

A request that ends in an error, or is stopped (`<leader>as`), frees the
chat like an answer does: `n` starts a new chat, and the box asks again
(the first question failed: a new conversation) or follows up again (a
follow-up failed: the same conversation). Only a request still running
makes it say "wait for the answer first".

Here the model may read other files of the project (Read, Grep, Glob) to
answer, never change them.

## Other keys

| Key | What |
|---|---|
| `<leader>ac` | review the code (or the selection) in the window: bugs, risky cases, simplifications, with line numbers |
| `<leader>ar` | the last request again, with the context of now (another selection, another file) |
| `<leader>ah` | past answers of this session, in the picker; opening one allows follow-ups |
| `<leader>am` | select model: Ollama (local), Claude, agy (see "Models") |
| `<leader>at` | the thinking of `<leader>ai`: show / hide it while it writes, or open the last one |
| `<leader>au` | open the user context file (see "What the models know about you") |
| `<leader>as` | stop everything running |
| `<leader>aq` | what quitting Neovim does, without quitting: stop everything, unload the Ollama models used here from the GPU, close the Ollama started here (the next local request asks to start it again) |
| `<leader>ax` | the actions of the vault's `claude` folder (below) |
| `<leader>ab` | run the ```` ```claude ```` or ```` ```llm ```` block under the cursor (again) |

## Actions: `<leader>ax`

The requests you make often, one markdown file each, in the `claude` folder
of the vault (any case: `Claude/` works; another folder with
`vim.g.pure_llm_actions = 'Pasta'`, or an absolute path). `<leader>ax`
lists them in the fzf picker by title (the file name, as Obsidian shows
it), with the file as preview; the one you pick
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

Two modules give their data this way, straight from their APIs, one plain
line per item (much less than the blocks they write into notes):

- `context: todoist`: the tasks of `today | overdue | no date`, subtasks
  indented, `- [ ] Task · date · P1 · Project`;
- `context: calendar`: today's and tomorrow's appointments of every calendar
  shown in Google Calendar, `- 10:00-11:00 Dentista (calendar)`.

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
| `output` | `insert`: into the buffer below the cursor · `replace`: over the selection, or the whole note without one · `window`: the answer window, a chat (follow-ups with `a`); with `Edit` or `Write` in `tools` it may also change files in `dirs` when you ask or it clearly helps, and says which · `notify`: the model works on its own and sends a short summary of what it did as a notification | `notify` when it may change files, else `window` |
| `tools` | what the model may use: `Read`, `Grep`, `Glob` read; `Edit` (replace a part), `Write` (create or rewrite a file), `Move` (move or rename a file, see below), `Bash` change files (accepted without asking); `Todoist` adds, updates and completes Todoist tasks (see below) | none for insert/replace; reading for window |
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

**`tools: Todoist`.** No model has a Todoist tool, so an action with this one
gets every open task with its id (`todoist.text('all', true)`) and answers
with one line per change, which Neovim sends to Todoist when it ends and
replaces with what was done (`Todoist: added "…"`):

```
<todoist add="Call the dentist" due="tomorrow 10am" priority="p2" project="Home"/>
<todoist add="Finish the video" ref="v"/>
<todoist add="Edit the intro" parent="v"/>
<todoist update="ID" content="…" due="…" priority="…" parent="…"/>
<todoist complete="ID"/>
```

`parent` makes a subtask, at any depth: the id of an open task, or the `ref`
of a task added earlier in the same answer; on `update` it moves the task
under that one.

It works the same on Claude, agy and Ollama, and the `todoist` blocks of open
notes are redrawn after. The vault's "Sincronizar com Todoist" action uses it
to bring the current note's `- [ ]` tasks into Todoist.

**Examples.** `:LLMActionsExamples` (or `<leader>ax` while the folder has
no actions) writes five into the folder, never over an existing file:

| File | What |
|---|---|
| Revisar texto | spelling and grammar of the selection (`replace`) |
| Virar tarefas | loose text into `- [ ]` tasks (`replace`) |
| Sugerir links | looks for related notes in the vault, adds `## Relacionadas` (`insert`) |
| Resumir | the note or the selection in topics (`window`) |
| Nota permanente | the selection becomes its own note in `3-Resources`, replaced by a sentence and its `[[link]]` (`replace`, with `Write`) |

## Personas: `/name`

An action is *what* to do; a persona is *who* answers: its instructions (tone,
rules, what it knows how to do), the context it needs and its tools. Start
any request with `/name` and that persona answers it:

- **in the chat** (`<leader>aa`, or its own, see `chatWith` below), as the
  first question or a follow-up: `/job what do I do now?`. It stays for the
  follow-ups, until another `/name`. Here the persona brings its own `tools`
  and `dirs` too: with `Edit`, `Write` and `Move` it reads, writes and moves
  files in its folders while you talk;
- **at `<leader>ai`**: `/job summarize this` writes in the persona's voice;
- **in an action's text** or a **```` ```llm ```` block** starting with
  `/name`: its instructions and context come first. The tools stay the
  action's or the block's (a block runs on its own, so it never gets a
  persona's write permission).

A text starting with something that is not a persona (`/usr/bin`) is left as
it is.

Each persona is one markdown file in the `Personas` folder of the actions
folder (`vim.g.pure_llm_personas` for another name), in the actions' format.
The file name is the command (`job.md`: `/job`); the folder is not listed as
actions.

```markdown
---
description: Work assistant
aliases: coworker
greeting: Hi! What are we doing?
context: todoist, stats.lua
tools: Read, Glob, Grep, Edit, Write, Move
dirs: vault
---
You are my work assistant. Wait for my question; when I ask what to do,
propose one small step...
```

| Key | What |
|---|---|
| `description` | what it is (required, as for actions) |
| `aliases` | more names for it: `coworker, cowork` |
| `greeting` | shown when a chat opens with it (`chatWith`), without asking the model anything |
| `context`, `tools`, `dirs`, `model` | as for actions. With `Edit`, `Write` or `Move` it may change, write or move files in `dirs` when you ask or it clearly helps, and says which |

`require('pure.llm').chatWith('job')` opens the persona's **own chat**,
apart from `<leader>aa`'s: each keeps its own conversation and context, so
you can go back and forth between them. It opens with the persona's
greeting (if it has one) and the box waiting for your first question
(nothing is asked before it). Called again, it hides or shows that chat,
like `<leader>aa`. The chats share the middle of the screen, so showing one
hides the other (kept, with an answer still coming). Map it in
`keymaps.lua` to give a persona its key.

## Requests in notes: ```` ```llm ```` blocks

A request that runs on its own, written in a note (```` ```claude ```` blocks, from
before the rename, work the same). The answer is written
under it, between two markers (HTML comments, which Obsidian does not show):

````
```llm
Resuma a daily de ontem e liste as tarefas que ficaram abertas.
```
<!-- claude -->
…the answer…
<!-- /claude -->
````

It runs when the note is shown (or saved) and **has no answer yet**, so it
runs once. In Neovim the request and the markers are hidden once there is an
answer; move the cursor onto it to see them. `<leader>ab` (or
`:LLMBlock`) on the block runs it again and replaces the answer. For
these requests the model may read the whole vault (Read, Grep, Glob), never
change it; it is told where the daily / weekly / monthly notes live and
today's date.

Put the block in a template and every note made from it gets its answer:

- **Daily** (`Templates/Daily.md`): *"Summarize yesterday's daily and list
  the tasks left open."* Runs when the day's note is made.
- **Weekly** (`Templates/Weekly.md`), a review at the end of the week:

  ````
  ```llm
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
| `model: ...` | specific model for this block (e.g. `qwen2.5-coder:14b` or `haiku`) |

It never runs:

- in the templates folder or the trash;
- in a note named after a date outside its time: a daily only on its own
  day, a weekly in its week or the week after, a monthly in its month or
  the month after (so opening old notes costs nothing);
- in a note with unsaved changes (it runs once the note is saved);
- while a request still has `{{…}}` placeholders.

The note is saved after the answer is written, unless it had other unsaved
changes by then.

## Models: `<leader>am`

`<leader>am` (or `:LLMModel`) opens the model picker:

- **Ollama**: the models of the running Ollama (`http://localhost:11434`),
  such as `qwen3.5:9b`. With Ollama down, the line "(offline) start Ollama"
  starts it and lists them.
- **Claude**: `default`, `sonnet`, `haiku`, `opus`.
- **agy**: its default and every model `agy models` lists (kept in a cache,
  refreshed in the background: the listing takes a few seconds).
- **Custom model**: type any name (`ollama:…`, `claude:…`, `agy:…`).

The pick is remembered across sessions (in Neovim's state folder). Or
directly:

```vim
:LLMModel ollama:gemma4:e4b
:LLMModel claude:sonnet
:LLMModel agy:gemini-3.1-pro-high
```

The `:Claude…` names of these commands (`:ClaudeModel`, `:ClaudeActions`,
`:ClaudeBlock`) still work.

### Local models (Ollama)

- **Started on demand.** A request that finds Ollama down asks whether to
  start it; started from here, `ollama serve` belongs to this Neovim and is
  stopped (with the model processes) when Neovim quits. An Ollama already
  running is never stopped. `vim.g.pure_ollama_autostart`: `'ask'`, `true`
  (without asking), `false`.
- **With Neovim, if you like.** `vim.g.pure_ollama_start_with_nvim = true`
  starts it in the background when Neovim opens (with a UI), without
  asking, unless one is running already.
- **Off when idle.** `vim.g.pure_ollama_idle_minutes` (default 15) minutes
  after the last local request ends, the models used here are unloaded from
  the GPU and the Ollama started here is closed; never while a request
  runs. `false` or `0`: never. `<leader>aq` does the same at once (and stops
  every request).
- **Tools.** Local models get the same tools as Claude in the same request:
  read a file, list files, grep and, only where the request allows it
  (actions with `Edit` / `Write` / `Move`), edit, write and move files. Only inside the
  request's folders, never a file with unsaved changes in Neovim. A model
  that writes its tool call as text (qwen2.5-coder) is understood too; one
  without tool support answers without them. A note read this way has the
  regions Neovim writes into it (the Todoist list, the calendar grid, block
  answers) collapsed to one line each; they are most of a daily note, and
  never to be edited by a model.
- **Thinking** is off: models answer straight away
  (`vim.g.pure_ollama_think = true` turns it on). Measured with qwen3.5:9b on
  an 8 GB card, thinking took 30–54 s per answer against 1.4–6 s without,
  with answers as good. When on, it is kept out of the answer (Ollama's
  `thinking` field and `<think>…</think>` in the text alike) and shown dimmed
  instead (`vim.g.pure_llm_thinking = 'hide'` hides it).
- **Context size.** Each request gets the smallest context that holds it
  (8192 tokens, doubled as needed, up to `vim.g.pure_ollama_num_ctx`,
  32768): with 8 GB of VRAM a 9B model runs half as fast at 32K. There is
  no cap on the answer's length.

- **Nothing left behind.** When Neovim quits, requests still running are
  stopped with their process trees, the Ollama models used are unloaded from
  the GPU (also from an Ollama not started here, such as the tray app) and
  the Ollama started here is stopped.
- **Which model.** Measured on an 8 GB card: `gemma4:e4b` for chat and
  writing (right on everyday tasks, tools without thinking, ~1 s); JetBrains'
  Mellum2 for code (the one that edited a file right). Actions that read a
  lot and edit several places with detailed rules (a daily note) are for
  Claude: no local model that fits did them right.

### agy

Requests that only read run in agy's default mode, where edits are refused
(print mode has nobody to approve them); requests that change files use
`accept-edits`. The prompt goes on stdin as a stream-json event.

## Moving files: `Move`

Claude Code moves files only with `Bash`, which can run anything. `Move` in
an action's `tools` moves and renames files without it: a tool for local
models, and for Claude and agy a line `<move from="a.md" to="b/a.md"/>` in
their answer, which Neovim carries out when the answer is done (the line
is not shown; "Moved a.md to b/a.md" is). Either way: only inside the
request's folders, missing folders are made, an existing file is never
replaced, a file with unsaved changes stays, an open buffer follows its
file, and links to a moved note are fixed in the vault (as `<leader>vr`
does). An action to sort the inbox:

```markdown
---
description: Organizar o inbox
output: notify
tools: Read, Glob, Move
dirs: vault
---
Mova cada nota do 0-Inbox para a pasta certa do vault.
```

## Private folders: `vim.g.pure_llm_private`

Folders no cloud model (Claude, agy) may see; local models (Ollama) may,
since nothing leaves the machine. Inside the vault or absolute:

```lua
vim.g.pure_llm_private = { '6-Private' }
```

A request to a cloud model is not sent ("…not sent. A local model may do
it.") when it holds the text of a note from one of them (the chat,
`<leader>ai`, an action or a block from such a note), or when its folders
reach one, since its tools could read it there. Claude may still work in the
vault's root when the vault's `.claude/settings.json` denies
`Read(<folder>/**)`, which Claude Code enforces itself; agy has nothing like
it, so it gets no request whose folders reach one. A cloud model's `Move`
never takes a file into or out of one.

## What the models know about you: `<leader>au`

A markdown file about you that every request reads, whatever the model:
`stdpath('data')/llm_user.md`, outside every git repository (another path with
`vim.g.pure_llm_user_context`). `<leader>au` opens it to edit.

A model may add to it: when you tell it something lasting (a preference, your
work), it puts `<remember>…</remember>` at the end of its answer; that is
saved to the file with its date and never shown or written into a buffer.
A fact the file already holds, in other words or another language, is not
written again. `vim.g.pure_llm_memory = false`: the file is only read.

## Settings

All in `lua/configs/configs.lua`, section "LLMs":

```lua
vim.g.pure_llm_model = nil            -- model when none was picked ('ollama:gemma4:e4b', 'sonnet', 'agy:')
vim.g.pure_claude_cmd = 'claude'      -- Claude Code command, if not in the PATH
vim.g.pure_llm_blocks = true          -- false: blocks run only with <leader>ab
vim.g.pure_llm_actions = 'claude'     -- folder of the actions, in the vault
vim.g.pure_llm_personas = 'Personas'  -- folder of the personas (/name), in the actions folder
vim.g.pure_llm_thinking = 'show'      -- 'hide': never show a model's thinking
vim.g.pure_llm_user_context = nil     -- the user context file (false: none)
vim.g.pure_llm_memory = true          -- false: models never write to it
vim.g.pure_llm_private = nil          -- folders no cloud model may see ({ '6-Private' })
vim.g.pure_ollama_url = 'http://localhost:11434'
vim.g.pure_ollama_num_ctx = 32768     -- largest context a request may get
vim.g.pure_ollama_think = false       -- true: models think before answering (slower)
vim.g.pure_ollama_autostart = 'ask'   -- true / false
vim.g.pure_ollama_start_with_nvim = false -- true: start it when Neovim opens
vim.g.pure_ollama_idle_minutes = 15   -- unload / close after that long unused (false: never)
vim.g.pure_ollama_models = nil        -- models folder for the Ollama started here
```

## Notes

- Claude requests use `claude -p` (no interactive session). The prompt goes on
  stdin; the answer is read as it streams (`--output-format stream-json`).
- Ollama requests stream via Ollama's `/api/chat` endpoint using `curl`; each
  round of tool calls is one more request. Conversation history is kept per
  chat, so follow-ups work with local models too.
- Writes into the buffer run without tools (faster); asks, reviews and
  blocks may read files, never write them or run commands.
- On Windows, an npm install (`claude.cmd`) is run through `cmd.exe`; the
  native install (`claude.exe`) directly. Process trees are cleaned up
  reliably on stop.
