# Keymaps

Leader is `<Space>`. Press it and wait to see these live ([keyhint.md](keyhint.md)).
Mode: n = normal, x = visual. Mappings that only exist in some buffers
(markdown, the Todoist list, the git status buffer, oil, the chat window) are on their own pages.
Generated from the running config; the source is `lua/configs/keymaps.lua`.

## Leader, single keys

| Key | Mode | What |
|---|---|---|
| `<leader>+` | n | Taller window |
| `<leader>,` | n | Wider window |
| `<leader>-` | n | Shorter window |
| `<leader>.` | n | Narrower window |
| `<leader><leader>` | n | Find files, two levels up |
| `<leader>D` | n, x | Delete without yanking |
| `<leader>E` | n | Explore home |
| `<leader>h` | n | Toggle word highlight (short form) |
| `<leader>in` | n, x | Inspect highlight under cursor |
| `<leader>n` | x | Run normal command on selection |
| `<leader>p` | x | Paste over without yanking |
| `<leader>p` | n | Paste from clipboard |
| `<leader>r` | n | Rename word under cursor |
| `<leader>s` | x | Substitute inside selection |
| `<leader>u` | n | Undotree |
| `<leader>v` | x | Substitute, very magic |
| `<leader>y` | n, x | Yank to clipboard |

## `<leader>a` – AI (LLMs)

See [llm.md](llm.md).

| Key | Mode | What |
|---|---|---|
| `<leader>aa` | n, x | Chat: show / hide (like <leader>tt) |
| `<leader>ab` | n | Run the ```` ```llm ```` block under the cursor |
| `<leader>ac` | n, x | Review the code |
| `<leader>ad` | n | Daily note: next step and the measured day (the action `Daily note` of `~/Flora/ai/actions`) |
| `<leader>ah` | n | Past answers |
| `<leader>ai` | n, x | Write here (visual: rewrite) |
| `<leader>ap` | n | Personas: pick one from the list, open its chat (`/name`, see [llm.md](llm.md#personas)) |
| `<leader>aj` | n | Job assistant: the chat with the `/job` persona, waiting for your question (see [llm.md](llm.md#personas-name)) |
| `<leader>am` | n | Select model (Ollama / Claude / agy) |
| `<leader>ar` | n, x | Repeat the last request |
| `<leader>as` | n | Stop |
| `<leader>aq` | n | Quit the AI: stop, unload models, close Ollama |
| `<leader>at` | n | Thinking of <leader>ai (show / hide) |
| `<leader>au` | n | User context file (what the LLMs know about you) |
| `<leader>aw` | n | Weekly note: the week in one place (the action `Week review` of `~/Flora/ai/actions`) |
| `<leader>ax` | n, x | Actions (claude/ folder of the vault) |

## `<leader>b` – Buffers

| Key | Mode | What |
|---|---|---|
| `<leader>bn` | n | Next buffer |
| `<leader>bo` | n | Close all but current |
| `<leader>bp` | n | Previous buffer |
| `<leader>bq` | n | Delete buffer |
| `<leader>bv` | n | List buffers |

## `<leader>c` – Code

| Key | Mode | What |
|---|---|---|
| `<leader>cc` | n | Run compiler command |
| `<leader>cl` | n | Clear search highlight |
| `<leader>cs` | n | Source current file |
| `<leader>ct` | n | Insert TODO comment |
| `<leader>cx` | n | Make file executable |

## `<leader>d` – Diagnostics

| Key | Mode | What |
|---|---|---|
| `<leader>dd` | n | Show diagnostic |

## `<leader>e` – Explore

| Key | Mode | What |
|---|---|---|
| `<leader>e.` | n | Explore ~/.config |
| `<leader>ee` | n | Explore current directory |
| `<leader>en` | n | Explore nvim config |
| `<leader>eo` | n | Oil Float |
| `<leader>ev` | n | Explore Obsidian vault |

## `<leader>f` – Find

| Key | Mode | What |
|---|---|---|
| `<leader>f.` | n | Find in ~/.config |
| `<leader>f/` | n | Recent files |
| `<leader>fb` | n | Buffers |
| `<leader>fc` | n | Colorschemes |
| `<leader>fe` | n | fzf explorer, current directory |
| `<leader>ff` | n | Find files, four levels up |
| `<leader>fg` | n | Grep |
| `<leader>fh` | n | Help tags |
| `<leader>fj` | n | Jump list |
| `<leader>ft` | n | Every `TODO:` of the repo (or the folder), searchable, with preview |
| `<leader>f"` | n | Registers (Enter: make it the register p pastes) |
| `<leader>fl` | n | Notes linking here (backlinks, also <leader>vb) |
| `<leader>fn` | n | Find in nvim config |
| `<leader>fv` | n | Find a note, heading or alias in Flora (same as `<leader>vf`) |
| `<leader>f~` | n | Find in home |

## `<leader>g` – Git

