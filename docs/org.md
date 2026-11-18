# Org notes (`lua/plugins/org.lua`)

[org.nvim](https://github.com/xheisenbugx/org.nvim) on the org vault
(the entry of `vim.g.pure_vaults` with `format = 'org'`; `pure/vault.lua`), set up to behave like the Doom Emacs of the same vault. It is
independent of the Markdown modules (`notes`, `zettelkasten`): those act on
`markdown` buffers, org.nvim on `org` ones. Neovim 0.11 or newer.

## What is configured

| Setting | Value |
|---|---|
| Agenda files | `tasks.org`, `inbox.org` (`seedbed.org` from 2026-11-08 to 2026-11-09), `projects/**/*.org`, `garden/*.org` (from 2026-11-09; as `my/garden-agenda-files` in Doom) |
| Task states | `TODO NEXT DOING WAITING \| DONE CANCELLED` |
| Idea stages | `SEED SPROUT PLANT TREE FRUIT \| COMPOST` (FRUIT was FLOWER until 2026-11-08: a tree bears fruit) (keywords must be declared, or a node title would start with `PLANT`) |
| Keyword colours | the Ethereal palette |
| Roam directory | the whole vault, except `journal/` and `journal.org` |
| Daily notes | `journal.org` at the root of the vault, one entry per day in its date tree |

## Capture (`<leader>mc`, then a key)

The keys of the quick capture (Win+Q) of the Emacs side:

| Key | Goes to |
|---|---|
| `t` | a `TODO` in `tasks.org`; no question: the buffer has an empty `SCHEDULED:` line, filled in words (`today`, `tomorrow`, `fri`, `+3d`, `2026-11-20`, also `hoje`, `amanhã`, `oggi`, `domani`) that become a timestamp when stored; left empty, the line is dropped |
| `T` | a `TODO` with a `DEADLINE` (date picked in org.nvim's date float) |
| `l` | a link in `inbox.org`; asks the address (the clipboard is the default) and the title; the buffer then opens in Normal mode, to check them |
| `n` | a node (it replaced `s` seed and `f` source); no question: the buffer has every property, empty (`TYPE AUTHOR STATUS GENRE LANGUAGE BY WHERE RATING NOTES`); the ones left empty are dropped when stored, and `:TYPE:` (any case) says where it goes: `seed` the inbox (`inbox.org`) as a SEED; `sprout` a heading of `garden/nursery.org`; `plant`, `tree`, `fruit` a note of its own in `garden/` (named after the title); `compost` `archive/compost.org` (each with that state, the TYPE line dropped); the name of a note of `sources/` (`books`, `quotes`...) that note (TYPE kept); none, or a type with no note, the inbox as a SEED (`<leader>vm` moves it once the note exists) |

Only `l` asks questions, in the input float in the centre (`vim.ui.input`,
`pure/fuzzyUtils.lua`, through org.nvim's `utils.input`), in its target function,
before org.nvim opens the inbox, so Esc cancels the capture and leaves nothing behind.
The `:TYPE:` of `n` (`pure.vault.routeNode`) and the words of `t`'s `SCHEDULED:` are read by a store filter
(`org.capture.store_filters.pure_vault`, in `lua/plugins/org.lua`) just before the
entry is stored, so org.nvim's "Captured to ..." names the file it went to. The source
property names are added to org.nvim's completion of property names (after `:` in a
drawer); property names are not case sensitive for org (`Author` = `AUTHOR`). A `%` in an answer stays a `%`
(org.nvim would read `%a`, `%^{...}` as escapes: the template carries it as a
private-use character and its hook puts the `%` back).
The lists, the questions and the capture buffer share one size (`CAPTURE_RATIO`,
0.8): the same width, left edge and top row, so each opens where the last one was;
a question is one line at that top edge.
| `j` | a line `* HH:MM text` in `journal.org`, under today's date |

The text is written in a centred floating window (`capture.window = 'pure_float'`: the
config's `createWindow`, 80% of the screen, the same look as the terminals), not in
a split, and without org.nvim's key hint bar. `:w` or `<C-c><C-c>` stores the entry
and closes the window; `:q` closes it and drops the entry; `<C-c><C-k>` aborts.
org.nvim's window modes are strings only, so `lua/plugins/org.lua` wraps its window
opener (`org.ui.open_buffer_window`) for that one mode; every other window is org.nvim's.

### Captures from outside (`remote.enabled`)

`remote = { enabled = true }` (2026-11-12): the first Neovim that sets org up is org.nvim's
session server, listening on `\\.\pipe\org.nvim.<user>` (Windows; a socket in the runtime
directory elsewhere). The `org` command line, org-protocol URLs and `org.api.remote.call()`
send their requests there, so they change that Neovim's buffers instead of the files behind
its back; another Neovim takes over the address when it gets the focus after the server
quit. The Quick Capture plugin of Flow Launcher (`q`, `qs`, `qt`...) captures this way: the
entry lands in the open note, with undo. org.nvim saves the buffer after a capture, so
changes not saved yet are saved with it. With no server running, the capture writes the file.

On Windows the address is set as `//./pipe/org.nvim.<user>`: org.nvim's default spells the same
pipe `\\.\pipe\...`, but `serverlist()` reports it with forward slashes, so the Neovim serving it
did not see itself as the server (`require('org.remote').is_server()` was false).

## States per note (`#+TODO:`)

The config has two sets of states: the tasks' (`TODO NEXT DOING WAITING | DONE CANCELLED`) and
the garden's (`SEED SPROUT PLANT TREE FRUIT | COMPOST`). A note with a `#+TODO:` line of its own
keeps only those sets, as in Emacs: `inbox.org` has only the garden's, `tasks.org` only the tasks'.
So the state menu (`<leader>vt` or `<leader>T`, org.nvim's `<leader>mS` or `<C-c><C-t>`) and `t` in
the agenda (which uses the note of the entry) offer only the right ones there; a keyword of the other
set in those two is plain text. Every other note has both: `garden/nursery.org` and the notes of
`garden/` with both lines (the garden's first), notes without a line (`projects/`...) by default. A new
note made by grow (`<leader>vn`) or the node capture gets both lines.

## Agenda (`<leader>a`)

`<leader>a` (or org.nvim's own `<leader>ma`) opens the agenda's menu: `a` the week, `t` every
open item, `m` a tags / property match, `s` a word search. It reads `tasks.org`, `inbox.org`,
`projects/**/*.org` and `garden/*.org` (`agenda_files`). The agenda opens floating (`agenda = { window = 'float' }`),
in the config's window at the size and place of the capture windows (`CAPTURE_RATIO`): the window
opener of `lua/plugins/org.lua` takes org.nvim's "Org Agenda" float too. `<CR>` or `<Tab>` on an
entry closes the float and opens the note in the window behind; `q` closes it. `g?` lists its keys.

## Tables made from headings (dynamic blocks)

A `#+BEGIN: columnview ... #+END:` block builds a table from the properties of the
headings (the columns are the file's `#+COLUMNS:`), as in Emacs. `sources/books.org`
has one: a heading per book, the table at the top. Every dynamic block of a note of
the vault is made again when the note is saved, so the table follows its headings:
by hand (`:w`) and when org.nvim writes the file itself (a capture, a refile). It is
a write hook of org.nvim (`org.write_hooks`, in `lua/plugins/org.lua`), because
org.nvim writes those with `:noautocmd`; silent. `C-c C-c` on the block (or
`<leader>mxU`) updates it by hand, in Doom too. Notes outside the vault are left alone.

```org
#+COLUMNS: %ITEM(Book) %AUTHOR(Author) %STATUS(Status) %BY(Recommended by) %WHERE(Where)
#+BEGIN: columnview :id global :maxlevel 1
#+END:
```

`:link t` is left out on purpose: org.nvim writes the link with the absolute path of
the file, which differs between machines and from Doom's.

## Org-roam

The `roam` extension of org.nvim, not a separate plugin. It indexes the vault
into a JSON file (`stdpath('data')/org/roam-index.json`), not into SQLite, so
Doom's `org-roam.db` is untouched; the note format is the same, so both
editors can share the vault. A node is a file or a headline with an `:ID:`.
Keys are under `<leader>mm` (find `f`, insert link `i`, backlinks `l`,
capture `c`, graph `g`) and `<leader>mmd` for the daily notes (`t` today).

## Keys

org.nvim's keys are under `<leader>m` (`mappings = { prefix = '<leader>m' }` in
`lua/plugins/org.lua`; its default is `<leader>o`, the Toggles group). Manim moved to
`<leader>M`. org-roam is `<leader>mm…` and its dailies `<leader>mmd…`; `<leader>mc` is
capture and `<leader>ma` the agenda. Press `g?` in an org buffer, or `<Space>m` and wait,
for the list.

## Rendering

org.nvim's own drawing over the text (concealed links, star bullets,
checkbox icons, indent) is off in `lua/plugins/org.lua`: the rendering is
`lua/pure/render-org.lua`'s, so it can be toggled and follows the terminal.
Its syntax colours stay. The file is the org twin of `render-md.lua` (settings,
view, bigger headlines) and uses the same colours (`pure/notecolors.lua`, which
follow the colorscheme). The text is never changed; marks are drawn over it.

`<leader>tm` turns the drawing on and off, in markdown and in org notes; `<leader>tM` turns the big headlines on (off by default).

| In the note | On screen |
|---|---|
| `* Headline` | icon instead of the stars and a coloured band; `*` and `**` bigger where the terminal can (below) |
| `- item` | bullet per level: • ◦ ▪ ▫ (`vim.g.pure_md_bullets`); `1.` stays |
| `- [ ]` `- [X]` `- [-]` | checkbox icons; done items dimmed |
| `#+begin_src lua` … `#+end_src` | shaded block, the language as a label (any `#+begin_xxx`); quote blocks get a bar |
| `-----` | a full-width line |
| `\| tables \|` | box-drawing borders |
| `[[target][text]]`, `[[target]]` | only the text (or the target); the link under the cursor stays raw |
| `[[id:ID][Note#Heading\|\|alias]]`, `[[Note\|\|alias]]` | only the alias: what is before the `\|\|` stays in the text (to edit, the cursor on the link shows it all) and is hidden by the render |
| `*bold*` `/italic/` `_u_` `=verbatim=` `~code~` `+strike+` | the marks around are hidden (`vim.g.pure_org_emphasis = false` keeps them) |
| `:PROPERTIES:` and `:LOGBOOK:` drawers | hidden; they come back while the cursor is on them |
| `#+title: Name` | drawn as a first-level title |

Blocks and drawers are read first, so a `*` or a link inside a src block is plain text.

**Tables.** org.nvim aligns a table by the width the buffer *shows* (a link counts as its text,
hidden emphasis marks as nothing, like Emacs' `org-string-width`), but only when its own conceal
options are on, and they are off in `lua/plugins/org.lua`. `render-org.lua` sets the per-buffer
flags `b:org_link_descriptive` and `b:org_hide_emphasis_markers` to follow the rendering
(`<leader>tm`) and `vim.g.pure_org_emphasis`, so `|` columns line up on screen. With the
rendering off the raw width is used. `startup_align_all_tables = true` (`lua/plugins/org.lua`)
aligns every table when a note is opened (like `#+STARTUP: align`), so tables written by scripts
show straight at once; the buffer then counts as modified. A table row that is wider than the window *as written* (a long
`[[link]]` counts in full, the render hides it) would wrap into extra screen rows and leave the `│` of the table loose: while
such a row is in view the window does not wrap, and `wrap` comes back when none is (`vim.g.pure_org_table_nowrap = false`
turns it off). In Insert mode `<Tab>` / `<S-Tab>` in a table go to the next / previous cell, and with the completion menu
open they pick the next / previous suggestion.

**Shrinking wide tables (`<leader>tT`).** org.nvim can shrink a column: a column with a width cookie
`<W>` shows the first W characters of each cell and a `…`, and the text is never changed (the drawing
of Emacs' `org-table-shrink`). The toggle works out the widths that make each table wider than the
window fit (columns that fit keep their width, the others share what is left, the widest first) and
hands them to that drawing, so **no cookie is written into the note**. A table with cookies of its
own is left to org.nvim. In Insert mode a table shows in full. While a table is shrunk the window
does not wrap (a raw row longer than the window would take extra screen rows under the drawing),
and `wrap` comes back when none is. Saved as `table_shrink` (the toggles of `configs/functions.lua`);
the code is "Narrowing wide tables" in `lua/pure/render-org.lua`. When a shrunk table is deleted,
org.nvim forgets it but leaves its cell marks (inline virtual text), which pile up on the line where it
was; the toggle clears the whole `org.table.shrink` namespace before each redraw, so they go away.

**Wrapping wide tables into rows (`<leader>tW`).** The other way, and this one **changes the text**:
a cell that does not fit its column continues on the next line, as an extra table row holding only the
rest of that cell (the other cells of that row empty). Widths are worked out as for shrinking, the
rows are written aligned by org.nvim's own formatter, so the table fits the window in the text and on
screen, and nothing needs the window to stop wrapping or the cursor line to be drawn differently. It
runs when a note is opened and when Insert mode is left in a table; a table that already fits is left
alone, and so is one with a `#+TBLFM` line. A `[[link]]` or an `=verbatim=` is never split; a word wider
than its column is cut. The continuation rows are remembered (extmarks), so turning the toggle off joins
them back into their rows (this session only: rows written in an earlier session are ordinary rows).
Saved as `table_wrap`, off by default. **A script that reads the note's tables sees the extra rows**
(the maps of `D:\Assets\_maps` are read by one): do not save a wrapped copy of such a file.
`<leader>tT` and `<leader>tW` work alone or together (wrapped tables fit, so there is nothing left to shrink).

Not covered by the width fix: the `||alias` part of a link, which org.nvim counts but the render hides.

Links keep the buffer's own text: the brackets and the target are concealed and the text
stays, coloured. Neovim sizes a wrapped line by its **raw** width, concealed text included, so
hiding text that would make the line need fewer rows than Neovim reserves leaves a blank row
under it. Such a line (a long `[[id:…][Title]]` in a narrow window) is left as written;
`vim.g.pure_org_conceal_wrapped = true` hides it anyway and accepts the blank row.

The headline text takes the colours of the Markdown headings (`OrgHeadlineLevelN` link to them),
and the statusline shows the org glyph (Nerd Font `nf-custom-orgmode`) for org notes.

### Bigger headlines

Where the terminal can: kitty draws `*` (3x) and `**` (2x) with OSC 66, WezTerm with the
double-height lines (DECDHL, only when the window spans the terminal's width), the others
draw the icon and band. Same checks as the markdown headings: `vim.g.pure_org_headings`
(or `vim.g.pure_md_headings` when nil): `auto`, `osc66`, `decdhl`, `image`, `off`;
`:PureOrgHeadings [auto|osc66|decdhl|image|off]` changes it while Neovim runs. In WSL set it to
`decdhl` for WezTerm, as for markdown. The terminal code is a copy of `render-md.lua`'s.

**Images (`image`)**, the choice of `auto` in a GUI with Neovim's `ext_images` UI extension
(experimental, e.g. Zonvie with a Neovim that has it): each `*` (3 rows) and `**` (2 rows)
headline becomes a PNG shown through `vim.ui.img`, in the headline's colour on the `Normal`
background, with the bold face of the editor font. The image sits just above the headline,
whose own line is hidden (`conceal_lines`) except while the cursor is on it, so it can be
edited; the image stays. A headline on the first line of the file keeps its line, with the
image under it. Images belong to the buffer: scrolling redraws nothing. A title too long for
the window gets a smaller font. A TODO keyword keeps its own colour (the one org.nvim gives
it in the buffer, e.g. its `todo_keyword_faces` face); the rest is in the headline's colour.

Headlines on consecutive lines become one image under the nearest visible line above them:
Neovim does not draw the virtual lines of a hidden line, and does not keep the order of
several images anchored at one line. With the cursor on one of them the group splits there
(the headlines after it hang under its visible line), so moving into a run of headlines
renders new PNGs once.

- The PNG is made by `scripts/org_heading_png.py` (Python 3 with Pillow: `py -3` on
  Windows, else `python3`), in the background; cached in `stdpath('cache')/org-headings`
  by text, colours, size and window width (a new colorscheme makes new ones).
- The font: `vim.g.pure_org_heading_font` (a `.ttf` path), or the first
  `JetBrainsMono*-Bold.ttf` among the system / user fonts. The cell shape is taken from
  that font's metrics, so use the bold face of the GUI's own font.
- Missing Python, Pillow or font: one warning, and the headlines stay as text.

`<leader>tm` turns the rendering on and off; `<leader>tM` turns the big headlines (OSC 66 / DECDHL) on or off,
off by default (saved as `big_headings`; they show only while the rendering is on).
`require('pure.render-org').set_level('full'|'off')` sets the rendering directly.

Tested in Kitsu (kitty for Windows) on the right monitor, with the real config, on a copy of the
vault's garden notes: scrolling by lines and pages, fast `Ctrl-D/U/E/Y`, folds, inserting, toggling.
What that found and fixed (the same engine draws the Markdown headings):

- **Scrolling through the rows a block reserves** (Neovim's `topfill`, or `skipcol` in a wrapped
  line) moves the screen without changing `topline`; the old blocks stayed where they were and
  new ones were drawn beside them (the same heading three times, a stray letter). Now both are part
  of the key that clears the blocks, and while the scroll is not on a whole line nothing is drawn and
  the raw headline shows (the big one comes back when it settles): Neovim's rows for the lines are
  not the ones on the screen in that state.
- A code block's label left a hole in the shading; a link line showed a blank row under it (an
  inline virtual text is counted on top of the raw width); big headlines showed the `*bold*` marks
  and the link syntax of their text.

## Coloured highlights (`<leader>H`, `lua/pure/highlights.lua`)

A highlight marks a word or a phrase with a colour behind it. It is an org link of its own type,
so it is saved in the note and comes back when the note is opened again (Emacs keeps it as a link):

```org
#+HL: idea #7d82d9 doubt #F99957
#+HL: #92a593

A [[hl:idea][phrase to remember]], a [[hl:yellow][word]] and [[hl:#92a593][any colour]].
```

- The render hides the brackets and the target as for any link; the text gets the colour behind it,
  with black or white text on top by brightness (with the render on or off).
- The palette: `yellow green blue pink orange purple` (the Ethereal colours; `vim.g.pure_highlights`,
  a list of `{ name, '#rrggbb' }`, replaces them), plus the note's own `#+HL:` lines, anywhere in the
  note. A name before a hex code names it; a bare hex code is its own name; a note's name replaces a
  default of the same name. Changing a colour in `#+HL:` recolours every highlight of that name.
  A name the palette does not know is drawn with `Search` (group `PureHighlightUnknown`).
- `<leader>H` in normal mode highlights the word under the cursor, in visual mode the selection (one
  line; `V` takes the line without its indent). A list asks the colour: the note's, the defaults, or
  "other colour" (type a hex code). On a highlight it changes the colour or removes it (the text stays).
- A highlight cannot go over a link (org has no link inside a link) nor hold `[[` / `]]`.
- `<CR>` on a highlight tells its colour. HTML export writes `<mark style="background-color:...">`,
  the other backends the plain text (org.nvim `links.types.hl`).
- `<leader>h` (the word highlight of the search, `<leader>th`) is not this.

## Pasted links get their name (`lua/pure/urltitle.lua`)

Paste a bare `http(s)` URL into an org or markdown note (a terminal paste: Ctrl+V, Win+V, middle
button) and it becomes a link at once, called by the site's name, then by the page's title as soon as
`curl` has fetched it, in the background (the text you keep typing is not disturbed):

| In | You paste | At once | A moment later |
|---|---|---|---|
| org | `https://www.youtube.com/watch?v=3ZeKWrs6VBM` | `[[https://www.youtube.com/watch?v=3ZeKWrs6VBM][youtube.com]]` | `[[...][Bro drew for 1000 hours]]` |
| markdown | `https://example.com/` | `[example.com](https://example.com/)` | `[Example Domain](https://example.com/)` |

The title is the page's `og:title`, else its `<title>`; for YouTube the video's name (oEmbed). A page
that does not answer, or has no title, keeps the site's name. Brackets in a title become parentheses,
a title is cut at 120 characters.

Left alone: a paste of anything but one URL (text, several lines), a paste inside a link (`[[...` in
org, the `(...)` of `](...)` in markdown), other file types (`.txt` has no link syntax: the URL stays),
a long paste that arrives in pieces, Visual and Command-line mode, and `p` of a register (only the
terminal's paste is a paste). The paste makes one request to the pasted address, the one opening the
link would make. `vim.g.pure_url_titles = false` (`configs/configs.lua`, on by default) pastes the URL
as it is.

## Vault keys (`<leader>v`, `lua/pure/vault.lua`)

The group of the old Markdown vault now works on the org vault, like Doom's `SPC v`:
find a node (`f`), a file (`F`), grep (`g`), quick capture (`q`: the template
menu, a new seed is its `n`), grow the idea (`n`) and compost it (`c`) as Doom does,
new note (`N`), insert a link (`i`), backlinks (`b`), rename (`r`),
delete to `archive/trash/` (`d`), journal line (`j`), today (`J`), explore (`e`),
save and commit (`s`), preview the linked note (`p`, in org notes). Until
2026-11-08 the capture menu was `t`, `n` was a new seed and `q` the quick edit of
the linked note (removed). The list is in [keymaps.md](keymaps.md). Links are by `:ID:`, so renaming
or moving a note breaks none. The Markdown vault's functions are left in
`pure/zettelkasten.lua` and `pure/notes.lua` as commands, without keys.

## Links between notes (`[[`, `<leader>vi`, `lua/pure/links.lua`)

A port of the Emacs side (`link-complete.el` and `aliases.el` in the Doom config). In an org note,
typing `[[` opens Neovim's own completion menu (the `completefunc` of the buffer; Tab / S-Tab or
`<C-n>` / `<C-p>` move, Enter takes the highlighted item, the first is highlighted at once, Esc closes
it) with the notes, the aliases and the headings (levels 1-2) of the vault, filtered as you type
(words in any order, accents and case ignored; better matches first, notes before headings, the
newer first). Taking one replaces `[[foo` by `[[id:ID][Title]]` (the render shows only the title):
the target gets its `:ID:` now when it had none, in the file or in the heading, through org.nvim's
`org.id`, and the file is written (the buffer you are in, or one with unsaved changes, is left
modified).

| You type | What you get |
|---|---|
| `[[foo` | notes, aliases and headings called like foo; the last item, `+ New note: foo`, makes a `SEED` called foo in `inbox.org` and links to it |
| `[[*foo` or `[[#foo` | only headings |
| `[[note*foo`, `[[note#foo`, `[[note:foo` | only the headings of the notes whose name has "note" |
| `[[foo\|\|short` | the link reads "short" and the alias is saved in the note (`:ROAM_ALIASES: short`, also at a heading when it is a heading that is linked) |

After a note is taken the cursor stays **inside** the link, at the end of its text, so `]` goes out
past the `]]` (the pairs already skip it) and `*`, `#` or `:` there opens the headings of that note
(the separator has to be typed there: a colon that is already in a title does nothing); taking one
changes **only the id**, to the heading's, and completes what was typed (`[[id:HEADING-ID][Note#Heading]]`,
whichever of `# * :` was typed, which becomes `#`): the brackets, the text before the separator, an
`||alias` and whatever follows are left as they are, so no `]]` is added. It works the same on a link
that was already in the note: put the cursor in its text, type `#` and a few letters of the heading.
A typed link (`[[file:`, `[[https:`...) is not searched.

**How the alias works.** An alias is another name for the note you picked; it never makes a new note
(with `||` typed the menu has no `+ New note` item). The text of the link keeps what it is to and the alias
after `||`: `[[id:ID][Note#Heading||alias]]`. **Only the render shows the alias** (`alias`); the text stays
as written, so editing the note (the cursor on the link) shows `Note#Heading||alias`. The alias is also
added to the `:ROAM_ALIASES:` of the note (or of the heading), so from then on it is an entry of the menu
and of `<leader>vf` ("alias → Note"). Two ways:

1. **Pick the note, then type the alias inside the link.** Take the note from the menu (Enter, or Tab and
   then keep typing) and type `||alias` where the cursor is, inside the link: `[[id:ID][Title||alias]]`.
   When you leave it (Enter, Esc, a move out of the link, an idle moment) the alias is saved.
2. **Type it all, then Enter.** `[[note||alias` with the menu open (or typed faster than the menu follows).
   The text after `||` is not part of the search, and the link is written `[[id:ID][Title||alias]]`.

Only links this module has just written are read for a `||` when you leave them (an older link, whatever its
text, is never touched). **Following** a link that has a `||` (`<CR>`, `gx`) checks the alias in the note it
points to and adds it when it is not there; the link itself is left as written. (Your `<Esc>` with a menu
open only closes the menu; the second one leaves insert mode.) A title with a colon, a star or a
hash in it ("Emacs log: to do") is found as typed: the separator only asks for headings when the whole
text is not the name of a note; the same goes for a title with `||` in it.

**Writing the link by hand.** The menu only tells what exists; you can type the whole link, or edit the
text of one that is already there, and **the text decides where it goes**: on `:w` (and when a link is
followed, `<CR>` / `gx`) every link whose text has a `||`, or that has no id yet, is read: `[[nota li#bud||x]]`
or `[[id:OLD][Nota linkada#Budget||x]]` become `[[id:ID-OF-THAT-HEADING][Nota linkada#Budget||x]]` (words are
enough, as long as they name ONE note and ONE heading of it; the text is made canonical, the target gets its
`:ID:` and the alias its `:ROAM_ALIASES:`). A link that names nothing is left as it is and flagged (a warning
at the link). A link without `||` is only text with an id and is never reinterpreted. Links already checked
are not looked at again until their text changes. `vim.g.pure_links_reconcile = false` turns it off.

**Why it can fail.** The menu is the `omnifunc` of the buffer (this module answers for the `[[` and
hands every other question to org.nvim's own, which is what the 'autocomplete' of this configuration
asks as you type; before, org.nvim's menu opened on every `[[` and this one never did). With
`vim.g.pure_links_complete = false` (configs.lua) the menu is **off**, and then there is no `||`, no
id and no headings: `[[` is org.nvim's own completion. `<C-x><C-u>` after a `[[` still opens this menu by hand.
Enter takes the first item when none is highlighted (`noselect` leaves none), and is what it was
(a new line, a list item, org.nvim's table row, Copilot) anywhere else. Enter right after a typed
`[[note||alias`, before the menu has caught up with the last key (no menu on screen), writes the link
for the best match at once (or for a new note called as typed when nothing matches), so typing fast
does not lose the alias.

`<leader>vi` (normal mode) is the same list in the picker of `<leader>vf` (the same look and order)
and inserts the link at the cursor; a title that matches nothing makes a seed in the inbox and links
to it. Every `vim.ui.select` list (org.nvim's own pickers, code actions, templates...) is drawn in
that look too ([fuzzy.md](fuzzy.md)).

## Find (`<leader>vf`)

One picker for the whole vault, a port of Doom's `SPC v f` (`vault-open.el`), in
`lua/pure/vault.lua` (fzf, coloured). A note (a file, named by its `#+title`) reads
`Note name`; a heading (down to level 4) reads `Note name › Heading`, the heading in the
colour of its level; an alias (`:ROAM_ALIASES:`, of a note or a heading) reads
`Alias → Note name › Heading`, in italics. On the right, dim: the path and how long ago the
note was written. The name of a note weighs more than a word inside it: every note (and its aliases)
comes before any heading, the newest first, then the headings in the same order, and `archive/` last
of all, so with a typed name the note is above the headings that only hold it; any part of the name,
the path or an alias matches, words in any order. Enter opens the note at the heading; a
title that matches nothing makes a seed in `inbox.org`.

The colours (`pure/notecolors.lua`) follow the colorscheme; in Ethereal they are Doom's
exactly: note `#4f8a96`, alias `#c89dc1`, separators and path `#6d7db6`, headings the
level colours. It lists every note and heading, not only the ones with an `:ID:`
(org-roam's `roam_node_find` is still `<leader>mmf`).

## `lua/lsp/orgls.lua`: the org language server (in-process)

One file with the vault reading of `pure/vault.lua` and all of `pure/links.lua` (merged, code as it was), plus
a small language server that needs no executable: its config is returned to `configs/lspConfigs.lua`
(`'orgls'` is in its list), and it attaches to the org notes **inside the vault** only. Plan, steps and what was
copied and why: the vault's note `projects/setup/Org LSP.org`.

| What | How |
|---|---|
| `K` on a link | `textDocument/hover` (the `K` map falls through to `lsp.hover()` when it is not a web link): the note, or the section for a heading link, as an org block (properties drawer left out, 40 lines at most); a link that names nothing says so (`No single note or heading named "x"`, `No note or heading with the id ...`). Links read: `[[id:ID][text]]`, `[[Note]]`, `[[Note#Heading]]` (with or without `\|\|alias`), `[[file:path]]`; web links give nothing. The server reads the open buffers, so unsaved text shows. |
| Automatic hover | `configs/lspConfigs.lua`, for **every** attached server that has a hover (not only this one): once the cursor has rested `vim.g.lsp_auto_hover_delay` ms (default 500) the hover shows by itself, silent when there is nothing. A timer of its own, so `updatetime` is untouched. `vim.g.lsp_auto_hover = false` turns it off; `<leader>tk` toggles it (saved across restarts, `configs/functions.lua`). |
| `K` `K` | the second `K` while the hover of a link is open (`configs/functions.lua` followOrHover) opens the linked note itself in its place (`pure/vault.lua` editLinkedNote): the real buffer, editable (`:w` saves), drawn as org, at the heading (a link to the whole note lands on its `#+title` line, else its first heading, not in the properties drawer); `q` closes it (asking to save when changed). Elsewhere the second `K` enters the hover as before. |
| `<leader>vp` | unchanged: still `vault.preview`, not the LSP. |

The module has no side effects when loaded, so it can be required next to `pure.links`; the editor side that
`pure/links.lua` runs at load (the `[[` menu, alias saving) is `require('lsp.orgls')._module.setup()`, **not
called yet**: `pure.links` stays the one in use for it. Settings: `vim.g.orgls_vault` (the vault folder; the
personal default lives in one function, `vaultDir`), `vim.g.orgls_inbox`, `vim.g.orgls_new_keyword`.
Without `vim.g.orgls_vault` / `vim.g.orgls_inbox` it asks `pure/vault.lua`: `vault.dir('org')`,
`vault.inbox('org')`. The notes `<leader>o_` opens by name are the `notes` of the vault's entry in
`vim.g.pure_vaults` (`nursery` is where grow moves a sprout; `vault.note(name, 'org')`, `vault.nursery()`).
