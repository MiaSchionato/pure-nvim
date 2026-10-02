# Editing (`surround.lua`, `pairs.lua`, `lists.lua`, `indentscope.lua`, `folding.lua`)

## Surround (`lua/pure/surround.lua`)

| Key | Then type | Result |
|---|---|---|
| `s` (normal) | a character | surrounds the word under the cursor: `s(` → `(word)` |
| `s` (visual) | a character | surrounds the selection |
| `S` | a function name | `S` + `print` → `print(word)` (visual: the selection) |
| `ds` | a character | deletes the pair around the cursor: `ds"` |
| `cs` | old, new | changes the pair: `cs"'`, `cs[{` |

Characters: `(` `)` `p` → `( )` · `[` `]` `b` → `[ ]` · `{` `}` `c` → `{ }` ·
`<` `>` → `< >` · `'` `q` → `' '` · `"` `dq` → `" "` · `` ` `` `t` → `` ` ` `` ·
any other character surrounds with itself on both sides (`s*` → `*word*`).

`d` before a key doubles the pair: `sdb` → `[[word]]` (a wikilink), `sdp` →
`((word))`, `sdc` → `{{word}}`; `dq` is the exception, the double quote. The
same keys work in `ds` and `cs`: `dsdb` removes `[[ ]]`, `csbdb` turns
`[word]` into `[[word]]`. `ds` / `cs` look on the current line.

## Auto pairs (`lua/pure/pairs.lua`)

In insert mode, `(` `[` `{` `<` `"` `'` `` ` `` add their closing half.
Typing the closer when it is already next to the cursor steps over it, and
`<BS>` between an empty pair deletes both. In normal mode, `dl` deletes the
character under the cursor and its pair.

When a completion already ends in closers, the ones added with the opener are
dropped: accepting a note after `[[` gives `[[Note]]`, not `[[Note]]]]`. Closers
that belong to something opened before the completion stay, so completing
`getcwd()` inside `print()` still ends in `print(getcwd())`.

## Lists (`lua/pure/lists.lua`)

In a markdown note a new line under a list item starts the next item, as in
Obsidian: `<CR>` in insert mode, and `o` / `O` in normal mode, repeat

- the same bullet (`-`, `*`, `+`);
- a checkbox, always unchecked (`- [x] done` → `- [ ] `);
- the next number (`3.` → `4.`; `O` keeps the same one);

with the same indentation, inside a quote or callout too (`> - item`).
`<CR>` in the middle of an item takes the rest of the line into the new one.
`<CR>` on an item with no text ends the list: an indented item moves one
level out, a top-level one loses its marker.

Right after the marker of an empty item (`- [ ] |`, `- |`), `Tab` makes it a
sub-item and `S-Tab` takes it one level back out. Nothing changes inside a
code block, on the marker itself, or on a line that is not a list item.

## Indent scope (`lua/pure/indentscope.lua`)

A vertical line beside the indented block the cursor is in. Blank lines do
not end a block.

| Key | What |
|---|---|
| `ii` / `ai` | text object: the block / the block plus its borders (`if … end`) |
| `[i` / `]i` | jump to the line above / below the block |

When the block changes only the lines that differ are redrawn, so the line
does not blink while typing.

Colour `PureIndentscopeSymbol`. Off in one buffer:
`vim.b.pure_indentscope_disable = true`.

## Folds (`lua/pure/folding.lua`)

Folds are made automatically: from treesitter when the language has a parser,
from indentation otherwise. Everything starts open. A closed fold shows its
first line and `… 󰁂 N lines`, in the theme's `Directory` colour with no
background (`Folded`).

| Key | What |
|---|---|
| `zz` / `<leader>zz` | open / close the fold that **starts** on this line (a line where none starts is left alone: `za` would close the fold around it, in a markdown list the whole section) |
| `zt` / `<leader>zt` | tasks: fold the done ones (`[x]`, `[-]`), to see what is left |
| `zT` / `<leader>zT` | tasks: fold the open ones, to see what was done |
| `<leader>za` | all folds: open everything if any is closed, else close all |
| `<leader>zf` (visual) | fold the selection by hand |
| `<leader>zd` | delete the manual fold under the cursor |
| `<leader>zr` | back to automatic folds (drops the manual ones) |

Folding by hand switches that window to manual folds: the automatic ones
stay, but stop following your edits until `<leader>zr`. Manual folds are
lost when the file is closed.

**Tasks** (`zt` / `zT`): each run of done (or open) tasks becomes one line,
`󰄲 2 done tasks`, taking along their sub-items and the text indented under
them; headings and other text stay. The same key again, or `<leader>zr`,
goes back to the usual folds, all open as before. Which states count as done:
`vim.g.pure_tasks_done` (default `'xX-'`). These replace Vim's own `zt` /
`zz` (scroll the line to the top / middle).

## Completion

Neovim's own completion as you type (`'autocomplete'`): where a language
server is attached, the menu comes from it alone; in prose (markdown, text,
git commits) and without a server, from the words in open buffers.

Nothing is selected until you pick; `<CR>` takes the suggestion.

| Key (insert) | What |
|---|---|
| `<Tab>` / `<S-Tab>` | menu open: next / previous suggestion. Else: step past the closing pairs right after the cursor (`[[a\|]]` → `[[a]]\|`), jump in a snippet, or a plain Tab. Right after an empty list item's marker: indent / outdent it (Lists, above). Tab never indents otherwise |
| `<CR>` | a Copilot suggestion on screen: accept it. Menu open: take the selected suggestion, or the first one (a word already complete just gets its new line). Else a new line (the next list item in notes) |
| `<Esc>` | menu open: close only the menu (a picked suggestion stays) and stay in insert mode; else leave insert mode |
| `<Up>` | signature help where a language server offers it; else up |
| `<C-s>` | signature help |

In visual mode `<Tab>` / `<S-Tab>` indent / outdent the selection and keep it
selected; in normal mode `>>` / `<<` indent.

`<leader>op` turns Copilot on and off.

## Text objects

| Object | Selects |
|---|---|
| `is` / `as` | inside / around `[ ]` |
| `ic` / `ac` | inside / around `{ }` |
| `iq` / `aq` | inside / around the nearest quotes of any kind |
| `i.` / `a.` | a sentence |
| `in` / `an` | the treesitter node: child / parent (visual: `[n` `]n` `[N` `]N` move between nodes) |
| `ii` / `ai` | indent scope (above) |
| `gc` | a comment |
