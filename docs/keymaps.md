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
| `<leader>ad` | n | Daily note: next step and the measured day (the vault action `Nota do dia`) |
| `<leader>ah` | n | Past answers |
| `<leader>ai` | n, x | Write here (visual: rewrite) |
| `<leader>aj` | n | Job assistant: the chat with the `/job` persona, waiting for your question (see [llm.md](llm.md#personas-name)) |
| `<leader>am` | n | Select model (Ollama / Claude / agy) |
| `<leader>ar` | n, x | Repeat the last request |
| `<leader>as` | n | Stop |
| `<leader>aq` | n | Quit the AI: stop, unload models, close Ollama |
| `<leader>at` | n | Thinking of <leader>ai (show / hide) |
| `<leader>au` | n | User context file (what the LLMs know about you) |
| `<leader>aw` | n | Weekly note: the week in one place (the vault action `Nota da semana`) |
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
| `<leader>fl` | n | Notes linking here (backlinks, also <leader>vb) |
| `<leader>fn` | n | Find in nvim config |
| `<leader>fv` | n | Find in Atlas, the Obsidian vault |
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

## `<leader>m` – Manim

See [manim.md](manim.md).

| Key | Mode | What |
|---|---|---|
| `<leader>mm` | n | Preview the scene, again on every save (toggle) |
| `<leader>ms` | n | Preview another scene |
| `<leader>mp` | n, x | Preview only this part (selection, or the block under the cursor) |
| `<leader>mf` | n | Picture of the scene at this line |
| `<leader>mi` | n | Live window at this line: mouse camera, Python shell (toggle) |

## `<leader>n` – New file / folder

| Key | Mode | What |
|---|---|---|
| `<leader>n.` | n | New file in ~/.config |
| `<leader>nd` | n | New folder here |
| `<leader>ne` | n | New file here |
| `<leader>nf` | n | New file, pick the folder (from two levels up) |
| `<leader>nh` | n | New file in home |
| `<leader>nn` | n | New file in nvim config |
| `<leader>nv` | n | New note in the vault's inbox |

## `<leader>o` – Toggles

| Key | Mode | What |
|---|---|---|
| `<leader>oc` | n | Toggle signcolumn |
| `<leader>od` | n | Toggle diagnostics |
| `<leader>oh` | n | Toggle word highlight |
| `<leader>oi` | n | Toggle inlay hints |
| `<leader>om` | n | Toggle markdown rendering |
| `<leader>on` | n, x | Toggle line numbers |
| `<leader>op` | n | Toggle Copilot |
| `<leader>or` | n, x | Toggle relativenumber |
| `<leader>os` | n | Toggle statusline |
| `<leader>ot` | n | Toggle tabline |
| `<leader>ow` | n | Toggle wrap |
| `<leader>ox` | n | Transparent mode |
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

## `<leader>v` – Vault

| Key | Mode | What |
|---|---|---|
| `<leader>vb` | n | Backlinks (notes linking here) |
| `<leader>vd` | n | Delete note (to the vault's trash) |
| `<leader>ve` | n | Explore the vault |
| `<leader>vf` | n | Find a note |
| `<leader>vg` | n | Grep the vault |
| `<leader>vn` | n | New note (inbox, asks the name only) |
| `<leader>vr` | n | Rename note, fix links to it |
| `<leader>vs` | n | Sync the vault (git) |
| `<leader>vN` | n | New note from a template (born in its folder) |
| `<leader>vt` | n | Apply a template |

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
| `aq` | Smart outer quotes |
| `as` | Outer square brackets |
| `gc` | Toggle comment |
| `gh` | First non-blank |
| `gl` | End of line |
| `i.` | Inner sentence |
| `ic` | Inner curly brackets |
| `ii` | Inner indent scope |
| `in` | Select child (inner) node |
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
| `<Esc><Esc>` | Close terminal |
| `<S-Esc>` | Leave terminal mode |

Text objects (`is`, `ic`, `iq`, `ii`, `in` …): see [editing.md](editing.md).
