local M = {}
local func = require('configs.functions')
local terms = require('pure.terms')
local cache_dir = vim.fn.stdpath("cache") if vim.fn.isdirectory(cache_dir) == 0 then vim.fn.mkdir(cache_dir, "p") end

---@param opts table The options for fuzzy logic.
function M.fuzzyLogic(opts)
  local win,buf = func.createWindow(opts.title, opts.ratio)
  local temp = vim.fn.stdpath("cache") .. "/opts_run"
  vim.api.nvim_set_option_value('bufhidden', 'wipe', {buf = buf})
  vim.cmd(string.format("terminal %s > %s", opts.cmd, temp))

  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    callback = function()
      local data = ""

      if vim.fn.filereadable(temp) == 1 then
        local f = io.open(temp, "r")
        if f then
          local last_line = ""
          for line in f:lines() do
            last_line = line
          end
          f:close()
          os.remove(temp)
          data = last_line:gsub("%s+$", "")
        end
          os.remove(temp)
      end

      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end

        if data ~= "" or opts.isChooser then
          opts.callback(data)
        else
            vim.cmd("stopinsert")
        end
      end)
    end
    })
  vim.defer_fn(function()
    vim.cmd("startinsert")
  end, 50)
end

function M.fuzzySearch(path)
  if path == nil then path = "/Users/mia/" end
  local fd = "fd --hidden --type file . --strip-cwd-prefix --base-directory  "
  local fzf = "fzf --keep-right --tiebreak=end"

  M.fuzzyLogic({
    title = "Fuzzy Search",
    ratio = 0.6,
    cmd = string.format("%s %s | %s", fd, path, fzf),
    callback = function(selection)
      vim.cmd("edit! " .. vim.fn.fnameescape(path .. selection))
      vim.cmd("filetype detect")
    end

  })
end


function M.fuzzyGrep(path)
  local rg = "rg --column --line-number --no-heading --color=always --smart-case -- . "
  local fzf = "fzf --ansi --delimiter : --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' --preview-window 'up,60\\%,border-bottom,+{2}+3/3'"

  M.fuzzyLogic({
    title = "Fuzzy Grep",
    ratio = 0.8,
    cmd = string.format("%s %s | %s",rg,path,fzf),
    callback = function(selection)
      local full_path, line, col = selection:match("^([^:]+):(%d+):(%d+)")
      if full_path and line and col then
        vim.cmd("edit! " .. vim.fn.fnameescape(full_path))
        vim.api.nvim_win_set_cursor(0, {tonumber(line),tonumber(col)})
      end
      vim.cmd("filetype detect")
    end
  })
end

function M.fuzzyHelp()
  local doc_path = vim.fn.expand("$VIMRUNTIME/doc/")

  M.fuzzyLogic({
    title = "Fuzzy help",
    ratio = 0.6,
    cmd = string.format("ls %s | fzf", doc_path),
    callback = function (selection)
      vim.cmd("help " .. vim.fn.fnameescape(selection))
      vim.cmd("filetype detect")
    end
  })
end

function M.fuzzyGit()
  local path = vim.fn.expand("%:p:h")

  local fzf = "fzf --ansi --preview 'git show --color=always {1}' --preview-window 'up,60\\%,wrap,border-bottom'"
  local git = "git log --oneline --color=always "

  M.fuzzyLogic({
    title = "Fuzzy Git log",
    ratio = 0.8,
    cmd = string.format("cd %s && %s | %s",path, git, fzf),
    callback = function (selection)
      vim.cmd(string.format("edit %s", vim.fn.fnameescape(selection)))
    end
  })
end


function M.fuzzyGitGrep()
  local git_grep = "git grep --line-number --column"
  local fzf = "fzf --ansi --delimiter : --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' --preview-window 'up,60\\%,border-bottom,+{2}+3/3'"
  local path = vim.fn.expand("%:p:h")

  M.fuzzyLogic({
    title = "Fuzzy Git Grep",
    ratio = 0.8,
    cmd = string.format("cd %s && %s . | %s", path, git_grep, fzf),
    callback = function(selection)
      local full_path, line, col_str = selection:match("^([^:]+):(%d+):(%d+)")
      if not full_path then return end
      local col = tonumber(col_str)

      vim.cmd("edit! " .. vim.fn.fnameescape(full_path))
      if line and col then
        vim.api.nvim_win_set_cursor(0, {tonumber(line), col})
      end
      vim.cmd("filetype detect")
    end
  })
end

