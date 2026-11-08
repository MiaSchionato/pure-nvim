# Interface (`dashboard`, `statusline`, `notify`, `terms`, themes)

## Dashboard (`lua/pure/dashboard.lua`, `ascii.lua`)

Shown when Neovim starts without a file. A new tab (`:tabnew`, `<leader>wn`) opens on the
[scratch note](#scratch-note-luapurescratchlua) instead (`vim.g.pure_newtab = 'dashboard'` shows the
dashboard there again); a tab opened on something (`:tabnew file`, `:tab help`) is left alone. The planet (`ascii.lua`,
`M.saturn`) is centred and scaled up by the largest whole factor that fits
the window, and redrawn when the window changes size. Blank lines fill the
window to the bottom, so no `~` shows under the drawing.

| Key | What |
|---|---|
| `d` | today in the vault's journal (org-roam dailies, same as `<leader>vJ`; [org](org.md)) |
| `l` | the last note (org or markdown) of the vault that was open, at the line where it was left (else the last file Neovim was closed on, `'0`) |
| `n` | the scratch note (below) |
| `v` | a seed in the vault's inbox (the node capture, same as `<leader>vq n`) |
| `q` | quit; in a tab while others are open, close just that tab |
| `u` | update: the configuration's repository, then the plugins (below) |

### Updating (`u`, or `:PureUpdate` anywhere – `lua/pure/update.lua`)

Keeps machines in step: commit and push on one, press `u` on the other.

1. `git fetch` in the config folder, in the background (a clone of
   `main` / `windows`, or of `single-file`).
2. New commits upstream: they are listed, and **Yes** pulls them
   (`--ff-only`: it never merges or overwrites anything).
3. After a pull it offers to restart Neovim (`:restart`) so the new
   configuration runs; press `u` again then for the plugins, which the new
   configuration may have changed.
4. Nothing new (or no restart): the plugins are updated **silently**, by a
   separate Neovim in the background – no report buffer, no progress
   messages, the editor stays free. One notification at the end names the
   plugins that changed (restart to use them); the details go to
   `nvim-pack.log` in `stdpath('log')`. Skipped in the portable one-file
   build.

Every question defaults to **Yes**: Enter answers it.

It touches nothing, and says why, when this machine has commits that were
not pushed while upstream has new ones (pull by hand to merge them), or when
a local change to a file would be overwritten by the pull.

`vim.g.pure_dashboard_scale = 1` keeps the drawing at its original size (any
number fixes the scale; `'auto'` is the default). The statusline and line
numbers are hidden while it is shown and come back after, tab by tab: another
tab keeps its own. The tabline is hidden too, unless other tabs are open.

## Statusline (`lua/pure/statusline.lua`)

Left: mode (coloured), error count, file name and `[+]` when modified.
Right: macro being recorded, pending keys (`showcmd`), filetype icon, line:column.
Each window shows its own file, errors and filetype; only the active window
shows the mode. Colours come from the theme when it defines them
(myghtfly does), otherwise from built-in defaults.

`<leader>os` hides / shows it, `<leader>ot` the tabline, `<leader>oz` zen mode
(no bars, no numbers).

## Scratch note (`lua/pure/scratch.lua`)

Emacs' `*scratch*`, in a file: one note for whatever has no other place. It is the same buffer in
every tab and window, and a new tab opens on it. As `*scratch*`, it starts empty every time: its
file (`stdpath('data')/scratch.org`) is deleted when Neovim exits. While Neovim runs the file is
written when you stop typing, leave the buffer or lose focus, so a crash does not lose the text
(it is still there on the next start and goes at the next normal exit; closing one of two running
Neovims deletes the file for both). `vim.g.pure_scratch_keep = true` keeps the note across exits.
`<leader>ns` or `n` on the dashboard opens it in the current window; `:Scratch` too, and
`:Scratch clear` empties it. Settings: `vim.g.pure_scratch_filetype` (default `'org'`),
`vim.g.pure_scratch_file` (the path), `vim.g.pure_scratch_message` (the first line of an empty
note), `vim.g.pure_newtab` (`'scratch'` default, `'dashboard'`, `'empty'`).

