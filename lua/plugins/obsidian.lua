vim.pack.add {
  {
    src = "https://github.com/obsidian-nvim/obsidian.nvim",
    version = vim.version.range "*", -- use latest release, remove to use latest commit
  },
}

-- The vault comes from pure/zettelkasten.lua, which asks for it on a fresh
-- install and remembers the answer (or reads vim.g.pure_vault), so it is
-- configured in one place instead of hard-coded here.
local configured = nil

local function setup(vault)
  -- obsidian.nvim throws "At least one workspace is required!" when none of
  -- the configured paths exist, which failed this whole module on any machine
  -- without the vault. Skip the setup there instead.
  if not vault or vim.fn.isdirectory(vault) == 0 then return end
  if configured then
    if configured ~= vault then
      vim.notify('obsidian.nvim keeps using ' .. configured .. ' until Neovim restarts', vim.log.levels.WARN)
    end
    return
  end
  configured = vault

  require("obsidian").setup {
    legacy_commands = false, -- this will be removed in 4.0.0
    -- pure/mdview.lua renders markdown; obsidian's own UI would draw a second
    -- set of checkboxes and bullets over it.
    ui = { enable = false },
    -- <CR> on a checkbox cycled through five states ([ ] [~] [!] [>] [x]).
    -- Only [ ] and [x] are task items to markdown, so the other three showed as
    -- raw brackets; now it toggles like <leader>tx and the Todoist list do.
    checkbox = { order = { " ", "x" } },
    -- obsidian.nvim rewrote the frontmatter of every note saved in Neovim: it
    -- added id/aliases/tags and sorted all the keys, so a daily's type, date,
    -- week... came out alphabetical, and Templates/Daily.md saved here got a
    -- block of its own that it then copied into every daily. Notes keep the
    -- frontmatter that Obsidian and the templates give them.
    frontmatter = { enabled = false },
    -- Same folder pure/zettelkasten.lua expands templates from, so
    -- :Obsidian template finds them too.
    templates = { folder = vim.g.pure_templates or "Templates" },
    workspaces = {
      {
        name = vim.fs.basename(vault),
        path = vault,
      },
    },
    callbacks = {
      enter_note = function(note)
        -- Required lazily, inside the callback: at the top of this file it ran
        -- before vim.pack.add() had put the plugin on the runtimepath, so it
        -- failed with "module 'obsidian.actions' not found".
        local actions = require "obsidian.actions"
        local api = require "obsidian.api"

        -- K is already taken by LSP hover (configs/keymaps.lua). Because this
        -- mapping is buffer-local it only shadows K inside notes, so hover keeps
        -- working everywhere else -- and inside notes it is not lost either:
        -- smart_action returns "<CR>" when the cursor is on nothing it handles,
        -- which is the case where hover is what you actually wanted.
        --
        -- expr = true is mandatory: smart_action does not act, it *returns* the
        -- keys to feed back ("<cmd>Obsidian follow_link<cr>", "za", "<CR>", ...).
        -- Without it the mapping types that text into the note.
        --
        -- The plugin's own <CR> stays as it is; adding a key does not replace it,
        -- so nothing needs vim.keymap.del().
        -- The check is explicit rather than leaning on smart_action's own "<CR>"
        -- fallback: checkbox.create_new defaults to true, so smart_action answers
        -- toggle_checkbox for *any* line and hover would never be reached.
        vim.keymap.set("n", "K", function()
          if api.cursor_link() or api.cursor_tag() or api.cursor_checkbox() or api.cursor_heading() then
            return actions.smart_action()
          end
          return "<cmd>lua vim.lsp.buf.hover()<cr>"
        end, {
          buffer = true,
          expr = true,
          desc = "Obsidian Smart Action, falling back to LSP hover",
        })

        -- <CR> inside a ```todoist block opens its tasks (pure/todoist.lua);
        -- anywhere else it is obsidian's own smart action, as before.
        -- Not an expr mapping: opening a window is not allowed from one.
        vim.keymap.set("n", "<CR>", function()
          require("pure.todoist").enter(function()
            vim.api.nvim_feedkeys(vim.keycode(actions.smart_action()), "n", false)
          end)
        end, { buffer = true, desc = "Todoist block, else Obsidian Smart Action" })
      end,
    },
  }
end

setup(require('pure.zettelkasten').vaultPath())

-- Set up as soon as a vault is chosen at the startup question or with
-- :ZettelVault, without waiting for a restart.
vim.api.nvim_create_autocmd('User', {
  pattern = 'PureVaultChanged',
  callback = function(args) setup(args.data and args.data.vault) end,
})
