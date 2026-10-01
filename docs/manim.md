# Manim preview (`lua/pure/manim.lua`)

A window that plays the [Manim](https://www.manim.community) scene you are
writing, and plays it again every time you save.

| Key | What |
|---|---|
| `<leader>mm` | start the preview of the scene under the cursor (the `class X(Scene)` above it; asked when the cursor is on none). Again: stop it |
| `<leader>ms` | preview another scene of the file |
| `:ManimPreview [Scene]` | the same, with the scene by name (completes the file's scenes) |
| `:ManimLog` | the whole output of the last render |
| `:ManimStop` | stop the preview and close the window |

On every `:w` of that file, Manim renders the scene in the background, and
the window loads the new video and loops it. Neovim stays free while it
renders.

- A notification says when it starts and when it is ready, with the
  seconds it took.
- Saving again while it renders drops the old render for the new one.
- **An error** says its message and line (`Quadrado failed (line 5):
  NameError: name 'Squaree' is not defined`), and puts the place in the
  quickfix list (`:copen`, then `<CR>` on it); `:ManimLog` has the whole
  traceback.
- Low quality by default (480p, 15 fps): it renders fast, which matters
  more while writing. Render the final video yourself, as usual
  (`manim -qh cena.py Cena`).

The videos go to Neovim's cache folder (`stdpath('cache')/manim`), never
into the project, and the old ones are removed as new ones come.

## The window: mpv

The window is [mpv](https://mpv.io), on Linux, macOS and Windows. Neovim
drives it through mpv's control socket, so it stays open and only swaps
the video. Close it any time; the next save opens it again. Without mpv,
each render opens in the system's video player instead.

## Installing

Manim (Community Edition) and mpv, once per machine:

| System | Manim | mpv |
|---|---|---|
| Linux (Debian/Ubuntu) | `sudo apt install libpango1.0-dev pkg-config python3-dev` then `pip install manim` | `sudo apt install mpv` |
| macOS | `brew install py3cairo pango pkg-config` then `pip install manim` | `brew install mpv` |
| Windows | `pip install manim` (or `py -m pip install manim`) | `winget install mpv` (or `scoop install mpv`) |

Formulas (`MathTex`, `Tex`) also need LaTeX: TeX Live (Linux), MacTeX
(macOS), MiKTeX (Windows). The rest of Manim works without it.

`manim` is looked for on the PATH; without it, through Python
(`python3 -m manim`, `py -m manim` on Windows), so a pip install that did
not put it on the PATH works too.

## Settings

```lua
vim.g.pure_manim_cmd = 'manim'          -- or { 'python', '-m', 'manim' }, or a venv's manim
vim.g.pure_manim_quality = 'l'          -- l (480p15), m (720p30), h (1080p60)
vim.g.pure_manim_args = {}              -- more arguments for manim
vim.g.pure_manim_viewer_args = {}       -- more for mpv, e.g. { '--geometry=40%-0-0', '--ontop' }:
                                        -- smaller, bottom right, above the other windows
```