| Key | Mode | What |
|---|---|---|
| `<leader>gA` | n | Git add all |
| `<leader>gB` | n | Git switch branch |
| `<leader>gP` | n | Git pull |
| `<leader>ga` | n | Git add current file |
| `<leader>gb` | n | Git blame current line |
| `<leader>gc` | n | Git commit |
| `<leader>gd` | n | Toggle git diff |
| `<leader>gg` | n | Git grep |
| `<leader>gl` | n | Git log |
| `<leader>gp` | n | Git push |
| `<leader>gr` | n | Git discard changes to current file |
| `<leader>gs` | n | Git status (interactive) |
| `<leader>gu` | n | Git unstage current file |
| `<leader>gv` | n | Git Vault Sync |

## `<leader>j` – Jumps

| Key | Mode | What |
|---|---|---|
| `<leader>jh` | n | Jump back |
| `<leader>jl` | n | Jump forward |

## `<leader>l` – LSP

| Key | Mode | What |
|---|---|---|
| `<leader>la` | n | LSP code action |
| `<leader>ldb` | x | Print selection via lua |
| `<leader>lr` | n | LSP rename |
| `<leader>ls` | n | LSP workspace symbols |

## `<leader>M` – Manim

See [manim.md](manim.md).

| Key | Mode | What |
|---|---|---|
| `<leader>Mm` | n | Preview the scene, again on every save (toggle) |
| `<leader>Ms` | n | Preview another scene |
| `<leader>Mp` | n, x | Preview only this part (selection, or the block under the cursor) |
| `<leader>Mf` | n | Picture of the scene at this line |
| `<leader>Mi` | n | Live window at this line: mouse camera, Python shell (toggle) |

## `<leader>n` – New file / folder

| Key | Mode | What |
|---|---|---|
| `<leader>n.` | n | New file in ~/.config |
| `<leader>nd` | n | New folder here |
| `<leader>ne` | n | New file here |
| `<leader>ns` | n | Scratch note (same in every tab; a new tab opens on it) |
| `<leader>nf` | n | New file, pick the folder (from two levels up) |
| `<leader>nh` | n | New file in home |
| `<leader>nn` | n | New file in nvim config |
| `<leader>nv` | n | New note in the vault's inbox |

## `<leader>o` – Toggles

Every toggle says what it did in a notice ("Wrap on", "Wrap off", ...); `<leader>tn` flips both number
options and says "Line numbers on/off" once.

| Key | Mode | What |
|---|---|---|
| `<leader>oc` | n | Toggle signcolumn |
| `<leader>od` | n | Toggle diagnostics |
| `<leader>oh` | n | Toggle word highlight |
| `<leader>oi` | n | Toggle inlay hints |
| `<leader>tm` | n | Toggle note rendering on / off (markdown or org, by the buffer), without the big headings |
| `<leader>tM` | n | Toggle the big headings (OSC 66 / DECDHL) of markdown and org; off by default |
| `<leader>tT` | n | Toggle shrinking of org tables wider than the window (columns cut with `…`, text untouched) |
| `<leader>tW` | n | Toggle wrapping of org tables wider than the window into extra rows (a long cell continues on the next line; changes the text, off joins it back) |
| `<leader>on` | n, x | Toggle line numbers |
| `<leader>op` | n | Toggle Copilot |
| `<leader>or` | n, x | Toggle relativenumber |
| `<leader>os` | n | Toggle statusline |
| `<leader>ot` | n | Toggle tabline |
| `<leader>ow` | n | Toggle wrap |
| `<leader>oH` | n | Toggle the coloured bar behind md and org headings |
| `<leader>oxc` | n | Toggle transparency |
| `<leader>oz` | n | Toggle zen mode |

## `<leader>s` – Split

| Key | Mode | What |
|---|---|---|
| `<leader>sh` | n | Split horizontally |
| `<leader>sv` | n | Split vertically |

## `<leader>t` – Terminal, Todoist

| Key | Mode | What |
|---|---|---|
| `<leader>tD` | n | Todoist today and overdue |
| `<leader>td` | n | Todoist all tasks |
| `<leader>tg` | n | Toggle Gemini terminal |
| `<leader>tt` | n | Toggle terminal |

## `<leader>v` – Flora (the org vault, `pure/flora.lua`)