function M.fuzzyJump()
  -- Get table content
  local jumplist = vim.fn.getjumplist()
  local jumps = {}
    for _, jump in ipairs(jumplist[1]) do
      local path = vim.api.nvim_buf_get_name(jump.bufnr)
      if path ~= "" then
        table.insert(jumps,string.format("%s:%d:%d", path, jump.lnum, jump.col))
      end
    end

  -- Write to temp file
  local temp = vim.fn.stdpath("cache") .. "/Jump_list"
  local f = io.open(temp, "w")
  if f then
    f:write(table.concat(jumps, "\n"))
    f:close()
  end

  local fzf = "fzf --ansi --delimiter : --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' --preview-window 'up,60\\%,border-bottom,+{2}+3/3'"
  M.fuzzyLogic({
    title = "fuzzy jumps",
    ratio = 0.8,
    cmd = string.format("cat %s | %s", temp, fzf),
    callback = function (selection)
      os.remove(temp)
      local full_path, line, col = selection:match("^([^:]+):(%d+):(%d+)")
      vim.cmd("edit! " .. vim.fn.fnameescape(full_path))
      if full_path and line and col then
        vim.api.nvim_win_set_cursor(0, {tonumber(line),tonumber(col)})
        vim.cmd("filetype detect")
      end
    end
  })
end


function M.fuzzyBuffers()
  -- Get table contet
  local buffer_list = vim.api.nvim_list_bufs()
  local buffers = {}
  for _, bufnr in ipairs(buffer_list) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
      local full_path = vim.api.nvim_buf_get_name(bufnr)
      local short_path = vim.fn.fnamemodify(full_path, ":.")
      table.insert(buffers, short_path)
    end
  end

  -- Write to temp file
  local temp = vim.fn.stdpath("cache") .. "/buffer_list"
  local f = io.open(temp, "w")
  if f then
    f:write(table.concat(buffers, "\n"))
    f:close()
  end

  M.fuzzyLogic({
    title = "Fuzzy buffers",
    ratio = 0.7,
    cmd = string.format("cat %s | fzf --keep-right --tiebreak=end", temp),
    callback = function (selection)
        os.remove(temp)
        vim.cmd("edit " .. vim.fn.fnameescape(selection))
        vim.cmd("filetype detect")
    end
  })

end

function M.fuzzyOldfiles()
  -- Get table content
  local oldfiles = vim.tbl_filter(function (f)
    return vim.fn.filereadable(f) == 1
  end, vim.v.oldfiles)

  -- Write table content on temp file
  local temp = vim.fn.stdpath("cache") .. "/oldfiles_list"
  local f = io.open(temp, "w")
  if f then
    f:write(table.concat(oldfiles, "\n"))
    f:close()
  end

  -- Handle to the logic function
  M.fuzzyLogic({
      title = "Oldfiles",
      ratio = 0.7,
      cmd = string.format("cat %s | fzf",temp),
      callback = function(selection)
        os.remove(temp)
        vim.cmd("edit " .. vim.fn.fnameescape(selection))
        vim.cmd("filetype detect")
      end
    })

end

function M.fuzzyColorscheme()
  local schemes = vim.fn.getcompletion("", "color")
  local temp = vim.fn.stdpath("cache") .. "/colorscheme_list"
  local f = io.open(temp, "w")
  if f then
    f:write(table.concat(schemes, "\n"))
    f:close()
  end

  -- Handle to the logic function
  M.fuzzyLogic({
      title = "Fuzzy Search",
      ratio = 0.7,
      cmd = string.format("cat %s | fzf",temp),
      callback = function(theme)
        os.remove(temp)
        vim.cmd("colorscheme "  .. vim.fn.fnameescape(theme))
        vim.g.MY_THEME = theme
        if vim.g.neovide then
          vim.api.nvim_set_hl(0,'Normal', { bg = "#060b1e" })
        end
      end
    })
end

