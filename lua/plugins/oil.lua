vim.pack.add({
  { src = 'https://github.com/stevearc/oil.nvim', name = 'oil' }
})
require('oil').setup({
  
  -- No 'icon' column: it needs mini.icons or nvim-web-devicons, and neither
  -- is installed. Directories still stand out by colour and trailing '/'.
  columns = {
    'permissions',
    'size',
    'mtime',
  },
  prompt_save_on_select_new_entry = false,
  skip_confirm_for_simple_edits = true,

  keymaps = {
    ["g?"] = "actions.show_help",
    ["<CR>"] = "actions.select",
    ["H"] = "actions.parent",
    ["L"] = "actions.select",
    -- The key that opened the float (<leader>ee, <leader>eo, ...) closes it
    -- too; that is handled by the global mappings, which toggle.
    ["<Esc>"] = "actions.close",
    ["q"] = "actions.close",
    ["P"] = "actions.preview",
    ["R"] = "actions.refresh",
  },
  view_options = {
    show_hidden = true,
     highlight_filename = function(entry, is_hidden, is_link_target, is_link_orphan)
       if entry.type == 'directory' then
         return "Directory"
       end

       if entry.type == 'file' then
         return "String"
       end

       if entry.type == 'executable' then
         return "Function"
       end 

       if entry.type == 'symlink' then
         return "Constant"
       end

       if is_hidden then
         return "Comment"
       end

       if is_link_target then
         return "String"
       end

       if is_link_orphan then
         return "Error"
       end
     end,
   },
})
-- Under explore (<leader>e) rather than <leader>ot, which is the tabline toggle
-- in the <leader>o toggles group. The same key closes the float from inside.
vim.keymap.set('n', '<leader>eo', require("oil").toggle_float, {silent = true,desc = "Oil Float" })