| Key | Mode | What |
|---|---|---|
| `<leader>vf` | n | Find a note, a heading or an alias in one coloured picker (as Doom's `SPC v f`); a title that matches nothing makes a seed |
| `<leader>vF` | n | Find a file of the vault |
| `<leader>vg` | n | Grep the vault |
| `<leader>vn` | n | New seed (inbox) |
| `<leader>vN` | n | New note in its own file |
| `<leader>vt` | n | Capture: pick a template |
| `<leader>vi` | n | Insert a link to a node: the picker of `<leader>vf`, then `[[id:ID][Title]]` at the cursor (typing `[[` in an org note opens the same list as a menu, see [org.md](org.md)) |
| `<leader>vb` | n | Backlinks (notes linking here) |
| `<leader>vr` | n | Rename this note (title and file; links are by `:ID:`) |
| `<leader>vd` | n | Delete this note (moved to `archive/trash/`) |
| `<leader>vj` | n | Journal line (today) |
| `<leader>vJ` | n | Today in the journal |
| `<leader>ve` | n | Explore the vault |
| `<leader>vs` | n | Save the notes and commit (pull and push when there is an upstream) |
| `<leader>vp` | n | Preview the linked note (org notes; markdown keeps `linkview`) |
| `<leader>vq` | n | Quick edit the linked note (org notes) |

`<leader>ev`, `<leader>fv`, `<leader>nv` and `<leader>gv` follow Flora too.

## `<leader>w` – Tabs, window view

| Key | Mode | What |
|---|---|---|
| `<leader>wh` | n | Previous tab |
| `<leader>wl` | n | Next tab |
| `<leader>wn` | n | New tab |
| `<leader>wo` | n | Close other tabs |
| `<leader>wq` | n | Close tab |
| `<leader>wvh` | n | Focus window left |
| `<leader>wvj` | n | Focus window below |
| `<leader>wvk` | n | Focus window above |
| `<leader>wvl` | n | Focus window right |

## `<leader>z` – Folds

| Key | Mode | What |
|---|---|---|
| `<leader>zT` | n | Fold open tasks (see what is done) |
| `<leader>za` | n | Toggle all folds |
| `<leader>zd` | n | Delete fold |
| `<leader>zf` | x | Fold selection |
| `<leader>zr` | n | Reset folds to automatic |
| `<leader>zt` | n | Fold done tasks (see what is left) |
| `<leader>zz` | n | Toggle the fold starting here |

## Normal mode, no leader

| Key | What |
|---|---|
| `<C-F>` | Half page down |
| `<C-P>` | Jump to matching pair |
| `<Down>` | Move line down |
| `<Up>` | Move line up |
| `J` | Join lines, keep cursor |
| `K` | Follow link, else LSP hover |
| `S` | Surround with function |
| `U` | Redo |
| `Y` | Yank to end of line |
| `[<Space>` | Add empty line above cursor |
| `[d` | Previous diagnostic |
| `[i` | Indent scope top |
| `]<Space>` | Add empty line below cursor |
| `]d` | Next diagnostic |
| `]i` | Indent scope bottom |
| `cs` | Change surround |
| `dl` | Delete char and its pair |
| `ds` | Delete surround |
| `gc` | Toggle comment |
| `gcc` | Toggle comment line |
| `gd` | LSP definition |
| `ge` | Last line |
| `gh` | First non-blank |
| `gj` | Half page down |
| `gk` | Half page up |
| `gl` | End of line |
| `s` | Surround word |
| `vv` | Select word |
| `zT` | Fold open tasks (see what is done) |
| `zt` | Fold done tasks (see what is left) |
| `zz` | Toggle the fold starting here |

## Visual mode

| Key | What |
|---|---|
| `<` | Outdent and reselect |
| `<Down>` | Move selection down |
| `<S-Tab>` | Outdent and reselect |
| `<Tab>` | Indent and reselect |
| `<Up>` | Move selection up |
| `>` | Indent and reselect |
| `J` | Down 5 lines |
| `K` | Up 5 lines |
| `S` | Surround with function |
| `[N` | Select previous sibling node |
| `[i` | Indent scope top |
| `[n` | Select previous node |
| `]N` | Select next sibling node |
| `]i` | Indent scope bottom |
| `]n` | Select next node |
| `a.` | Outer sentence |
| `ac` | Outer curly brackets |
| `ai` | Outer indent scope |
| `an` | Select parent (outer) node |
| `ap` | Outer parentheses |
| `aq` | Smart outer quotes |
| `as` | Outer square brackets |
| `gc` | Toggle comment |
| `gh` | First non-blank |
| `gl` | End of line |
| `i.` | Inner sentence |
| `ic` | Inner curly brackets |
| `ii` | Inner indent scope |
| `in` | Select child (inner) node |
| `ip` | Inner parentheses (not paragraph; the paragraph is `i}`) |
| `iq` | Smart inner quotes |
| `is` | Inner square brackets |
| `s` | Surround selection |

## Insert mode

| Key | What |
|---|---|
| `<CR>` | Accept Copilot suggestion / next list item / new line |
| `<Esc>` | Close the completion menu, else leave insert mode |
| `<S-Tab>` | Outdent an empty list item / previous suggestion / snippet jump back |
| `<Tab>` | Indent an empty list item / past closing pair / next suggestion / snippet jump |
| `<Up>` | LSP signature help, else up |

## Terminal mode

| Key | What |
|---|---|
| `<Esc>` then `<Esc>` again (250 ms) | Leave terminal mode, then close the floating terminal (not the one in a tab); `<A-Esc>` sends a real `<Esc>`. See [ui.md](ui.md) |
| `<Esc><Esc>` | Close a floating terminal that runs a command |
| `<S-Esc>` | Leave terminal mode |

Text objects (`is`, `ic`, `iq`, `ii`, `in` …): see [editing.md](editing.md).