function M.setup()
  vim.ui.select = function(items, opts, selected)
    opts = opts or {}
    if #items == 0 then
      selected(nil, nil)
      return
    end

    local choices = {}
    for i, item in ipairs(items) do -- Check if table or plain text
      if opts.format_item then
        choices[i] = opts.format_item(item)
      else
        choices[i] = tostring(item)
      end
    end

    local temp = vim.fn.stdpath("cache") .. "/ui_select"
    local f = io.open(temp, "w")
    if not f then
      vim.notify('Error creating temp file', 4)
      return
    end
    f:write(table.concat(choices, "\n"))
    f:close()

    M.fuzzyLogic({
      title = opts.prompt or "Select",
      ratio = 0.7,
      cmd = string.format("cat %s | fzf", temp),
      callback = function(selection)
        os.remove(temp)
        if selection and selection ~= "" then
          local selected_idx
          for i, choice in ipairs(choices) do
            if choice == selection then
              selected_idx = i
              break
            end
          end
          if selected_idx then
            selected(items[selected_idx], selected_idx)
          else
            selected(nil, nil)
          end
        else
          selected(nil, nil)
        end
      end
    })
  end

  vim.ui.input = function(opts, callback)
    opts = opts or {}
    local prompt = opts.prompt or "Input: "
    local win, buf = func.createWindow(prompt, 0.8)
    vim.api.nvim_win_set_height(win, 1)

    if opts.default then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {opts.default})
      vim.cmd("startinsert!")
    end

    local confirmed = false

    local function submit()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      confirmed = true
      local input = table.concat(lines, "\n")
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
      callback(input)
    end

    local function cancel()
      confirmed = false
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
      callback(nil)
    end

    local opts_map = {noremap = true, silent = true, nowait = true, buffer = buf}
    vim.keymap.set('i', '<CR>', submit, opts_map)
    vim.keymap.set('n', '<CR>', submit, opts_map)

    vim.keymap.set('n', 'q', cancel, opts_map)
    vim.keymap.set('n', '<Esc>', cancel, opts_map)

    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      callback = function()
        if not confirmed then
          callback(nil)
        end
      end
    })


    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
            if opts.default then
                vim.cmd("startinsert!")
            else
                vim.cmd("startinsert")
            end
        end
    end, 10)
  end
end

function M.NewFile(path)
  local fd = "fd --hidden --type directory . --strip-cwd-prefix --base-directory  "
  local fzf = "fzf --keep-right --tiebreak=end"
  M.fuzzyLogic({
    title = "Select New File Path",
    ratio = 0.6,
    cmd = string.format("%s %s | %s", fd, path, fzf),
    callback = function(selection)
      vim.ui.input({prompt = "New file name: "}, function(input)
        if input and input ~= "" then
          vim.cmd("edit! " .. vim.fn.fnameescape(path .. selection .. "/" .. input))
        else
          vim.cmd("edit! " .. vim.fn.fnameescape(path .. selection).. "Untitled")
        end
      end)
    end
  })
end

function M.CompilerCommand()
  vim.ui.input({prompt = "Compiler Command:"}, function(input)
    if input and input ~= "" then
      terms.toggleTerminal(input, 0.6)
    end
  end)
end

---@param path string|nil The directory path to explore. If nil, uses current working directory.
function M.fuzzyExplorer(path)
  if path == nil then path = vim.fn.getcwd() end

  -- Use ls -ap to show hidden files and classify with indicators (/ for dirs)
  local list_cmd = "ls -ap --color=always"

  -- Preview command for fzf. It's executed in `path` directory.
  -- Added --line-range to bat to avoid lagging on large files.
  local preview_cmd = "if [ -d {} ]; ls -apF --color=always {}; else bat --color=always --style=numbers --line-range :500 {}; end"
  local fzf_cmd = string.format("fzf --ansi --preview='%s' --print-query", preview_cmd)

  M.fuzzyLogic({
    title = "Explorer: " .. path,
    ratio = 0.8,
    cmd = string.format("cd %s && %s | %s", vim.fn.shellescape(path), list_cmd, fzf_cmd),
          callback = function(selection)
            if not selection or selection == "" or selection == "./" then
              return -- Do nothing
            end
    
            local new_path = vim.fn.resolve(path .. "/" .. selection)
    
            if selection:sub(-1) == '/' then
              -- User intends to create/enter a directory
              if vim.fn.isdirectory(new_path) == 0 then
                -- Directory doesn't exist, create it
                vim.fn.mkdir(new_path, "p")
              end
              -- Enter the directory
              M.fuzzyExplorer(new_path)
            else
              -- User intends to open/create a file
              if vim.fn.isdirectory(new_path) == 1 then
                -- It's an existing directory, but no trailing slash was typed
                -- so we enter it instead of trying to edit it as a file.
                M.fuzzyExplorer(new_path)
              else
                -- It's a file (new or existing)
                vim.cmd("edit! " .. vim.fn.fnameescape(new_path))
              end
            end
          end  })
end

function M.yaziExplorer(path)
  if path == nil then path = vim.fn.getcwd() end
  local temp = vim.fn.stdpath("cache") .. "/yazi_explorer"
  local yazi = "yazi --chooser-file " .. temp

  M.fuzzyLogic({
    title = "Yazi: " .. path,
    ratio = 0.8,
    cmd = string.format("%s", yazi),
    isChooser = true,
    callback = function()
        local f = io.open(temp, "r")
        if f and vim.fn.filereadable(temp) then
          local content = f:read("*a")
          f:close()
          vim.cmd("edit! " .. vim.fn.fnameescape(content))
          os.remove(temp)
        else
          vim.notify("No file selected", vim.log.levels.WARN)
        end
      end
    })
end

return M

