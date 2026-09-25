# Editing (`surround.lua`, `pairs.lua`, `indentscope.lua`, `folding.lua`)

## Surround (`lua/pure/surround.lua`)

| Key | Then type | Result |
|---|---|---|
| `s` (normal) | a character | surrounds the word under the cursor: `s(` → `(word)` |
| `s` (visual) | a character | surrounds the selection |
| `S` | a function name | `S` + `print` → `print(word)` (visual: the selection) |
| `ds` | a character | deletes the pair around the cursor: `ds"` |
| `cs` | old, new | changes the pair: `cs"'`, `cs[{` |

Characters: `(` `)` `p` → `( )` · `[` `]` `b` → `[ ]` · `{` `}` `c` → `{ }` ·
`<` `>` → `< >` · `"` `q` → `" "` · `'` · `` ` `` `t` → `` ` ` `` · any other
character surrounds with itself on both sides (`s*` → `*word*`). `ds` / `cs`
look on the current line.

## Auto pairs (`lua/pure/pairs.lua`)

In insert mode, `(` `[` `{` `<` `"` `'` `` ` `` add their closing half.
Typing the closer when it is already next to the cursor steps over it, and
`<BS>` between an empty pair deletes both. In normal mode, `dl` deletes the
character under the cursor and its pair.

## Indent scope (`lua/pure/indentscope.lua`)

A vertical line beside the indented block the cursor is in. Blank lines do
not end a block.

| Key | What |
|---|---|
| `ii` / `ai` | text object: the block / the block plus its borders (`if … end`) |
| `[i` / `]i` | jump to the line above / below the block |

Colour `PureIndentscopeSymbol`. Off in one buffer:
`vim.b.pure_indentscope_disable = true`.

## Folds (`lua/pure/folding.lua`)

Folds are made automatically: from treesitter when the language has a parser,
from indentation otherwise. Everything starts open. A closed fold shows its
first line and `… 󰁂 N linhas`.

| Key | What |
|---|---|
| `<leader>zz` | open / close the fold under the cursor |
| `<leader>za` | all folds: open everything if any is closed, else close all |
| `<leader>zf` (visual) | fold the selection by hand |
| `<leader>zd` | delete the manual fold under the cursor |
| `<leader>zr` | back to automatic folds (drops the manual ones) |

Folding by hand switches that window to manual folds: the automatic ones
stay, but stop following your edits until `<leader>zr`. Manual folds are
lost when the file is closed.

## Completion

Neovim's own completion as you type (`'autocomplete'`): where a language
server is attached, the menu comes from it alone; in prose (markdown, text,
git commits) and without a server, from the words in open buffers.

| Key (insert) | What |
|---|---|
| `<Tab>` / `<S-Tab>` | next / previous item, or jump in a snippet |
| `<CR>` | accept a Copilot suggestion (else a normal Enter) |
| `<Up>` / `<C-s>` | signature help |

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
