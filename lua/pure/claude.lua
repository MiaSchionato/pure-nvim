-- =============================================================================
--  Claude
-- =============================================================================
--  Claude Code (the `claude` command, installed and logged in) driven from
--  keys, not a chat. Every request goes with its context: the file, where
--  the cursor is, the selection and the LSP diagnostics.
--
--    <leader>ai   write: what Claude answers goes straight into the buffer,
--                 below the cursor line (or in place of a blank line); in
--                 visual mode it replaces the selection. The text is shown
--                 dimmed while it is written, then becomes real text: one
--                 `u` takes it back.
--    <leader>aa   ask: the answer shows in a floating window (markdown).
--                 In it: a asks a follow-up, y copies the answer, q closes.
--    <leader>ac   review the code (or the selection) in the window.
--    <leader>ar   the last request again, with the current context.
--    <leader>ah   past answers.
--    <leader>as   stop what is running.
--    <leader>ab   run the ```claude block under the cursor again.
--
--  Blocks: a note can hold a request that runs on its own, and whose answer
--  is written into the note under it, between two markers:
--
--    ```claude
--    Summarize yesterday's daily and list the tasks left open.
--    ```
--    <!-- claude -->
--    ...the answer...
--    <!-- /claude -->
--
--  It runs when the note is shown and has no answer yet (so, put in the
--  daily template, once per daily). Options go first, as `key: value` lines:
--
--    when: sunday   not before that weekday (of the note's week, for a
--                   weekly note named like 2026-W39)
--    run: manual    only with <leader>ab
--
--  Never in the templates or the trash, and a note named after a date runs
--  only in its own period (a daily on its day, a weekly in its week or the
--  week after, a monthly in its month or the month after). For these
--  requests Claude can read the vault (Read, Grep, Glob), never write to it.
--
--    vim.g.pure_claude_model = nil     the claude command's default model
--    vim.g.pure_claude_cmd = 'claude'  the command
--    vim.g.pure_claude_blocks = true   false: blocks run only with <leader>ab
-- =============================================================================

local M = {}

local ns = vim.api.nvim_create_namespace('pure_claude')
local READ_TOOLS = { 'Read', 'Grep', 'Glob' }

local history = {} -- { kind, question, answer, session, time }, newest last
local running = {} -- id -> vim.SystemObj
local last        -- the last request: { kind, instruction, visual }

-- -----------------------------------------------------------------------------
--  Running claude
-- -----------------------------------------------------------------------------

--- The claude executable with `args`, or nil when it is not installed.
local function command(args)
  local exe = vim.fn.exepath(vim.g.pure_claude_cmd or 'claude')
  if exe == '' then return nil end
  -- npm installs a .cmd on Windows, which only cmd.exe runs. The prompt
  -- goes on stdin, so only these fixed flags pass through cmd.exe.
  if vim.fn.has('win32') == 1 and (exe:lower():match('%.cmd$') or exe:lower():match('%.bat$')) then
    return vim.list_extend({ 'cmd.exe', '/c', exe }, args)
  end
  return vim.list_extend({ exe }, args)
end

--- Run one request. `opts`: prompt, tools (list), cwd, resume (session id),
--- keep (keep the session, to follow up), on_text(chunk), on_tool(name),
--- on_done(err, text, session). Callbacks run on the main loop. Returns a
--- function that stops it.
local function run(opts)
  local tools = table.concat(opts.tools or {}, ',')
  local args = { '-p', '--output-format', 'stream-json', '--verbose', '--include-partial-messages',
    '--tools', tools }
  if tools ~= '' then vim.list_extend(args, { '--allowedTools', tools }) end
  if vim.g.pure_claude_model then vim.list_extend(args, { '--model', vim.g.pure_claude_model }) end
  if opts.resume then vim.list_extend(args, { '--resume', opts.resume }) end
  if not (opts.keep or opts.resume) then table.insert(args, '--no-session-persistence') end

  local cmd = command(args)
  if not cmd then
    vim.schedule(function()
      opts.on_done('Claude Code is not installed: `claude` is not in the PATH'
        .. ' (https://claude.com/claude-code), or set vim.g.pure_claude_cmd')
    end)
    return function() end
  end

  local pending, text, session, result, err_text = '', {}, nil, nil, {}
  local finished = false
  local function event(line)
    local ok, ev = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
    if not ok or type(ev) ~= 'table' then return end
    session = ev.session_id or session
    if ev.type == 'stream_event' and ev.event then
      local e = ev.event
      -- Only the answer's own text: not what goes on around a tool call.
      if e.type == 'content_block_delta' and e.delta and e.delta.type == 'text_delta' and not ev.parent_tool_use_id then
        table.insert(text, e.delta.text)
        if opts.on_text then opts.on_text(e.delta.text) end
      elseif e.type == 'content_block_start' and e.content_block and e.content_block.type == 'tool_use' then
        if opts.on_tool then opts.on_tool(e.content_block.name) end
      elseif e.type == 'message_start' and #text > 0 then
        -- A new turn after a tool call: keep its text apart from the last.
        table.insert(text, '\n\n')
        if opts.on_text then opts.on_text('\n\n') end
      end
    elseif ev.type == 'result' then
      result = ev
    end
  end

  local id = tostring(vim.uv.hrtime())
  local ok, obj = pcall(vim.system, cmd, {
    cwd = opts.cwd,
    stdin = opts.prompt,
    stdout = function(_, data)
      if not data then return end
      vim.schedule(function()
        if finished then return end
        pending = pending .. data
        for line in pending:gmatch('([^\n]*)\n') do event(line) end
        pending = pending:match('[^\n]*$')
      end)
    end,
    stderr = function(_, data) if data then table.insert(err_text, data) end end,
  }, function(res)
    vim.schedule(function()
      running[id] = nil
      if finished then return end
      if pending ~= '' then event(pending) end
      finished = true
      if result and not result.is_error then
        return opts.on_done(nil, result.result or table.concat(text), session)
      end
      local why = result and (result.result or result.subtype)
        or vim.trim(table.concat(err_text))
      if res.signal ~= 0 and why == '' then why = 'stopped' end
      opts.on_done(why ~= '' and why or ('claude exited with ' .. res.code), table.concat(text), session)
    end)
  end)
  if not ok then
    vim.schedule(function() opts.on_done('Could not run claude: ' .. tostring(obj)) end)
    return function() end
  end
  running[id] = obj
  return function()
    if running[id] then pcall(function() obj:kill(15) end) end
  end
end

function M.stop()
  local n = 0
  for _, obj in pairs(running) do
    pcall(function() obj:kill(15) end)
    n = n + 1
  end
  vim.notify(n > 0 and 'Claude: stopped' or 'Claude: nothing running')
end

-- -----------------------------------------------------------------------------
--  Context
-- -----------------------------------------------------------------------------

--- The folder claude runs in: the git root of the file, else its folder.
local function workdir(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local dir = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
  local git = vim.fs.root(dir, '.git')
  return git or (vim.uv.fs_stat(dir) and dir) or vim.fn.getcwd()
end

--- The visual selection as 1-based lines { first, last }, or nil.
local function selection()
  local mode = vim.fn.mode()
  if not mode:match('^[vV\22]') then return nil end
  local a, b = vim.fn.line('v'), vim.fn.line('.')
  vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
  return { math.min(a, b), math.max(a, b) }
end

local function diagnosticsText(buf, range)
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local line = d.lnum + 1
    if not range or (line >= range[1] and line <= range[2]) then
      table.insert(out, ('line %d: %s: %s'):format(line, vim.diagnostic.severity[d.severity]:lower(),
        (d.message:gsub('\n', ' '))))
    end
  end
  return table.concat(out, '\n')
end

--- The file as the request sees it. `mark` puts a line with a marker in it:
--- { row (0-based, the marker goes before it), text }.
local function fileText(buf, mark)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if mark then table.insert(lines, mark[1] + 1, mark[2]) end
  -- Very long files: the part around the cursor.
  local limit = 3000
  if #lines > limit then
    local center = mark and mark[1] or vim.api.nvim_win_get_cursor(0)[1]
    local first = math.max(1, center - limit / 2)
    lines = vim.list_slice(lines, first, first + limit - 1)
    table.insert(lines, 1, ('[... lines before %d left out ...]'):format(first))
    table.insert(lines, '[... rest left out ...]')
  end
  return table.concat(lines, '\n')
end

local function header(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local cwd = workdir(buf)
  local shown = name == '' and '[no name]'
    or (vim.fs.relpath and vim.fs.relpath(cwd, name)) or name
  local ft = vim.bo[buf].filetype
  return ('File: %s%s\nToday: %s'):format(shown, ft ~= '' and (' (' .. ft .. ')') or '',
    os.date('%Y-%m-%d, %A'))
end

local function context(buf, range)
  local parts = { header(buf) }
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  if range then
    local sel = vim.api.nvim_buf_get_lines(buf, range[1] - 1, range[2], false)
    table.insert(parts, ('Selected lines %d-%d:\n<selection>\n%s\n</selection>'):format(range[1], range[2],
      table.concat(sel, '\n')))
  else
    table.insert(parts, ('Cursor on line %d: %s'):format(cursor,
      vim.api.nvim_buf_get_lines(buf, cursor - 1, cursor, false)[1] or ''))
  end
  table.insert(parts, '<file>\n' .. fileText(buf) .. '\n</file>')
  local diag = diagnosticsText(buf, range)
  if diag ~= '' then table.insert(parts, '<diagnostics>\n' .. diag .. '\n</diagnostics>') end
  return table.concat(parts, '\n\n')
end

-- -----------------------------------------------------------------------------
--  Ask: the answer in a window
-- -----------------------------------------------------------------------------

local ASK_RULES = 'You are called from inside Neovim with the user\'s current buffer as context. '
  .. 'Answer the request directly and briefly, in the language the request is written in. '
  .. 'Markdown is fine; the answer is shown in a small floating window. '
  .. 'You may read other files of the project, never change them.'

local function addHistory(kind, question, answer, session)
  table.insert(history, { kind = kind, question = question, answer = answer, session = session, time = os.time() })
  if #history > 50 then table.remove(history, 1) end
end

--- A window for an answer: `question` on top, then the answer as it comes.
--- Returns an object to write into it.
local function answerWindow(title)
  local win, buf = require('configs.functions').createWindow(' Claude · ' .. title .. ' ', 0.7)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'wipe'
  vim.b[buf].pure_mdview = true
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  vim.wo[win].conceallevel = 2
  local w = { win = win, buf = buf }

  function w.valid() return vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) end
  function w.title(s)
    if w.valid() then pcall(vim.api.nvim_win_set_config, win, { title = ' Claude · ' .. s .. ' ' }) end
  end
  --- Append `s` (may hold newlines) at the end, following it with the
  --- cursor when the cursor is on the last line.
  function w.append(s)
    if not w.valid() then return end
    local count = vim.api.nvim_buf_line_count(buf)
    local follow = vim.api.nvim_win_get_cursor(win)[1] >= count - 1
    local last_line = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)[1] or ''
    local new = vim.split(last_line .. s, '\n', { plain = true })
    vim.api.nvim_buf_set_lines(buf, count - 1, count, false, new)
    if follow then
      pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end
  return w
end

--- Stream one request into the window `w`.
local function askInto(w, question, prompt, opts)
  local answer = {}
  local stopped = false
  w.title('thinking…')
  local stop = run({
    prompt = prompt,
    tools = READ_TOOLS,
    cwd = opts.cwd,
    resume = opts.session,
    keep = true,
    on_tool = function(name) w.title(name == 'Read' and 'reading…' or 'searching…') end,
    on_text = function(s)
      table.insert(answer, s)
      w.title('writing…')
      w.append(s)
    end,
    on_done = function(err, text, session)
      if err then
        if not stopped then
          w.append('\n\n> **Error:** ' .. err:gsub('\n', '\n> ') .. '\n')
          if not w.valid() then vim.notify('Claude: ' .. err, vim.log.levels.ERROR) end
        end
        w.title('error')
        return
      end
      if #answer == 0 then w.append(text) end
      w.append('\n')
      w.title(opts.kind .. ' · a: follow up, y: copy, q: close')
      w.session = session
      w.answer = text
      addHistory(opts.kind, question, text, session)
    end,
  })
  w.stop = function() stopped = true; stop() end
end

local function openAnswer(kind, question, prompt, cwd, preset)
  local w = answerWindow(kind)
  vim.api.nvim_buf_set_lines(w.buf, 0, -1, false, { '## ' .. (question:gsub('\n', ' ')), '', '' })
  if preset then
    vim.api.nvim_buf_set_lines(w.buf, 2, -1, false, vim.split(preset, '\n', { plain = true }))
  end

  local o = { buffer = w.buf, nowait = true, silent = true }
  vim.keymap.set('n', 'q', function() pcall(vim.api.nvim_win_close, w.win, true) end, o)
  vim.keymap.set('n', '<Esc>', function() pcall(vim.api.nvim_win_close, w.win, true) end, o)
  vim.keymap.set('n', 'y', function()
    if not w.answer then return end
    vim.fn.setreg('+', w.answer)
    vim.fn.setreg('"', w.answer)
    vim.notify('Claude: answer copied')
  end, o)
  vim.keymap.set('n', 'a', function()
    if not w.session then return vim.notify('Claude: wait for the answer first') end
    vim.ui.input({ prompt = ' Follow up: ' }, function(q)
      if not q or vim.trim(q) == '' or not w.valid() then return end
      vim.api.nvim_set_current_win(w.win)
      w.append('\n---\n\n## ' .. q .. '\n\n')
      askInto(w, q, q, { cwd = cwd, session = w.session, kind = kind })
    end)
  end, o)
  -- Closing the window stops a request still running: nobody would see it.
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(w.win),
    once = true,
    callback = function() if w.stop and not w.answer then w.stop() end end,
  })

  if prompt then askInto(w, question, prompt, { cwd = cwd, kind = kind }) end
  return w
end

--- Ask about the buffer; the answer shows in a window.
function M.ask(question, range)
  local buf = vim.api.nvim_get_current_buf()
  range = range or selection()
  local function go(q)
    if not q or vim.trim(q) == '' then return end
    last = { kind = 'ask', instruction = q }
    local prompt = ASK_RULES .. '\n\n' .. context(buf, range) .. '\n\nRequest: ' .. q
    openAnswer('ask', q, prompt, workdir(buf))
  end
  if question then return go(question) end
  vim.ui.input({ prompt = range and ' Ask about the selection: ' or ' Ask Claude: ' }, go)
end

local REVIEW = 'Review this code. Point out bugs, risky cases and clear simplifications, each with its line '
  .. 'number, most important first. Skip style nits. If it is fine, say so in one line.'

function M.review(range)
  local buf = vim.api.nvim_get_current_buf()
  range = range or selection()
  last = { kind = 'review' }
  local prompt = ASK_RULES .. '\n\n' .. context(buf, range) .. '\n\nRequest: ' .. REVIEW
  openAnswer('review', range and ('Review of lines %d-%d'):format(range[1], range[2]) or 'Review',
    prompt, workdir(buf))
end

-- -----------------------------------------------------------------------------
--  Write: the answer into the buffer
-- -----------------------------------------------------------------------------

local WRITE_RULES = 'You are called from inside Neovim to write text straight into the user\'s buffer. '
  .. 'Your whole answer is inserted as is, so write ONLY the text to insert: no explanation, no preamble, '
  .. 'no markdown code fence around it (unless the file is markdown and the text itself needs one). '
  .. 'Match the file\'s language, style and indentation, and start or end with a blank line when the '
  .. 'surrounding text needs one to stay separated.'

local MARK = '<<<INSERT HERE>>>'

--- An answer wrapped whole in one ``` fence: the inside only.
local function unfence(text)
  local lines = vim.split(vim.trim(text), '\n', { plain = true })
  if #lines >= 2 and lines[1]:match('^%s*```') and lines[#lines]:match('^%s*```%s*$') then
    return vim.list_slice(lines, 2, #lines - 1)
  end
  return vim.split((text:gsub('%s+$', '')), '\n', { plain = true })
end

--- Write into the buffer: at the cursor, or over the selection.
function M.write(instruction, range)
  local buf = vim.api.nvim_get_current_buf()
  range = range or selection()
  local function go(q)
    if not q or vim.trim(q) == '' then return end
    last = { kind = 'write', instruction = q }
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
    local first, last_row -- 0-based rows replaced: [first, last_row)
    local prompt
    if range then
      first, last_row = range[1] - 1, range[2]
      prompt = WRITE_RULES .. '\n\n' .. context(buf, range)
        .. '\n\nYour answer REPLACES the selected lines.\n\nRequest: ' .. q
    else
      -- A blank cursor line is filled; otherwise the text goes below it.
      local here = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
      if here:match('^%s*$') then first, last_row = row, row + 1 else first, last_row = row + 1, row + 1 end
      prompt = WRITE_RULES .. '\n\n' .. header(buf)
        .. ('\n\nThe file, with %s where your answer goes:\n<file>\n%s\n</file>'):format(MARK,
          fileText(buf, { first, MARK }))
      local diag = diagnosticsText(buf)
      if diag ~= '' then prompt = prompt .. '\n\n<diagnostics>\n' .. diag .. '\n</diagnostics>' end
      prompt = prompt .. '\n\nRequest: ' .. q
    end

    -- A mark keeps the place while the text comes, even if lines are added
    -- or removed above meanwhile. Below the cursor line: the mark is on it
    -- and the text goes after it. Otherwise the mark is on the first line
    -- replaced.
    local below = first == last_row
    local anchor = below and first - 1 or first
    local count = last_row - first
    local a_mark = vim.api.nvim_buf_set_extmark(buf, ns, anchor, 0, {})
    local hl = range and vim.api.nvim_buf_set_extmark(buf, ns, first, 0,
      { end_row = last_row - 1, end_col = #(vim.api.nvim_buf_get_lines(buf, last_row - 1, last_row, false)[1] or ''),
        hl_group = 'Visual', hl_eol = true }) or nil
    local ghost_row = last_row - 1
    local ghost = vim.api.nvim_buf_set_extmark(buf, ns, ghost_row, 0, {
      virt_lines = { { { '  Claude is writing…', 'Comment' } } },
    })
    local streamed = ''
    local function clear()
      for _, id in ipairs({ a_mark, ghost, hl }) do
        if id then pcall(vim.api.nvim_buf_del_extmark, buf, ns, id) end
      end
    end

    run({
      prompt = prompt,
      cwd = workdir(buf),
      on_text = function(s)
        streamed = streamed .. s
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local shown = {}
        for _, l in ipairs(vim.split(streamed, '\n', { plain = true })) do
          table.insert(shown, { { l == '' and ' ' or l, 'Comment' } })
        end
        local at = vim.api.nvim_buf_get_extmark_by_id(buf, ns, ghost, {})
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, at[1] or ghost_row, 0, { id = ghost, virt_lines = shown })
      end,
      on_done = function(err, text)
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local at = vim.api.nvim_buf_get_extmark_by_id(buf, ns, a_mark, {})[1]
        clear()
        if err then return vim.notify('Claude: ' .. err, vim.log.levels.ERROR) end
        if not vim.bo[buf].modifiable then
          return vim.notify('Claude: the buffer is not modifiable', vim.log.levels.WARN)
        end
        local lines = unfence(text)
        if not at then return end
        if below then
          vim.api.nvim_buf_set_lines(buf, at + 1, at + 1, false, lines)
        else
          vim.api.nvim_buf_set_lines(buf, at, at + count, false, lines)
        end
        addHistory('write', q, text)
        vim.notify(('Claude: %d line%s written (u undoes)'):format(#lines, #lines == 1 and '' or 's'))
      end,
    })
  end
  if instruction then return go(instruction) end
  vim.ui.input({ prompt = range and ' Rewrite the selection: ' or ' Write here: ' }, go)
end

--- The last request again, with the context of now.
function M.repeatLast()
  if not last then return vim.notify('Claude: nothing to repeat yet') end
  local range = selection()
  if last.kind == 'write' then return M.write(last.instruction, range) end
  if last.kind == 'review' then return M.review(range) end
  M.ask(last.instruction, range)
end

--- Past answers of this session; picking one opens it (with follow-ups).
function M.history()
  local items = {}
  for i = #history, 1, -1 do table.insert(items, history[i]) end
  if #items == 0 then return vim.notify('Claude: no answers yet') end
  vim.ui.select(items, {
    prompt = 'Claude answers',
    format_item = function(h)
      return ('%s  %-6s %s'):format(os.date('%H:%M', h.time), h.kind, (h.question:gsub('\n', ' ')))
    end,
  }, function(h)
    if not h then return end
    local w = openAnswer(h.kind, h.question, nil, vim.fn.getcwd(), h.answer)
    w.session, w.answer = h.session, h.answer
    w.title(h.kind .. (h.session and ' · a: follow up, y: copy, q: close' or ' · y: copy, q: close'))
  end)
end

-- -----------------------------------------------------------------------------
--  Blocks in notes
-- -----------------------------------------------------------------------------

local block_begin, block_end = '<!-- claude -->', '<!-- /claude -->'

--- Every ```claude block: { first, last (0-based fence rows), options, prompt }.
local function blocksIn(lines)
  local blocks, i = {}, 1
  while i <= #lines do
    if lines[i]:match('^%s*```%s*claude%s*$') then
      local j = i + 1
      while j <= #lines and not lines[j]:match('^%s*```%s*$') do j = j + 1 end
      local options, body, head = {}, {}, true
      for k = i + 1, j - 1 do
        local key, value = lines[k]:match('^%s*(%a+)%s*:%s*(.-)%s*$')
        if head and key and (key == 'when' or key == 'run') then
          options[key] = value:lower()
        else
          head = head and lines[k]:match('^%s*$') ~= nil
          table.insert(body, lines[k])
        end
      end
      table.insert(blocks, {
        first = i - 1, last = math.min(j, #lines) - 1,
        options = options, prompt = vim.trim(table.concat(body, '\n')),
      })
      i = j + 1
    else
      i = i + 1
    end
  end
  return blocks
end

--- The answer under `block`: 0-based rows of its markers; false when the
--- begin marker has no end (left alone), nil when there is none.
local function regionOf(lines, block)
  local row = block.last + 1
  if vim.trim(lines[row + 1] or '') ~= block_begin then return nil end
  for r = row + 1, #lines - 1 do
    local text = vim.trim(lines[r + 1])
    if text == block_end then return { first = row, last = r } end
    if text == block_begin or text:match('^```%s*claude') then break end
  end
  return false
end

--- mdview hides a block that has an answer, and the answer's markers.
function M.hiddenBlocks(buf)
  local ranges = {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, b in ipairs(blocksIn(lines)) do
    local region = regionOf(lines, b)
    if region then
      table.insert(ranges, { b.first, region.first })
      table.insert(ranges, { region.last, region.last })
    end
  end
  return ranges
end

local function key(p)
  p = vim.fs.normalize(p)
  return vim.fn.has('win32') == 1 and p:lower() or p
end

--- Not in the templates or the trash.
local function allowed(path)
  local ok, zet = pcall(require, 'pure.zettelkasten')
  local vault = ok and zet.vaultPath() or nil
  if not vault then return true end
  local note = key(path)
  for _, folder in ipairs({ zet.templatesPath and zet.templatesPath() or (vault .. '/Templates'),
    vault .. '/' .. ((zet._destinations or {}).Delete or '0-Inbox/Trash') }) do
    local f = key(folder)
    if note:sub(1, #f + 1) == f .. '/' then return false end
  end
  return true
end

local WEEKDAYS = {
  monday = 1, tuesday = 2, wednesday = 3, thursday = 4, friday = 5, saturday = 6, sunday = 7,
  segunda = 1, terca = 2, ['terça'] = 2, quarta = 3, quinta = 4, sexta = 5, sabado = 6, ['sábado'] = 6, domingo = 7,
}

local function noonOf(y, m, d) return os.time({ year = y, month = m, day = d, hour = 12 }) end
local DAY = 86400

--- Monday (noon) of ISO week `w` of `y`.
local function isoMonday(y, w)
  local jan4 = noonOf(y, 1, 4)
  local wday = (os.date('*t', jan4).wday + 5) % 7 -- Monday = 0
  return jan4 - wday * DAY + (w - 1) * 7 * DAY
end

--- Whether a block may run now in the note `path`: { ok, why }.
local function due(path, block)
  if block.options.run == 'manual' then return false end
  local name = vim.fn.fnamemodify(path, ':t:r')
  local now = os.time()
  local today = noonOf(os.date('*t', now).year, os.date('*t', now).month, os.date('*t', now).day)
  local week_start
  local y, m, d = name:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  if y then
    if os.date('%Y-%m-%d', now) ~= name then return false end
  end
  local wy, ww = name:match('^(%d%d%d%d)%-W(%d%d)$')
  if wy then
    week_start = isoMonday(tonumber(wy), tonumber(ww))
    if today < week_start or today >= week_start + 14 * DAY then return false end
  end
  local my, mm = name:match('^(%d%d%d%d)%-(%d%d)$')
  if my then
    local first = noonOf(tonumber(my), tonumber(mm), 1)
    local after_next = noonOf(tonumber(my), tonumber(mm) + 2, 1)
    if today < first or today >= after_next then return false end
  end
  local when = block.options.when and WEEKDAYS[block.options.when]
  if when then
    week_start = week_start or (today - ((os.date('*t', today).wday + 5) % 7) * DAY)
    if today < week_start + (when - 1) * DAY then return false end
  end
  return true
end

local BLOCK_RULES = 'You are called from inside Neovim for a request written in a note of an Obsidian vault '
  .. '(the current folder). Your answer is written into the note, right under the request, as markdown. '
  .. 'Write ONLY that content: no preamble, no code fence around it, no heading repeating the request. '
  .. 'Use the note\'s language. You may read the vault (other notes) to answer, never change it. '
  .. 'Link notes as [[wikilinks]].'

local block_running = {} -- note key .. ':' .. block row -> true

--- Hints about where the periodic notes live, for requests like
--- "yesterday's daily".
local function vaultHints()
  local ok, zet = pcall(require, 'pure.zettelkasten')
  local out = {}
  for _, period in ipairs({ 'Daily', 'Weekly', 'Monthly' }) do
    local p = ok and zet._periodic and zet._periodic[period]
    if p then table.insert(out, ('%s notes: %s/%s.md'):format(period, p.folder, p.name)) end
  end
  return #out > 0 and ('Periodic notes (os.date names): ' .. table.concat(out, '; ')) or ''
end

--- Run `block` of the note in `buf` and write the answer under it.
local function runBlock(buf, block)
  local path = vim.api.nvim_buf_get_name(buf)
  local id = key(path) .. ':' .. block.first
  if block_running[id] then return end
  if block.prompt == '' then return end
  if block.prompt:find('{{', 1, true) then return end -- an unfilled template
  block_running[id] = true

  local ok, zet = pcall(require, 'pure.zettelkasten')
  local vault = ok and zet.vaultPath() or nil
  local cwd = vault and vim.uv.fs_stat(vault) and vault or workdir(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local shown = (vim.fs.relpath and vim.fs.relpath(cwd, path)) or path
  local prompt = BLOCK_RULES .. '\n\n'
    .. ('Note: %s\nToday: %s\n%s\n\n<note>\n%s\n</note>\n\nRequest: %s'):format(shown,
      os.date('%Y-%m-%d, %A'), vaultHints(), table.concat(lines, '\n'), block.prompt)

  local mark = vim.api.nvim_buf_set_extmark(buf, ns, block.last, 0, {
    virt_lines = { { { '  Claude is answering…', 'Comment' } } },
  })
  local tick = vim.b[buf].changedtick
  run({
    prompt = prompt,
    tools = READ_TOOLS,
    cwd = cwd,
    on_done = function(err, text)
      block_running[id] = nil
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local at = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark, {})
      pcall(vim.api.nvim_buf_del_extmark, buf, ns, mark)
      if err then return vim.notify('Claude block: ' .. err, vim.log.levels.ERROR) end
      -- Find the block again (lines may have moved meanwhile).
      local now = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local target
      for _, b in ipairs(blocksIn(now)) do
        if b.last == at[1] or (not target and b.prompt == block.prompt) then target = b end
      end
      if not target then return end
      local region = regionOf(now, target)
      if region == false then return end
      local new = { block_begin }
      vim.list_extend(new, unfence(text))
      table.insert(new, block_end)
      local s, e = target.last + 1, target.last + 1
      if region then s, e = region.first, region.last + 1 end
      local was_saved = not vim.bo[buf].modified
      vim.api.nvim_buf_set_lines(buf, s, e, false, new)
      -- Saved only when nothing else was pending: never someone's half edit.
      if was_saved and vim.b[buf].changedtick ~= tick and vim.bo[buf].buftype == '' then
        vim.api.nvim_buf_call(buf, function() vim.cmd('silent noautocmd update') end)
      end
    end,
  })
end

--- Run the blocks of `buf` that have no answer yet and are due.
local function autoBlocks(buf)
  if vim.g.pure_claude_blocks == false then return end
  if vim.bo[buf].buftype ~= '' or vim.bo[buf].modified then return end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == '' or not allowed(path) then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, b in ipairs(blocksIn(lines)) do
    if regionOf(lines, b) == nil and due(path, b) then runBlock(buf, b) end
  end
end

--- Run (again) the block under the cursor.
function M.runBlockAtCursor()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, b in ipairs(blocksIn(lines)) do
    local region = regionOf(lines, b)
    local stop = region and region.last or b.last
    if row >= b.first and row <= stop then
      if not allowed(vim.api.nvim_buf_get_name(buf)) then
        return vim.notify('Claude: blocks do not run in templates or the trash')
      end
      return runBlock(buf, b)
    end
  end
  vim.notify('Claude: no ```claude block under the cursor')
end

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufWritePost' }, {
  group = vim.api.nvim_create_augroup('PureClaudeBlocks', { clear = true }),
  pattern = { '*.md', '*.markdown' },
  callback = function(args) vim.schedule(function() autoBlocks(args.buf) end) end,
})

vim.api.nvim_create_user_command('ClaudeBlock', M.runBlockAtCursor, {
  desc = 'Run the ```claude block under the cursor (again)',
})

M._blocksIn, M._due, M._unfence, M._run = blocksIn, due, unfence, run

return M