**Where the note stands.** It lives in the data folder, so each window that shows it remembers the
folder it was opened from (the file the window showed before, or the previous tab's file for a new
tab, or the working folder). The pickers that start from the current file's folder start from that
one (`require('pure.scratch').dir(levels)`), and it is also the buffer's working folder, set with
`:bcd` (Neovim 0.13+), so `:terminal`, `:grep`, `:make` and `:!` run there too. The folder follows
the window you enter, and it does not leak: another buffer keeps the global working folder.

## Tabline (`configs/functions.lua`, `MyTabline`)

Shown only with two or more tabs. Tabs: `<leader>wn` new (on the scratch note), `wh` / `wl`
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
| `<Esc>` | leave terminal mode at once (to scroll / copy) |
| `<Esc>` again, within 250 ms | close (hide) the terminal; it keeps running |
| `<A-Esc>` | send a real `<Esc>` to the shell |
| `<Esc><Esc>` | close the terminal, for the ones running a command (`<leader>tc`, `<leader>tg`) |
| `<S-Esc>` | leave terminal mode |

`vim.g.terminal_esc_ms` (default 250) is the time for the second `<Esc>`;
`0` / `false` goes back to `<Esc><Esc>` only, with `<Esc>` reaching the
shell. The terminal in a tab (`<leader>tm`) is not touched. The fuzzy pickers
are never left with `<Esc>`: it always closes them (see [fuzzy.md](fuzzy.md)).

The shell: `vim.g.pure_terminal_shell` if set; on Windows the first of `nu`,
`pwsh`, `powershell` found (separate from the Git bash the pickers use);
elsewhere `'shell'`.

## Remote (`lua/pure/remote.lua`)

The first Neovim started listens at a fixed address, `/tmp/nvim-remote.sock`
(`vim.g.remote_socket`; `''` turns it off), so a program outside can open a
file in it instead of starting another one:

```
nvim --server /tmp/nvim-remote.sock --remote 'vault/inbox.org'
```

The Flow Launcher plugin `nv` does this. A Neovim started while another owns
the address does not listen there; a socket left by a Neovim that died is
replaced. Not on Windows (named pipes) and not in headless runs.

## Themes (`lua/themes/colorschemes.lua`, `colors/`)

`<leader>fc` picks a colorscheme; it is remembered across restarts, in
`stdpath('data')/colorscheme` (ShaDa carried it before, but only on a clean exit,
and the last instance to exit overwrote the others). Only `configs/autocmds.lua`
applies the saved theme (on `VimEnter`); no theme applies itself. Nothing saved yet:
`myghtfly` (the local one in `colors/`), which is also used when the saved theme is
not installed. Reading the saved choice at startup never changes it, so a fallback
does not overwrite it.

Every theme starts **opaque**, with its own background: `themes/colorschemes.lua`
turns off the transparency that `NeoSolarized` and `solarized-osaka` have by default.

The first entry of the list, **omarchy**, follows the Omarchy theme: it uses the
colorscheme that goes with the current theme (`omarchy theme current`), now, on
every start, and when the theme changes while Neovim is open (checked when the
terminal gets focus back). The colorscheme is read from the theme's own
`neovim.lua` (`colorscheme = "…"`), or matched by name when the theme has none
(`lua/pure/omarchy-theme.lua`). A theme plugin that is not installed is added
with `vim.pack`, which asks first. A theme with no matching colorscheme (e.g.
`vantablack`) gives a warning and the local theme.

### Transparency (`<leader>oxc`)

One variable, `require('configs.functions').transparent`, says whether the editor is
transparent (`false` at startup). `<leader>oxc` flips it:

