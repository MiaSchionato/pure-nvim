# Interface (`dashboard`, `statusline`, `notify`, `terms`, themes)

## Dashboard (`lua/pure/dashboard.lua`, `ascii.lua`)

Shown when Neovim starts without a file. The planet (`ascii.lua`,
`M.saturn`) is centred and scaled up by the largest whole factor that fits
the window, and redrawn when the window changes size.

| Key | What |
|---|---|
| `n` | new empty buffer |
| `q` | quit |
| `u` | update plugins (`vim.pack.update()`) |

`vim.g.pure_dashboard_scale = 1` keeps the drawing at its original size (any
number fixes the scale; `'auto'` is the default). The statusline, tabline and
line numbers are hidden while it is shown and come back after.

## Statusline (`lua/pure/statusline.lua`)

Left: mode (coloured), error count, file name and `[+]` when modified.
Right: macro being recorded, pending keys (`showcmd`), filetype icon, line:column.
Each window shows its own file, errors and filetype; only the active window
shows the mode. Colours come from the theme when it defines them
(myghtfly does), otherwise from built-in defaults.

`<leader>os` hides / shows it, `<leader>ot` the tabline, `<leader>oz` zen mode
(no bars, no numbers).

## Tabline (`configs/functions.lua`, `MyTabline`)

Shown only with two or more tabs. Tabs: `<leader>wn` new, `wh` / `wl`
previous / next, `wq` close, `wo` close the others.

## Notifications (`lua/pure/notify.lua`)

Every `vim.notify` message appears in a floating window in the top-right
corner, newest at the bottom, and goes away after 4 s (warnings 6 s, errors
8 s). `:Notifications` opens the history in a split.

Colours: `PureNotifyNormal`, `PureNotifyBorder`; warnings and errors use the
theme's `DiagnosticWarn` / `DiagnosticError`.

## Terminal (`lua/pure/terms.lua`)

| Key | What |
|---|---|
| `<leader>tt` | floating terminal (toggle; it keeps running when hidden) |
| `<leader>tg` | floating terminal running `gemini` |
| `<Esc><Esc>` | close the terminal |
| `<S-Esc>` | leave terminal mode (to scroll / copy) |

The shell: `vim.g.pure_terminal_shell` if set; on Windows the first of `nu`,
`pwsh`, `powershell` found (separate from the Git bash the pickers use);
elsewhere `'shell'`.

## Themes (`lua/themes/colorschemes.lua`, `colors/`)

`<leader>fc` picks a colorscheme; it is remembered across restarts. The
default is `myghtfly` (in `colors/`). `<leader>ox` makes the background
transparent. In Neovide the transparency is off (`configs/neovide.lua`).

## Toggles (`<leader>o…`)

| Key | Toggles |
|---|---|
| `oc` | sign column |
| `od` | diagnostics |
| `oh` (also `<leader>h`) | highlight of the word under the cursor, everywhere |
| `oi` | inlay hints |
| `om` | markdown drawing |
| `on` / `or` | line numbers / relative numbers |
| `op` | Copilot |
| `os` / `ot` | statusline / tabline |
| `ow` | wrap |
| `ox` | transparent background |
| `oz` | zen mode: no bars, numbers, sign column, inlay hints or inline diagnostics |

## Highlighted comments

A line with `TODO:` gets a grey background in file buffers.
`<leader>ct` inserts a TODO comment.
