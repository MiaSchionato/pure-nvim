# Keymaps

Leader is `<Space>`. Press it and wait to see these live ([keyhint.md](keyhint.md)).
Mode: n = normal, x = visual. Mappings that only exist in some buffers
(markdown, the Todoist list, the git status buffer, oil, the chat window) are on their own pages.
Generated from the running config; the source is `lua/configs/keymaps.lua`.

## Leader, single keys

| Key | Mode | What |
|---|---|---|
| `<leader><leader>` | n | Find files, two levels up |
| `<leader>a` | n | Agenda: the org agenda's menu (`a` week, `t` open items, `m` match, `s` search), floating; same as `<leader>ma`. Until 2026-11-08 `<leader>a` was the AI (now `<leader>l`) and `<leader>l` the LSP (now `<leader>L`) |
| `<leader>D` | n, x | Delete without yanking |
| `<leader>E` | n | Explore home |
| `<leader>h` | n | Toggle word highlight (short form) |
| `<leader>H` | n, x | Highlight the word / selection in a colour, org notes (on a highlight: change, remove); see [org](org.md#coloured-highlights-leaderh-luapurehighlightslua) |
| `<leader>in` | n, x | Inspect highlight under cursor |
| `<leader>n` | x | Run normal command on selection |
| `<leader>p` | x | Paste over without yanking |
| `<leader>p` | n | Paste from clipboard |
| `<leader>q` | n | Quick capture: the template menu (same as `<leader>vq`) |
| `<leader>r` | n | Rename word under cursor |
| `<leader>r` | x | Rename the selection in the whole buffer |
| `<leader>s` | x | Substitute inside selection |
| `<leader>T` | n | TODO state menu (short form of `<leader>vt`) |
| `<leader>u` | n | Undotree |
| `<leader>v` | x | Substitute, very magic |
| `<leader>y` | n, x | Yank to clipboard |

## `<leader>l` – AI (LLMs)

See [llm.md](llm.md).

| Key | Mode | What |
|---|---|---|
| `<leader>la` | n, x | Chat: show / hide (like <leader>tt) |
| `<leader>lb` | n | Run the ```` ```llm ```` block under the cursor |
| `<leader>lc` | n, x | Review the code |
| `<leader>ld` | n | Daily note: next step and the measured day (the action `Daily note` of the vault's `ai/actions`) |
| `<leader>lh` | n | Past answers |
| `<leader>li` | n, x | Write here (visual: rewrite) |
| `<leader>lp` | n | Personas: pick one from the list, open its chat (`/name`, see [llm.md](llm.md#personas)) |
| `<leader>lj` | n | Job assistant: the chat with the `/job` persona, waiting for your question (see [llm.md](llm.md#personas-name)) |
| `<leader>lm` | n | Select model (Ollama / Claude / agy) |
| `<leader>lr` | n, x | Repeat the last request |
| `<leader>ls` | n | Stop |
| `<leader>lq` | n | Quit the AI: stop, unload models, close Ollama |
| `<leader>lt` | n | Thinking of <leader>li (show / hide) |
| `<leader>lu` | n | User context file (what the LLMs know about you) |
| `<leader>lw` | n | Weekly note: the week in one place (the action `Week review` of the vault's `ai/actions`) |
| `<leader>lx` | n, x | Actions (claude/ folder of the vault) |

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

The folders of `<leader>e_`, `<leader>f_` and `<leader>n_` (home, `~/.config`, the nvim config, Projects)
are `vim.g.pure_dirs` in `configs.lua` (defaults in `configs/functions.lua`, `dir`); the vault is the
current one of `vim.g.pure_vaults`.

| Key | Mode | What |
|---|---|---|
| `<leader>e.` | n | Explore ~/.config |
| `<leader>ee` | n | Explore current directory |
| `<leader>en` | n | Explore nvim config |
| `<leader>ep` | n | Explore the Projects directory |
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
| `<leader>f'` | n | Registers (the same as `<leader>f"`) |
| `<leader>fl` | n | Notes linking here (backlinks, also <leader>vb) |
| `<leader>fn` | n | Find in nvim config |
| `<leader>fp` | n | Find in Projects |
| `<leader>fv` | n | Find a note, heading or alias in the vault (same as `<leader>vf`) |
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

## `<leader>L` – LSP

| Key | Mode | What |
|---|---|---|
| `<leader>La` | n | LSP code action |
| `<leader>Ldb` | x | Print selection via lua |
| `<leader>Lr` | n | LSP rename |
| `<leader>Ls` | n | LSP workspace symbols |

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

## `<leader>o` – Open

The vault's notes below open by name (`configs/functions.lua` openVaultNote): the `notes` of the vault's
entry in `vim.g.pure_vaults` (`configs.lua`; defaults in `pure/vault.lua`, without extension: the vault's
format adds it); the paths in the table are the defaults of an org vault.

| Key | Mode | What |
|---|---|---|
| `<leader>oi` | n | The vault's inbox, where new things land (`inbox.org`) |
| `<leader>on` | n | The sprouts' note, where young ideas grow (`garden/nursery.org`) |
| `<leader>ot` | n | The tasks (`tasks.org`) |
| `<leader>ob` | n | The books (`sources/books.org`) |
| `<leader>oq` | n | The quotes (`sources/quotes.org`) |
| `<leader>oc` | n | The concepts (`sources/concepts.org`) |
| `<leader>of` | n | Toggle the floating terminal (was `<leader>ot`) |
| `<leader>oC` | n | Toggle the Claude terminal (was `<leader>oc`) |
| `<leader>om` | n | New tab in terminal mode |
| `<leader>od` | n | Todoist: all tasks |
| `<leader>oD` | n | Todoist: today and overdue |

The descriptions say what a note is for, not its file name, so they stay true when a file is renamed.

## `<leader>s` – Split

| Key | Mode | What |
|---|---|---|
| `<leader>sh` | n | Focus split window left |
| `<leader>sj` | n | Focus split window below |
| `<leader>sk` | n | Focus split window above |
| `<leader>sl` | n | Focus split window right |
| `<leader>sn` | n | New split horizontally |
| `<leader>sv` | n | New split vertically |
| `<leader>sq` | n | Close split window |
| `<leader>so` | n | Close all other split windows |
| `<leader>s=` | n | Taller split window |
| `<leader>s-` | n | Shorter split window |
| `<leader>s,` | n | Wider split window |
| `<leader>s.` | n | Narrower split window |

## `<leader>t` – Toggles

Every toggle says what it did in a notice ("Wrap on", "Wrap off", ...); `<leader>tn` flips both number
options and says "Line numbers on/off" once.

| Key | Mode | What |
|---|---|---|
| `<leader>tb` | n | Toggle the grey background of `TODO:` lines (saved; default `vim.g.pure_todo_bg`) |
| `<leader>tc` | n | Toggle signcolumn |
| `<leader>td` | n | Toggle diagnostics |
| `<leader>th` | n | Toggle word highlight (also `<leader>h`) |
| `<leader>ti` | n | Toggle inlay hints |
| `<leader>tm` | n | Toggle note rendering on / off (markdown or org, by the buffer), without the big headings |
| `<leader>tM` | n | Toggle the big headings (OSC 66 / DECDHL) of markdown and org; off by default |
| `<leader>tn` | n, x | Toggle line numbers |
| `<leader>tp` | n | Toggle Copilot |
| `<leader>tr` | n, x | Toggle relativenumber |
| `<leader>tR` | n | Toggle reading mode (wide margins) |
| `<leader>ts` | n | Toggle statusline |
| `<leader>tt` | n | Toggle tabline |
| `<leader>tT` | n | Toggle shrinking of org tables wider than the window (columns cut with `…`, text untouched) |
| `<leader>tw` | n | Toggle wrap |
| `<leader>tW` | n | Toggle wrapping of org tables wider than the window into extra rows (changes the text, off joins it back) |
| `<leader>tH` | n | Toggle the coloured bar behind md and org headings |
| `<leader>tx` | n | Toggle transparency |
| `<leader>tz` | n | Toggle zen mode |

## `<leader>v` – the vault (org notes, `pure/vault.lua`)

| Key | Mode | What |
|---|---|---|
| `<leader>vf` | n | Find a note, a heading or an alias in one coloured picker (as Doom's `SPC v f`); a title that matches nothing makes a seed |
| `<leader>vF` | n | Find a file of the vault |
| `<leader>vg` | n | Grep the vault |
| `<leader>vN` | n | New note in its own file |
| `<leader>vq` | n | Quick capture: the template menu (`s` seed, `t` task, `T` task + deadline, `l` link, `f` source, `j` journal). Was `<leader>vt` until 2026-11-08 |
| `<leader>vn` | n | Grow the idea at the cursor, as Doom's `SPC v n`: SEED > SPROUT > PLANT > TREE; a SEED of `inbox.org` becomes a SPROUT and moves to `garden/nursery.org`; a SPROUT becomes a PLANT in a note of its own, `garden/<title>.org` (a new seed is `<leader>vq n`, the node capture with no `:TYPE:`) |
| `<leader>vt` | n | TODO state menu of the heading (org.nvim's `todo_select`, `<leader>mS`): it offers the states of the note (`#+TODO:` line): only the garden's in `inbox.org`, only the tasks' in `tasks.org`, both elsewhere. Also `<leader>T` |
| `<leader>va` | n | Agenda, its menu (same as `<leader>a` and `<leader>ma`) |
| `<leader>vm` | n | Move the heading at the cursor (with what is under it) to another note: the note of `sources/` named by its `:TYPE:` (any case), or one picked in the fzf list; links are by `:ID:`, none breaks |
| `<leader>vc` | n | Let the idea go, as Doom's `SPC v c`: asks first (No by default), then COMPOST, moved to `archive/compost.org` (nothing is erased) |
| `<leader>vi` | n | Insert a link to a node: the picker of `<leader>vf`, then `[[id:ID][Title]]` at the cursor (typing `[[` in an org note opens the same list as a menu, see [org.md](org.md)) |
| `<leader>vb` | n | Backlinks (notes linking here) |
| `<leader>vr` | n | Rename this note (title and file; links are by `:ID:`) |
| `<leader>vd` | n | Delete this note (moved to `archive/trash/`) |
| `<leader>vj` | n | Journal line (today) |
| `<leader>vJ` | n | Today in the journal |
| `<leader>ve` | n | Explore the vault |
| `<leader>vs` | n | Save the notes and commit (pull and push when there is an upstream) |
| `<leader>vp` | n | Preview the linked note (org notes; markdown keeps `linkview`) |

`<leader>ev`, `<leader>fv`, `<leader>nv` and `<leader>gv` follow the vault too.

## `<leader>w` – Tabs, window view

| Key | Mode | What |
|---|---|---|
| `<leader>wh` | n | Previous tab |
| `<leader>wl` | n | Next tab |
| `<leader>wn` | n | New tab |
| `<leader>wo` | n | Close other tabs |
| `<leader>wq` | n | Close tab |

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
| `K` | Follow link (also an org [[url][text]] link), else LSP hover |
| `S` | Surround: f function, l link |
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
| `S` | Surround: f function, l link |
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

Text objects (`is`, `ic`, `iq`, `ii`, `in` …): see [editing.md](editing.md).
