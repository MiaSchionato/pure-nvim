# Markdown (`lua/pure/mdview.lua`, `lua/pure/render-md.lua`)

Markdown is drawn in place, like render-markdown.nvim: **the file is never
changed**, marks are drawn over the text. Treesitter says what each piece is,
so a `-` inside a code block is never taken for a bullet.

`<leader>om` turns the drawing on and off.

## What is drawn

| In the file | On screen |
|---|---|
| `# Heading` | icon instead of the `#`s and a coloured band (colour from the theme) |
| `- item` | bullet per level: • ◦ ▪ ▫ (`vim.g.pure_md_bullets`); a sub-item keeps its indentation |
| `- [ ]` / `- [x]` | checkbox icons; done items dimmed |
| `- [~]` `[!]` `[>]` `[-]` | Obsidian's extra states: in progress (blue), important (red), deferred (purple), cancelled (grey) – fixed colours in every theme |
| `> quote` | a bar instead of `>` |
| `---` | a full-width line |
| tables | box-drawing borders; checkboxes inside cells too |
| ```` ```lua ```` | shaded block, the language as a label |
| `` `code` `` | shaded background |
| `[[path/note\|Text]]` | only **Text** |
| `[[note#Section]]` | **note > Section** |
| `![[image.png]]` / `![[Note]]` | an image or file icon and the name |
| `[text](url)` | only **text** (Neovim itself hides the URL) |
| `text[^1]` | text¹ – footnote references as superscripts |
| `[^1]: …` | hidden – footnote definitions |
| frontmatter (`---` block at the top) | hidden |
| ```` ```todoist ```` query | hidden (see [todoist.md](todoist.md)) |

## Editing what is drawn

- In **insert and visual** mode the line under the cursor shows the raw
  markdown.
- In normal mode it stays drawn, except:
  - a **wikilink** shows raw while the cursor is inside it (as in Obsidian's
    live preview), so it can be edited and followed with `<CR>`;
  - **hidden lines** (frontmatter, footnotes, todoist queries) come back while
    the cursor is on them: `gg` shows the frontmatter.
- A note opens just below its frontmatter.
- Typing redraws as little as it can: an edit that stays on one line redraws
  only that line, and while typing in insert mode (that line is raw) nothing
  is redrawn. A line that can change others (a ```` ``` ```` fence, `---`,
  `<!--`, a footnote definition), adding or removing lines, scrolling or
  changing mode redraws the screen.

## Other markdown settings (`render-md.lua`)

For every markdown buffer: `textwidth` 110, spell checking in the languages
whose word lists are installed (pt_br, en, it; `vim.g.pure_spelllang`),
suggestions ranked across them, conceal on.

The automatic line break while typing never splits a `[[wikilink]]` (a link
over two lines is no link, in Obsidian either): the line breaks before the
link instead, and a link too long for that stays whole on a longer line.
`gq` is Vim's own formatting.

Treesitter parses markdown synchronously (`vim.g._ts_force_sync_parsing`,
only while a markdown buffer is current): parsing in the background, as
Neovim does once a parse takes over 3 ms, let `**bold**` and `` `code` ``
flash back to their raw marks for one key while typing.

| Key (markdown only) | What |
|---|---|
| `<leader>tx` | tick / untick the checkbox on the line |
| `<leader>x` | cycle `[ ] [~] [!] [>] [-] [x]` (notes only, not the Todoist list) |
| `<leader>ft` | format the table around the cursor (`column -t`) |
| `<C-l>` (insert) | fix the last misspelled word before the cursor, on this line, with the first suggestion; the cursor stays; `u` undoes just the fix |
| `<leader>ds` | spelling suggestions (`z=`) |
| `<leader>dg` / `<leader>dw` | mark word good / wrong |
| `<leader>dp` / `<leader>dn` | previous / next misspelled word |

## Colours

Groups link to what every theme has, so they follow the colorscheme; set them
yourself to override: `PureMdH1`…`PureMdH6` (heading text), `PureMdH1Bg`…
(bands, computed), `PureMdCode`, `PureMdInlineCode`, `PureMdBullet`,
`PureMdQuote`, `PureMdRule`, `PureMdTable`, `PureMdLink`, `PureMdFootnote`.
The checkbox colours `PureMdTask*` are fixed on purpose.

A buffer that is not a file (a scratch buffer) is drawn only if it sets
`vim.b.pure_mdview = true`, as the Todoist list does.
