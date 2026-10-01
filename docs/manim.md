# Manim preview (`lua/pure/manim.lua`)

A window that plays the [Manim](https://www.manim.community) scene you are
writing, and plays it again every time you save; also only a part of it,
a picture of one moment, or the scene live with a camera you move.

| Key | What |
|---|---|
| `<leader>mm` | start the preview of the scene under the cursor (the `class X(Scene)` above it; asked when the cursor is on none). Again: stop it |
| `<leader>ms` | preview another scene of the file |
| `<leader>mp` | preview **only a part**: the selected lines, or the block the cursor is in (below) |
| `<leader>mf` | a **picture** of the scene as it is at the cursor line |
| `<leader>mi` | **live window** at the cursor line: move the camera with the mouse (3D), with a Python shell below. Again: close it |
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

## Only a part: `<leader>mp`, `<leader>mf`

Testing one moment of a long scene without watching it all from the
start. Split `construct()` into blocks with a comment line each, like the
cells of a notebook:

```python
def construct(self):
    # Cria o quadrado
    a = Square(color=BLUE)
    self.play(Create(a))

    # Move para a esquerda          <- cursor anywhere in here, <leader>mp
    self.play(a.animate.shift(LEFT))
    self.wait(0.5)

    # Fica vermelho
    self.play(a.animate.set_color(RED))
```

`<leader>mp` there renders only "Move para a esquerda": animations 1 and 2.
The ones before are applied without being rendered, so the part starts
with the square already made, and the scene stops after the part. In
visual mode it takes the selected lines instead. Without comment lines,
the block is the whole `construct()`.

`<leader>mf` renders no video, only the last frame after the animations
up to the cursor line: how everything looks at that point, in about a
second. The window shows the picture.

Either keeps going on every save, for the same lines: edits above them
move them along. `<leader>mm` goes back to the whole scene.

How it works: Manim numbers the animations as it plays them, every
`self.play(...)` and `self.wait(...)` from 0, and `manim -n A,B` renders
only A to B (`-s -n 0,B` for the picture). The lines become those numbers
by counting the calls written in `construct()` above them. A `self.play`
inside a loop or in another method counts once there, so in such scenes
the numbers can be off. The notification says which animations were
rendered ("Blocos, animations 1-2 ready").

## Live, with the camera: `<leader>mi`

For 3D scenes (`ThreeDScene`, `ThreeDAxes`, `Surface`…): looking at the
scene from any side, not only from the camera the code sets. `<leader>mi`
runs the scene up to the cursor line in Manim's **OpenGL renderer**, which
draws it live in a window instead of making a video:

| In the window | What |
|---|---|
| drag (left button) | orbit the camera around the scene |
| drag (middle button) | move the camera sideways |
| wheel | zoom in / out |
| `r` | camera back to where it started |

Below the code, a terminal opens with an **IPython shell** holding the
scene as it is at that line: `self`, and `play(...)`, `add(...)`,
`remove(...)`, `wait()` without the `self.`. Try an animation there and
see it in the window. `exit` lets the scene play on to its end; the
window and the terminal close. `<leader>mi` again stops it at once.

The animations before the cursor are applied without being played, so the
window opens at that point straight away. Your file is not changed: a
copy with `self.interactive_embed()` added after the statement at the
cursor is what runs (in Neovim's cache folder, from your file's folder, so
imports and asset paths work). The cursor can be anywhere in a statement
that spans lines; on a `for …:` line, the window opens inside the loop.

It needs **IPython** (`pip install ipython`, which Manim does not install
by itself) and OpenGL 3.3, which any recent computer has. The OpenGL
renderer is still experimental in Manim: a few things (some text and
effects) look different from the final video, and some animations do not
work in it. Make the final video with the usual renderer (`<leader>mm` or
`manim -qh`).

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

The live window (`<leader>mi`) also needs IPython: `pip install ipython`.
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
