# Documentation

What each part of this configuration does and how to use it, without reading
the code. Every "pure" module lives in `lua/pure/` and replaces a plugin with a
few hundred lines of Lua.

Inside Neovim: `<leader>fh` (help picker) lists every section of these pages
as `pure <page> › <section>`, next to Neovim's own help. Picking one opens the
page at that section.

When a module changes, update its page here in the same commit.

| Page | What it covers |
|---|---|
| [keymaps.md](keymaps.md) | Every mapping, by group (also shown live: press `<Space>` and wait) |
| [todoist.md](todoist.md) | Todoist: the editable task list, blocks in notes, sync into notes, archive |
| [zettelkasten.md](zettelkasten.md) | Obsidian vault, note templates, daily / weekly / monthly notes |
| [markdown.md](markdown.md) | How markdown is drawn: headings, tasks, tables, wikilinks, frontmatter, footnotes |
| [keyhint.md](keyhint.md) | The window that lists the keys after `<leader>` |
| [fuzzy.md](fuzzy.md) | The fzf pickers: files, grep, buffers, help, explorer, `vim.ui.select` |
| [git.md](git.md) | Git status buffer, commit, push, diff in the sign column |
| [editing.md](editing.md) | Surround, auto pairs, indent scope, folds, completion |
| [ui.md](ui.md) | Dashboard, statusline, tabline, notifications, terminal, themes |

## How the configuration loads

- `init.lua` requires **every** `.lua` file under `lua/`, in alphabetical order
  of path (`configs/…` before `lsp/…` before `plugins/…` before `pure/…`
  before `themes/…`). A file that fails to load is reported in one message
  after startup; the rest still load.
- `lua/configs/` – options (`configs.lua`), keymaps, autocommands, LSP
  servers, shared helper functions (`functions.lua`).
- `lua/lsp/` – one file per language server (`vim.lsp.config`). The list of
  enabled servers is in `configs/lspConfigs.lua`.
- `lua/plugins/` – the few third-party plugins (installed with `vim.pack`):
  treesitter, oil, obsidian.nvim, copilot.
- `lua/pure/` – the home-made modules documented here.
- `lua/themes/` – colorschemes; the chosen one is remembered across restarts
  (`vim.g.MY_THEME`, saved by Neovim in the ShaDa file).

The `windows` branch is `main` plus a Windows-only block in `init.lua` that
makes Neovim run shell commands through Git bash (the pickers need POSIX
pipes) and starts in the home folder when launched from a shortcut.

## Settings in one place

All of these are optional and set in `lua/configs/configs.lua` (or anywhere
before use).

| Setting | Default | Page |
|---|---|---|
| `vim.g.pure_vault` | asked on first start | [zettelkasten](zettelkasten.md) |
| `vim.g.pure_templates` | `'Templates'` | [zettelkasten](zettelkasten.md) |
| `vim.g.pure_templates_locale` | `'en'` | [zettelkasten](zettelkasten.md) |
| `vim.g.pure_todoist_confirm` | `'all'` | [todoist](todoist.md) |
| `vim.g.pure_todoist_archive` | off | [todoist](todoist.md) |
| `vim.g.pure_todoist_sync` | off (`{ interval = 10 }` in configs.lua) | [todoist](todoist.md) |
| `vim.g.pure_keyhint_delay` | `1000` ms | [keyhint](keyhint.md) |
| `vim.g.pure_keyhint_groups` | set in keymaps.lua | [keyhint](keyhint.md) |
| `vim.g.pure_keyhint_triggers` | `<leader>` in normal and visual | [keyhint](keyhint.md) |
| `vim.g.pure_keyhint` | on (`false` turns it off) | [keyhint](keyhint.md) |
| `vim.g.pure_fuzzy_ignore` | `{ '.git', '.obsidian' }` | [fuzzy](fuzzy.md) |
| `vim.g.pure_dashboard_scale` | `'auto'` | [ui](ui.md) |
| `vim.g.pure_terminal_shell` | nu, pwsh or powershell on Windows; `'shell'` elsewhere | [ui](ui.md) |
| `vim.b.pure_indentscope_disable` | off | [editing](editing.md) |

## What is stored outside the repository

Nothing personal is kept in the git repository. These live in Neovim's data
folder (`:echo stdpath('data')`: `~/.local/share/nvim`, or
`%LOCALAPPDATA%\nvim-data` on Windows):

| File | What |
|---|---|
| `todoist_token` | the Todoist API token (`:TodoistToken` writes it) |
| `todoist_no_prompt` | "never ask for the token" |
| `todoist_states.json` | Obsidian checkbox states ([~] [!] [>] [-]) kept for Todoist tasks |
| `obsidian_vault` | the vault folder (`:ZettelVault` writes it) |
| `obsidian_vault_no_prompt` | "never ask for the vault" |

Undo history is in `stdpath('state')/undo`.

## Commands

| Command | What |
|---|---|
| `:Todoist [filter]` | the editable task list ([todoist](todoist.md)) |
| `:TodoistSync` | write the tasks of every ```` ```todoist ```` block into its note now |
| `:TodoistRefresh` | reload the drawn blocks (when sync is off) |
| `:TodoistToken` | set the Todoist token (hidden input) |
| `:ZettelVault` | choose the Obsidian vault folder |
| `:Notifications` | history of messages |
| `:Oil [dir]` | file browser |
