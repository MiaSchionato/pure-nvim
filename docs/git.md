# Git (`lua/pure/git.lua`, `configs/functions.lua`)

Everyday git without plugins. Every command runs in the repository of the
**current file** (so it works on the vault, the config, any project) and
reports the result as a notification.

| Key | What |
|---|---|
| `<leader>gs` | **status buffer** (below) |
| `<leader>ga` / `<leader>gA` | stage the current file / everything |
| `<leader>gu` | unstage the current file |
| `<leader>gr` | discard the changes to the current file (asks first: they are gone for good) |
| `<leader>gc` | commit what is staged (asks for the message) |
| `<leader>gp` / `<leader>gP` | push / pull – **the branch you are on** |
| `<leader>gb` | who last changed the cursor line, when, in which commit |
| `<leader>gB` | pick a local branch and switch to it |
| `<leader>gl` | log picker; `Enter` shows the commit |
| `<leader>gg` | grep in the repository's files |
| `<leader>gd` | toggle the diff of the current file in the buffer: `+` in the sign column for added lines, removed lines shown in red above where they were |

Before a push, check the branch: `:!git branch --show-current`.

## Status buffer (`<leader>gs`)

Lists staged, unstaged and untracked files. Keys act on the file under the
cursor:

| Key | What |
|---|---|
| `a` | stage |
| `u` | unstage |
| `r` | discard changes (asks first) |
| `d` | diff in a split (staged or working changes; an untracked file whole) |
| `<CR>` | open the file |
| `c` | commit |
| `p` | push |
| `R` | refresh |
| `q` / `<Esc>` | close |

Buffers whose files git changed (discard, pull, switch) are reloaded.