- **Terminal**: transparent clears the background of the groups in
  `themes.colorschemes.groups`; going back applies the colorscheme again, which
  brings its own background back (nothing is saved or restored by hand).
- **Neovide**: the window opacity goes between `1.0` (the start) and
  `vim.g.transparencyAmount` (`configs/configs.lua`).

Changing the colorscheme keeps the state, so a transparent session stays transparent.
Going back to opaque does not change the saved theme.

## Toggles (`<leader>o…`)

| Key | Toggles |
|---|---|
| `oc` | sign column |
| `od` | diagnostics |
| `oh` (also `<leader>h`) | highlight of the word under the cursor, everywhere |
| `oi` | inlay hints |
| `om` | markdown and org drawing (org: full, no big headlines, off) |
| `oH` | the coloured bar behind md and org headings |
| `on` / `or` | line numbers / relative numbers |
| `op` | Copilot |
| `os` / `ot` | statusline / tabline |
| `ow` | wrap |
| `oxc` | transparent background |
| `oz` | zen mode: no bars, numbers, sign column, inlay hints or inline diagnostics |
| reading mode (`<leader>tR`, `:PureReading`) | a column of text in the middle between wide margins (below) |

**Reading mode** (`lua/pure/reading.lua`): two empty windows, one on each side, take the width the
text does not need, so the window with the text is a column (`vim.g.pure_reading_width`, 84 by
default) and lines wrap at its width. The margins are plain windows, not padding drawn in the text,
so wrapping, the cursor and the other modules see an ordinary window; the cursor never stays in
one (entering a margin goes back to the text) and `:q` closes them first, so it quits as it would
without them. `vim.g.pure_reading_min` (4) is the smallest margin. It is per tab, saved like the other
toggles (key `reading`) and applied again at the next start and in new tabs that open on a file.
Splits inside the column are laid out for the window as it was when the mode started: toggle it off
and on to lay it out again. WezTerm's big headings (DECDHL) need the full width, so they fall back
to the icon and band while the margins are there.

**How many columns:** `:PureReading width 100` sets the width of the text column (applied at once, in
every tab, and saved: it is still 100 the next time), `:PureReading width +8` / `-8` makes it wider or
narrower by 8, `:PureReading width` shows it. It is kept between 30 and 400. A width chosen with the
command wins over `vim.g.pure_reading_width`, which is only the starting value (84).

The toggles stay as you left them (`lua/configs/functions.lua`): a toggle you press is saved in
`stdpath('data')/toggles.json` and applied again on the next start. That covers the note
rendering (markdown on/off, org full / no big headlines / off), the heading bar, transparency,
diagnostics, statusline, tabline, sign column, wrap, line numbers, inlay hints and Copilot. Until a
toggle is pressed, the default of `configs.lua` applies. Not saved: zen mode (temporary, it puts
things back) and `oh` (the word highlight follows the cursor). `:PureToggles` shows what is saved,
`:PureToggles reset` forgets it all.

## Hex colours (`lua/pure/hexcolors.lua`)

`#7d82d9` is drawn with its own colour behind it (black or white text on top, by brightness).
Neovim already does this in `.lua` and CSS (`vim.lsp.document_color`, fed by `lua_ls` and the CSS
servers); this module covers the files no server handles: markdown, org and text. A buffer with a
server that reports colours is left to that server. Only the lines on screen are looked at and
nothing is written to the buffer.

`:PureHexColors [on|off|toggle]` changes it while Neovim runs. Settings (`lua/configs/configs.lua`):
`vim.g.pure_hexcolors = false` turns it off, `vim.g.pure_hexcolors_filetypes` is the list of
filetypes (default markdown, org, text), `vim.g.pure_hexcolors_style = 'foreground'` colours the text
instead of the background, `vim.g.pure_hexcolors_short = true` also draws `#rgb` (off by default:
it would catch tags like `#bad`).

## Highlighted comments

A line with `TODO:` gets a grey background in file buffers.
`<leader>ct` inserts a TODO comment.
