local home = vim.uv.os_homedir():gsub("\\", "/") .. "/"
vim.pack.add {
  {
    src = "https://github.com/obsidian-nvim/obsidian.nvim",
    version = vim.version.range "*", -- use latest release, remove to use latest commit
  },
}

-- `home` above already ends in "/", so no leading slash here or the path
-- comes out with a doubled separator.
local vault = home .. "iCloudDrive/Documents/Obsidian/Atlas"

-- obsidian.nvim throws "At least one workspace is required!" when none of the
-- configured paths exist, which failed this whole module on any machine
-- without the vault. Skip the setup there instead.
if vim.fn.isdirectory(vault) == 0 then
  return
end

require("obsidian").setup {
  legacy_commands = false, -- this will be removed in 4.0.0
  -- pure/mdview.lua renders markdown; obsidian's own UI would draw a second
  -- set of checkboxes and bullets over it.
  ui = { enable = false },
  workspaces = {
    {
      name = "Atlas",
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
    end,
  },
}
