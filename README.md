# My Neovim Configuration

This repository contains my personal and highly opinionated Neovim configuration. I believe that in the modern Neovim ecosystem, plugins and configurations are closely intertwined. This has inspired me to create my own set of configurations, tailored to my specific needs and preferences.

This repository is not intended for public use, but rather as a personal project. However, feel free to copy, modify, or use any part of this configuration at your own risk. I am always open to suggestions and ideas for improvement.

## Goals

My primary goal with this project is to learn programming through a hands-on approach. I believe that fine-tuning my own text editor, the programmer's essential tool, is an excellent way to learn. By customizing my editor, I not only learn how to code but also gain a deeper understanding of my own development environment.

My second, equally important goal, is to port my existing minimalist Neovim configuration and thoroughly refactor it. This involves a deliberate effort to eliminate any "bloatware" – unnecessary features or dependencies often introduced by larger plugins – and to streamline the configuration to precisely fit my workflow and preferences. The aim is to create an efficient, lean, and highly performant editor setup that enhances my productivity without compromising on functionality. This process allows me to deeply understand each component of my editor and ensure that every line of configuration serves a specific, well-defined purpose.
 
 
 

## Requirements

Plugins are installed by the built-in `vim.pack`, so **Neovim 0.12 or newer** is required (tested with 0.12.5). Everything below is an external program the config calls; each one is optional in the sense that the config starts without it, but the feature listed next to it will not work.

### Core tools

| Tool | Used by |
| --- | --- |
| `git` | `vim.pack` (plugin install and updates), the Git log / Git grep pickers |
| `fzf` | every fuzzy picker (`lua/pure/fuzzyUtils.lua`) |
| `fd` | file and directory pickers |
| `rg` (ripgrep) | live grep picker |
| `bat` | previews in the grep and explorer pickers |
| `tree-sitter` CLI + a C compiler | compiling Treesitter parsers (`npm install -g tree-sitter-cli`) |
| `node` | GitHub Copilot (`copilot.vim`) |
| `curl` | Todoist task list (`:Todoist`) |

On Debian/Ubuntu the `fd` and `bat` packages install the binaries as `fdfind` and `batcat`; link them to `fd` and `bat` so the pickers can find them.

### Language servers

A server is enabled only when its executable is found on `PATH` (`lua/configs/lspConfigs.lua`), so install just the ones you need.

| Server | Languages | Install |
| --- | --- | --- |
| `lua-language-server` | Lua | [release binaries](https://github.com/LuaLS/lua-language-server/releases) |
| `gopls` | Go | `go install golang.org/x/tools/gopls@latest` |
| `clangd` | C / C++ | LLVM / distro package |
| `csharp-ls` | C# | `dotnet tool install --global csharp-ls` (needs the .NET SDK) |
| `marksman` | Markdown | [release binaries](https://github.com/artempyanykh/marksman/releases) |
| `markdown-oxide` | Markdown (notes) | [release binaries](https://github.com/Feel-ix-343/markdown-oxide/releases) |
| `simple-completion-language-server` | buffer words and snippets | `cargo install --git https://github.com/estin/simple-completion-language-server` |

### Treesitter parsers

On startup the config installs any missing parser for: c, cpp, c_sharp, lua, json, vim, vimdoc, query, markdown, markdown_inline, go, bash, dockerfile and python. This needs the `tree-sitter` CLI and a C compiler on `PATH`; without them only the parsers bundled with Neovim work.

### Windows

The `windows` branch adds the Windows-only setup on top of `main`. The pickers build POSIX pipelines, so Git for Windows (Git bash) is needed there, and the floating terminal prefers `nu`, then `pwsh`, then `powershell`.

### Obsidian

`lua/plugins/obsidian.lua` expects the vault at `~/iCloudDrive/Documents/Obsidian/Atlas` and skips its setup when that folder does not exist. Change the path to match your own vault.

### Todoist

`:Todoist` lists your active tasks as a checkbox table (`:Todoist today`, `:Todoist overdue` or any other Todoist filter narrows it); `<CR>` or `x` completes the task under the cursor, `r` reloads and `q` closes. It needs an API token from Todoist (Settings → Integrations → Developer). When none is found Neovim asks for it on startup (with a "don't ask again" option); `:TodoistToken` sets or replaces it any time, with hidden input, and checks it against the API. It is stored in `stdpath('data')/todoist_token`, outside this repository; a `TODOIST_API_TOKEN` environment variable takes precedence. Avoid typing the token into a shell, whose history may be versioned.
