local M = {}

-- Using a table to store terminal instances, keyed by command.
-- Each entry will be { buf = buf_id, win = win_id }
local terminals = {}
local func = require('configs.functions')

-- init.lua points 'shell' at Git bash on Windows so the fuzzy pickers can run
-- POSIX pipelines ("ls | fzf"). :terminal reads that same option, which is why
-- this launcher started opening bash instead of a Windows shell. The
-- interactive terminal gets its own setting, so the pickers and the launcher no
-- longer have to agree on one shell.
--
-- Override with, for example:  vim.g.pure_terminal_shell = "cmd.exe"
local function interactiveShell()
  if vim.g.pure_terminal_shell and vim.g.pure_terminal_shell ~= '' then
    return vim.g.pure_terminal_shell
  end
  if vim.fn.has('win32') == 0 then
    return vim.o.shell
  end
  -- Nushell first: it is what wezterm.lua sets as default_prog, so the floating
  -- terminal matches the shell used everywhere else.
  for _, candidate in ipairs({ 'nu', 'pwsh', 'powershell' }) do
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
  return vim.o.shell
end

local function hideTerminal(cmd)
  local term = terminals[cmd]
  if term and term.win and vim.api.nvim_win_is_valid(term.win) then
    vim.api.nvim_win_close(term.win, true)
    term.win = nil
  end
end

function M.toggleTerminal(cmd, ratio)
  cmd = cmd or "default"
  ratio = ratio or 0.8

  local term = terminals[cmd]

  -- If the window for this terminal is open, close it.
  if term and term.win and vim.api.nvim_win_is_valid(term.win) then
    vim.api.nvim_win_close(term.win, true)
    term.win = nil
    return
  end

  -- If a valid buffer for this command exists, re-open it in a new window.
  if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    local buf = term.buf
    local win, _ = func.createWindow(" ", 0.8)
    vim.api.nvim_win_set_buf(win, buf)
    term.win = win
    vim.api.nvim_set_current_win(win)
    vim.cmd("startinsert") -- Re-enter terminal-insert mode.
    return
  end

  -- If we get here, create a new terminal from scratch.
  local cwd
  local current_buf_name = vim.api.nvim_buf_get_name(0)
  if current_buf_name ~= "" and vim.fn.filereadable(current_buf_name) == 1 and vim.bo.buftype == "" then
    cwd = vim.fn.expand("%:p:h")
  else
    cwd = vim.fn.getcwd()
  end

  -- Create a floating window, then switch to it.
  local new_win, _ = func.createWindow(" ", ratio)
  vim.api.nvim_set_current_win(new_win)

  -- Set the working directory for this window only, then open the terminal.
  local escaped_cwd = vim.fn.fnameescape(cwd)
  vim.cmd('lcd ' .. escaped_cwd)

  -- Run the terminal, which will inherit the window-local CWD.
  local final_cmd = "terminal"
  if cmd and cmd ~= "default" then
    final_cmd = final_cmd .. " " .. cmd
  end
  -- 'shell' has no buffer-local form, so swap it just around this one call.
  -- :terminal resolves it when the job starts, so restoring it immediately
  -- afterwards leaves the fuzzy pickers on bash. Only the bare interactive
  -- terminal is switched: an explicit command keeps running under 'shell',
  -- where shellcmdflag is already known to match.
  local saved_shell = vim.o.shell
  if cmd == "default" then
    vim.o.shell = interactiveShell()
  end
  vim.cmd(final_cmd)
  vim.o.shell = saved_shell

  vim.cmd('startinsert')

  -- The :terminal command created a new buffer, so we store it.
  local term_buf = vim.api.nvim_get_current_buf()
  terminals[cmd] = { buf = term_buf, win = new_win }

  -- Keys that close the floating terminal.
  --
  -- This buffer only had a normal-mode <Esc>, but startinsert above leaves you
  -- in terminal-insert mode, so <Esc> went straight to the shell and there was
  -- no configured way out at all. <Esc> alone cannot be taken over in terminal
  -- mode -- the shell and any TUI inside it need it -- so the terminal-mode
  -- binding is <Esc><Esc>.
  for mode, lhs in pairs({ t = '<Esc><Esc>', n = '<Esc>' }) do
    vim.keymap.set(mode, lhs, function() hideTerminal(cmd) end,
      { silent = true, buffer = term_buf, desc = "Hide floating terminal" })
  end
end

return M

