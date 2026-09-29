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
--    <leader>am   select model: switch on the fly between Ollama (local)
--                 and Claude (cloud).
--    <leader>as   stop what is running.
--    <leader>ab   run the ```claude block under the cursor again.
--    <leader>ax   the actions: markdown files of the vault's claude/ folder (see
--                 "Actions" below).
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
--    vim.g.pure_claude_model = nil     the default model (e.g. 'ollama:qwen2.5-coder:14b')
--    vim.g.pure_ollama_url = nil       Ollama API URL (default 'http://localhost:11434')
--    vim.g.pure_claude_cmd = 'claude'  the command
--    vim.g.pure_claude_blocks = true   false: blocks run only with <leader>ab
-- =============================================================================

local M = {}

local ns = vim.api.nvim_create_namespace('pure_claude')
local READ_TOOLS = { 'Read', 'Grep', 'Glob' }

local history = {} -- { kind, question, answer, session, time }, newest last
local running = {} -- id -> function that stops it
local last        -- the last request: { kind, instruction, visual }

-- -----------------------------------------------------------------------------
--  Model configuration and persistence
-- -----------------------------------------------------------------------------

local state_file = vim.fn.stdpath('state') .. '/pure_claude_model'

local function loadState()
  local ok, lines = pcall(vim.fn.readfile, state_file)
  if ok and lines and lines[1] and vim.trim(lines[1]) ~= '' then
    return vim.trim(lines[1])
  end
  return nil
end

local function saveState(id)
  pcall(function()
    vim.fn.mkdir(vim.fs.dirname(state_file), 'p')
    local f = io.open(state_file, 'w')
    if f then
      f:write(id)
      f:close()
    end
  end)
end

local active_model_id = loadState() or vim.g.pure_claude_model or 'claude:default'

--- Parse a model string into { backend = 'ollama'|'claude', model = string|nil, id = string, name = string }
local function parseModel(spec)
  local target = spec or active_model_id
  if not target or target == '' or target == 'default' then
    return { backend = 'claude', model = nil, id = 'claude:default', name = 'claude' }
  end

  if target:match('^ollama:') then
    local m = target:sub(8)
    return { backend = 'ollama', model = m, id = target, name = m }
  elseif target:match('^agy:') then
    -- Antigravity's CLI (agy), added to <leader>am beside Ollama and Claude.
    -- "agy:" alone: agy's own default model.
    local m = target:sub(5)
    local model = m ~= '' and m or nil
    return { backend = 'agy', model = model, id = target, name = model or 'agy' }
  elseif target:match('^claude:') then
    local m = target:sub(8)
    local model = (m == 'default' or m == '') and nil or m
    return { backend = 'claude', model = model, id = target, name = model or 'claude' }
  end

  if target == 'sonnet' or target == 'haiku' or target == 'opus' or target:match('^claude%-') then
    return { backend = 'claude', model = target, id = 'claude:' .. target, name = target }
  end

  if target:find(':') or target:match('^qwen') or target:match('^gemma') or target:match('^llama')
    or target:match('^deepseek') or target:match('^mistral') or target:match('^phi') then
    return { backend = 'ollama', model = target, id = 'ollama:' .. target, name = target }
  end

  return { backend = 'claude', model = target, id = 'claude:' .. target, name = target }
end

local function modelLabel(spec)
  local m = parseModel(spec)
  if m.backend == 'ollama' then
    return m.name
  end
  if m.backend == 'agy' then
    return m.model and ('agy ' .. m.model) or 'agy'
  end
  return m.name == 'claude' and 'Claude' or ('Claude ' .. m.name)
end

function M.getActiveModel()
  return parseModel()
end

function M.modelName()
  return parseModel().name
end

function M.setModel(id)
  if not id or vim.trim(id) == '' then return end
  local parsed = parseModel(vim.trim(id))
  active_model_id = parsed.id
  saveState(active_model_id)
  vim.notify(('Claude/LLM: active model set to [%s] %s'):format(parsed.backend, parsed.name))
end

--- Fetch local Ollama models asynchronously from /api/tags
local function fetchOllamaModels(cb)
  local url = (vim.g.pure_ollama_url or 'http://localhost:11434') .. '/api/tags'
  local ok = pcall(vim.system, { 'curl', '-s', '-m', '2', url }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 or not res.stdout or res.stdout == '' then
        return cb({}, false)
      end
      local parse_ok, data = pcall(vim.json.decode, res.stdout)
      if not parse_ok or not data or not data.models then
        return cb({}, false)
      end
      local models = {}
      for _, m in ipairs(data.models) do
        if m.name then table.insert(models, m.name) end
      end
      cb(models, true)
    end)
  end)
  if not ok then cb({}, false) end
end

--- agy's models, from `agy models` ("id<TAB>name" lines). It takes a few
--- seconds, so the list is cached in the state folder: the picker opens with
--- the cached list and it is refreshed in the background for next time. Only
--- the first time, with no cache, does the picker wait for it.
local agy_cache_file = vim.fn.stdpath('state') .. '/pure_agy_models'

local function readAgyCache()
  local ok, lines = pcall(vim.fn.readfile, agy_cache_file)
  if not ok then return nil end
  local models = {}
  for _, l in ipairs(lines) do
    local id, name = l:match('^(%S+)\t(.*)$')
    if id then table.insert(models, { id = id, name = name }) end
  end
  return #models > 0 and models or nil
end

local function fetchAgyModels(cb)
  if vim.fn.executable('agy') == 0 then return cb({}) end
  local ok = pcall(vim.system, { 'agy', 'models' }, { text = true }, function(res)
    vim.schedule(function()
      local models, lines = {}, {}
      for l in vim.gsplit(res.stdout or '', '\n', { plain = true }) do
        l = l:gsub('\r$', '')
        local id, name = l:match('^(%S+)\t(.*)$')
        if id then
          table.insert(models, { id = id, name = name })
          table.insert(lines, l)
        end
      end
      if #lines > 0 then pcall(vim.fn.writefile, lines, agy_cache_file) end
      cb(models)
    end)
  end)
  if not ok then cb({}) end
end

--- The agy models for the picker: `cb(models)`, from the cache when there
--- is one (refreshed meanwhile), else after asking agy.
local function agyModels(cb)
  local cached = readAgyCache()
  if cached then
    fetchAgyModels(function() end)
    return cb(cached)
  end
  fetchAgyModels(cb)
end

--- Interactive model selector (fzf / pure.fuzzyUtils or vim.ui.select fallback)
function M.selectModel()
  agyModels(function(agy_models)
  fetchOllamaModels(function(ollama_models, online)
    local choices = {}
    local model_map = {}
    local current = parseModel()

    -- Ollama models
    if #ollama_models > 0 then
      for _, name in ipairs(ollama_models) do
        local id = 'ollama:' .. name
        local is_active = (current.id == id or (current.backend == 'ollama' and current.model == name))
        local mark = is_active and '● ' or '  '
        local suffix = is_active and ' (active)' or ''
        local line = ('%s[ollama] %-28s%s\t%s'):format(mark, name, suffix, id)
        table.insert(choices, line)
        model_map[line] = id
      end
    else
      local status_text = online and '(no models installed in Ollama)'
        or ('(Ollama offline at ' .. (vim.g.pure_ollama_url or 'localhost:11434') .. ')')
      local line = ('  [ollama] %-28s\t'):format(status_text)
      table.insert(choices, line)
    end

    -- Claude presets
    local claude_presets = {
      { id = 'claude:default', name = 'default (Claude CLI)' },
      { id = 'claude:sonnet',  name = 'sonnet (Claude 3.7 / 3.5)' },
      { id = 'claude:haiku',   name = 'haiku (Claude 3.5)' },
      { id = 'claude:opus',    name = 'opus (Claude 3)' },
    }
    for _, c in ipairs(claude_presets) do
      local is_active = (current.id == c.id)
      local mark = is_active and '● ' or '  '
      local suffix = is_active and ' (active)' or ''
      local line = ('%s[claude] %-28s%s\t%s'):format(mark, c.name, suffix, c.id)
      table.insert(choices, line)
      model_map[line] = c.id
    end

    -- agy (Antigravity) models, when agy is installed. Its default first.
    if vim.fn.executable('agy') == 1 then
      local entries = { { id = 'agy:', name = 'default (agy CLI)' } }
      for _, m in ipairs(agy_models) do table.insert(entries, { id = 'agy:' .. m.id, name = m.name }) end
      for _, a in ipairs(entries) do
        local is_active = (current.id == a.id)
        local mark = is_active and '● ' or '  '
        local suffix = is_active and ' (active)' or ''
        local line = ('%s[agy]    %-28s%s\t%s'):format(mark, a.name, suffix, a.id)
        table.insert(choices, line)
        model_map[line] = a.id
      end
    end

    -- Custom model option
    local custom_line = '  [custom] Enter custom model name…\t__custom__'
    table.insert(choices, custom_line)
    model_map[custom_line] = '__custom__'

    local function applySelection(id)
      if not id or id == '' then return end
      if id == '__custom__' then
        vim.ui.input({ prompt = ' Model (e.g. ollama:qwen2.5-coder:14b or claude:sonnet): ' }, function(input)
          if input and vim.trim(input) ~= '' then
            M.setModel(vim.trim(input))
          end
        end)
        return
      end
      M.setModel(id)
    end

    local ok_fz, fuzzy = pcall(require, 'pure.fuzzyUtils')
    if ok_fz and fuzzy.pickList then
      fuzzy.pickList(choices, {
        title = ' LLM Models (current: ' .. current.name .. ') ',
        fzf = [[--delimiter='\t' --with-nth=1]],
      }, function(selected_line)
        applySelection(model_map[selected_line or ''])
      end)
    else
      vim.ui.select(choices, {
        prompt = 'Select LLM Model (current: ' .. current.name .. '):',
        format_item = function(item)
          return (item:match('^(.-)\t') or item)
        end,
      }, function(selected)
        if selected then applySelection(model_map[selected]) end
      end)
    end
  end)
  end) -- agyModels
end

-- -----------------------------------------------------------------------------
--  Process execution
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

--- Stop a running process. On Windows kills the whole process tree.
local function kill(obj)
  if vim.fn.has('win32') == 1 and obj.pid then
    pcall(vim.system, { 'taskkill', '/T', '/F', '/PID', tostring(obj.pid) })
  else
    pcall(function() obj:kill(15) end)
  end
end

--- Run with Claude Code CLI
local function runClaude(opts, model)
  local tools = table.concat(opts.tools or {}, ',')
  local args = { '-p', '--output-format', 'stream-json', '--verbose', '--include-partial-messages',
    '--tools', tools }
  if tools ~= '' then vim.list_extend(args, { '--allowedTools', tools }) end
  if model then vim.list_extend(args, { '--model', model }) end
  if opts.write then vim.list_extend(args, { '--permission-mode', 'acceptEdits' }) end
  for _, d in ipairs(opts.dirs or {}) do vim.list_extend(args, { '--add-dir', d }) end
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
  local finished, stopped = false, false
  local queued, flush_pending = {}, false
  local function flush()
    flush_pending = false
    if #queued == 0 or not opts.on_text then return end
    local chunk = table.concat(queued)
    queued = {}
    opts.on_text(chunk)
  end
  local function emit(piece)
    table.insert(queued, piece)
    if not flush_pending then
      flush_pending = true
      vim.defer_fn(function() if not finished then flush() end end, 60)
    end
  end
  local function event(line)
    local ok, ev = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
    if not ok or type(ev) ~= 'table' then return end
    session = ev.session_id or session
    if ev.type == 'stream_event' and ev.event then
      local e = ev.event
      if e.type == 'content_block_delta' and e.delta and e.delta.type == 'text_delta' and not ev.parent_tool_use_id then
        table.insert(text, e.delta.text)
        emit(e.delta.text)
      elseif e.type == 'content_block_start' and e.content_block and e.content_block.type == 'tool_use' then
        if opts.on_tool then opts.on_tool(e.content_block.name) end
      elseif e.type == 'message_start' and #text > 0 then
        table.insert(text, '\n\n')
        emit('\n\n')
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
        local start = 1
        while true do
          local nl = pending:find('\n', start, true)
          if not nl then break end
          event(pending:sub(start, nl - 1))
          start = nl + 1
        end
        pending = pending:sub(start)
      end)
    end,
    stderr = function(_, data) if data then table.insert(err_text, data) end end,
  }, function(res)
    vim.schedule(function()
      running[id] = nil
      if finished then return end
      if pending ~= '' then event(pending) end
      flush()
      finished = true
      if result and not result.is_error then
        return opts.on_done(nil, result.result or table.concat(text), session)
      end
      local why = result and (result.result or result.subtype)
        or vim.trim(table.concat(err_text))
      if stopped then why = 'stopped' end
      opts.on_done(why ~= '' and why or ('claude exited with ' .. res.code), table.concat(text), session)
    end)
  end)
  if not ok then
    vim.schedule(function() opts.on_done('Could not run claude: ' .. tostring(obj)) end)
    return function() end
  end
  local function stop()
    if running[id] then
      stopped = true
      kill(obj)
    end
  end
  running[id] = stop
  return stop
end

--- Run with agy (Antigravity's CLI), added to <leader>am. Same shape as
--- runClaude: print mode, streamed JSON.
---
--- The prompt goes on stdin as one stream-json "user" event, not as -p's
--- argument: a prompt with the whole file in it is too long for a Windows
--- command line (32k characters). agy has no --tools list, so what a request
--- may do is set by its mode. Its default mode asks before each edit, and
--- print mode has nobody to ask, so edits fail and reads work: read-only.
--- A request that writes (opts.write) gets accept-edits. (Not --mode plan:
--- it answered "I have created the plan... approve it" before the answer.)
--- Its events:
---   step_update  step_type agent_response: text_delta is answer text;
---                another step type, while ACTIVE, is agy using a tool
---   result       status SUCCESS and response (the whole answer), or error
local function runAgy(opts, model)
  local exe = vim.fn.exepath('agy')
  if exe == '' then
    vim.schedule(function() opts.on_done('agy is not installed: `agy` is not in the PATH') end)
    return function() end
  end
  local args = { exe, '--output-format', 'stream-json', '--input-format', 'stream-json' }
  if opts.write then vim.list_extend(args, { '--mode', 'accept-edits' }) end
  if model then vim.list_extend(args, { '--model', model }) end
  for _, d in ipairs(opts.dirs or {}) do vim.list_extend(args, { '--add-dir', d }) end
  if opts.resume then vim.list_extend(args, { '--conversation', opts.resume }) end
  -- -p last and empty: the prompt comes from stdin. (Given first, -p took the
  -- next flag as its prompt.)
  vim.list_extend(args, { '-p', '' })
  local input = vim.json.encode({ event = 'user', message = { role = 'user', content = opts.prompt } }) .. '\n'

  local pending, text, session, result, err_text = '', {}, nil, nil, {}
  local finished, stopped = false, false
  local queued, flush_pending = {}, false
  local function flush()
    flush_pending = false
    if #queued == 0 or not opts.on_text then return end
    local chunk = table.concat(queued)
    queued = {}
    opts.on_text(chunk)
  end
  local function emit(piece)
    table.insert(queued, piece)
    if not flush_pending then
      flush_pending = true
      vim.defer_fn(function() if not finished then flush() end end, 60)
    end
  end
  local last_step
  local function event(line)
    local ok, ev = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
    if not ok or type(ev) ~= 'table' then return end
    if ev.event == 'init' and ev.conversation_id then session = ev.conversation_id end
    if ev.event == 'step_update' and ev.step_update then
      local s = ev.step_update
      session = s.conversation_id or session
      if s.step_type == 'agent_response' then
        -- A new response step after an earlier one: a blank line between.
        if last_step and last_step ~= s.step_index and #text > 0 then
          table.insert(text, '\n\n')
          emit('\n\n')
        end
        last_step = s.step_index
        if s.text_delta and s.text_delta ~= '' then
          table.insert(text, s.text_delta)
          emit(s.text_delta)
        end
      elseif s.state == 'ACTIVE' and s.step_type ~= 'user_input' and opts.on_tool then
        -- agy's view_file is Claude's Read: the window then says "reading…".
        local tool = s.tool_name or s.step_type
        opts.on_tool(tool == 'view_file' and 'Read' or tool)
      end
    elseif ev.event == 'result' and ev.result then
      result = ev.result
      session = result.conversation_id or session
    end
  end

  local id = tostring(vim.uv.hrtime())
  local ok, obj = pcall(vim.system, args, {
    cwd = opts.cwd,
    stdin = input,
    stdout = function(_, data)
      if not data then return end
      vim.schedule(function()
        if finished then return end
        pending = pending .. data
        local start = 1
        while true do
          local nl = pending:find('\n', start, true)
          if not nl then break end
          event((pending:sub(start, nl - 1):gsub('\r$', '')))
          start = nl + 1
        end
        pending = pending:sub(start)
      end)
    end,
    stderr = function(_, data) if data then table.insert(err_text, data) end end,
  }, function(res)
    vim.schedule(function()
      running[id] = nil
      if finished then return end
      if pending ~= '' then event(pending) end
      flush()
      finished = true
      if stopped then return opts.on_done('stopped', table.concat(text), session) end
      if result and result.status == 'SUCCESS' then
        local answer = (result.response and result.response ~= '') and result.response or table.concat(text)
        -- It happened in testing: SUCCESS with no answer at all. Said so,
        -- rather than an empty window or nothing written with no reason.
        if vim.trim(answer) == '' then
          return opts.on_done('agy returned an empty answer; try again (<leader>ar)', '', session)
        end
        return opts.on_done(nil, answer, session)
      end
      local why = result and (result.error or result.status) or vim.trim(table.concat(err_text))
      opts.on_done((why and why ~= '') and ('agy: ' .. why) or ('agy exited with ' .. res.code),
        table.concat(text), session)
    end)
  end)
  if not ok then
    vim.schedule(function() opts.on_done('Could not run agy: ' .. tostring(obj)) end)
    return function() end
  end
  local function stop()
    if running[id] then
      stopped = true
      kill(obj)
    end
  end
  running[id] = stop
  return stop
end

local ollama_sessions = {} -- session_id -> { messages = ... }

-- -----------------------------------------------------------------------------
--  Tools for local models
-- -----------------------------------------------------------------------------
--  Claude Code brings its own tools (Read, Grep, Glob, Edit, Write); Ollama
--  has none, and runOllama used to ignore opts.tools. So a local model could
--  not read another file, and an action or block meant to change files only
--  described the change. These are the same tools, run here by Neovim and
--  offered through Ollama's tool calling: the names in opts.tools (as the
--  actions and blocks write them) pick which ones the model gets.
--
--  Every path must be inside opts.cwd or one of opts.dirs. Edit / Write only
--  when opts.tools has them, and never on a file with unsaved changes in
--  Neovim (the edit would be lost on the next :w, or lose them).

local TOOL_LIMIT = 40000 -- characters of one tool result the model gets back
local MAX_ROUNDS = 25    -- rounds of tool calls before giving up

--- Tool definitions, by the Claude Code name that enables them.
local OLLAMA_TOOLS = {
  Read = { name = 'read_file', description = 'Read a text file. Returns it with line numbers.',
    parameters = { type = 'object', required = { 'path' }, properties = {
      path = { type = 'string', description = 'File path, relative to the working folder or absolute' } } } },
  Glob = { name = 'list_files', description = 'List files matching a glob pattern, e.g. "**/*.md".',
    parameters = { type = 'object', required = { 'pattern' }, properties = {
      pattern = { type = 'string', description = 'Glob pattern' },
      path = { type = 'string', description = 'Folder to search in (default: the working folder)' } } } },
  Grep = { name = 'grep', description = 'Search file contents with a regular expression. Returns file:line:text.',
    parameters = { type = 'object', required = { 'pattern' }, properties = {
      pattern = { type = 'string', description = 'Regular expression' },
      path = { type = 'string', description = 'File or folder to search in (default: the working folder)' } } } },
  Edit = { name = 'edit_file', description = 'Replace an exact piece of text in a file. old_text must appear '
      .. 'exactly once; include enough surrounding text to make it unique. Read the file first.',
    parameters = { type = 'object', required = { 'path', 'old_text', 'new_text' }, properties = {
      path = { type = 'string' }, old_text = { type = 'string' }, new_text = { type = 'string' } } } },
  Write = { name = 'write_file', description = 'Create a file, or replace a whole file, with the given content.',
    parameters = { type = 'object', required = { 'path', 'content' }, properties = {
      path = { type = 'string' }, content = { type = 'string' } } } },
}
-- MultiEdit is Claude Code's multi-replace: the same edit_file, called once
-- per change.
OLLAMA_TOOLS.MultiEdit = OLLAMA_TOOLS.Edit
local CLAUDE_NAME = { read_file = 'Read', list_files = 'Glob', grep = 'Grep', edit_file = 'Edit', write_file = 'Write' }

--- The tools opts.tools enables ("Edit(notes/**)" counts as Edit), without
--- repeats; and a set of their names.
local function ollamaTools(names)
  local defs, seen = {}, {}
  for _, n in ipairs(names or {}) do
    local def = OLLAMA_TOOLS[n:match('^%a+') or '']
    if def and not seen[def.name] then
      seen[def.name] = true
      table.insert(defs, { type = 'function', ['function'] = def })
    end
  end
  return defs, seen
end

local function toolKey(p)
  p = vim.fs.normalize(p)
  return vim.fn.has('win32') == 1 and p:lower() or p
end

--- `path` made absolute against the request's folder, or nil and why when it
--- is outside every folder the request may use.
local function toolPath(path, opts)
  if type(path) ~= 'string' or path == '' then return nil, 'no path given' end
  local cwd = opts.cwd or vim.fn.getcwd()
  local absolute = path:match('^%a:[/\\]') or path:match('^[/\\]')
  -- simplify() resolves "." and "..": without it "proj/../outside.txt"
  -- starts with "proj/" and passed the check below, and "proj/." (the
  -- folder itself) did not.
  -- fs_realpath() on the part that exists: Windows spelled the same folder
  -- "MIASCH~1" one time and "Mia Schionato" the next, so the folder itself
  -- failed the check; it also follows symlinks, so a link inside the
  -- folder cannot lead the model outside it. A file not made yet keeps the
  -- rest of its path as given.
  local function full(p)
    p = (vim.fs.normalize(vim.fn.simplify(vim.fn.fnamemodify(p, ':p'))):gsub('/$', ''))
    local rest, cur = {}, p
    while not vim.uv.fs_realpath(cur) do
      local parent = vim.fs.dirname(cur)
      if not parent or parent == cur then return p end
      table.insert(rest, 1, vim.fs.basename(cur))
      cur = parent
    end
    local base = (vim.fs.normalize(vim.uv.fs_realpath(cur)):gsub('/$', ''))
    return #rest > 0 and (base .. '/' .. table.concat(rest, '/')) or base
  end
  -- The path as given is kept for the file itself (a new file keeps its
  -- case); the comparison is case-blind on Windows.
  local abs = full(absolute and path or (cwd .. '/' .. path))
  local key = toolKey(abs)
  for _, root in ipairs(vim.list_extend({ cwd }, opts.dirs or {})) do
    local r = toolKey(full(root))
    if key == r or key:sub(1, #r + 1) == r .. '/' then return abs end
  end
  return nil, 'outside the folders this request may use: ' .. path
end

local function clip(s)
  if #s <= TOOL_LIMIT then return s end
  return s:sub(1, TOOL_LIMIT) .. '\n[... cut: ' .. (#s - TOOL_LIMIT) .. ' more characters ...]'
end

--- Whether `abs` is open in Neovim with unsaved changes.
local function dirtyBuffer(abs)
  local b = vim.fn.bufnr(abs)
  return b > 0 and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified
end

--- Run one tool call; the text the model gets back.
local function runTool(name, args, opts)
  args = type(args) == 'table' and args or {}
  if name == 'read_file' then
    local abs, why = toolPath(args.path, opts)
    if not abs then return 'Error: ' .. why end
    local ok, lines = pcall(vim.fn.readfile, abs)
    if not ok then return 'Error: cannot read ' .. tostring(args.path) end
    for i, l in ipairs(lines) do lines[i] = ('%d\t%s'):format(i, l) end
    return clip(table.concat(lines, '\n'))
  elseif name == 'list_files' or name == 'grep' then
    local abs, why = toolPath(args.path or '.', opts)
    if not abs then return 'Error: ' .. why end
    if vim.fn.executable('rg') == 0 then return 'Error: ripgrep (rg) is not installed' end
    local cmd = name == 'grep'
      and { 'rg', '--line-number', '--no-heading', '--smart-case', '--max-count', '50', '--', args.pattern or '', abs }
      or { 'rg', '--files', '--glob', args.pattern or '*', abs }
    if not vim.uv.fs_stat(abs) then return 'Error: no such file or folder: ' .. tostring(args.path) end
    local res = vim.system(cmd, { text = true }):wait(15000)
    local out = vim.trim((res.stdout or ''):gsub('\r', ''))
    -- rg exits 1 for "nothing found", 2 for a real error (bad regex...).
    if res.code == 2 and out == '' then return 'Error: ' .. vim.trim(res.stderr or 'rg failed') end
    if out == '' then return 'No matches.' end
    -- Relative to the request's folder, as the model's own paths are: short
    -- paths it can pass straight back to read_file.
    local base = vim.uv.fs_realpath(opts.cwd or vim.fn.getcwd())
    if base then
      base = vim.fs.normalize(base):gsub('/$', '') .. '/'
      local lines = {}
      for l in vim.gsplit(out, '\n', { plain = true }) do
        l = l:gsub('\\', '/')
        if toolKey(l:sub(1, #base)) == toolKey(base) then l = l:sub(#base + 1) end
        table.insert(lines, l)
      end
      out = table.concat(lines, '\n')
    end
    return clip(out)
  elseif name == 'edit_file' or name == 'write_file' then
    local abs, why = toolPath(args.path, opts)
    if not abs then return 'Error: ' .. why end
    if dirtyBuffer(abs) then
      return 'Error: ' .. args.path .. ' has unsaved changes in the editor; not changed'
    end
    local content
    if name == 'write_file' then
      content = args.content or ''
    else
      local f = io.open(abs, 'rb')
      if not f then return 'Error: cannot read ' .. args.path end
      local old = f:read('*a')
      f:close()
      local needle = args.old_text or ''
      local from, to = old:find(needle, 1, true)
      if needle == '' or not from then
        return 'Error: old_text was not found in ' .. args.path .. '; read the file and copy the text exactly'
      end
      if old:find(needle, to + 1, true) then
        return 'Error: old_text appears more than once; include more surrounding text'
      end
      content = old:sub(1, from - 1) .. (args.new_text or '') .. old:sub(to + 1)
    end
    vim.fn.mkdir(vim.fs.dirname(abs), 'p')
    local f = io.open(abs, 'wb')
    if not f then return 'Error: cannot write ' .. args.path end
    f:write(content)
    f:close()
    return (name == 'write_file' and 'Wrote ' or 'Edited ') .. args.path
  end
  return 'Error: unknown tool ' .. tostring(name)
end

--- Models Ollama said have no tool support: asked without tools from then on.
local no_tools = {}

--- Tool calls a model wrote as text instead of through Ollama's tool_calls:
--- qwen2.5-coder answered a plain question with
---   {"name": "read_file", "arguments": {"path": "x.md"}}
--- (bare, in a ```json fence, or in qwen's <tool_call> tags), and that JSON
--- was shown as the answer. Only names in `enabled` count, so an answer that
--- is JSON for another reason stays an answer. Returns calls shaped like
--- Ollama's, or nil.
---
--- Only the FIRST call is taken. qwen2.5-coder also wrote a whole plan at
--- once: read_file, then edit_file with an old_text it had guessed without
--- reading, then "done". Running the first one and giving it the result lets
--- it make the next call knowing the file, as a real tool loop does.

--- The JSON value starting at `s`'s first character ('{' or '['), balanced
--- by hand (strings and escapes respected), or nil.
local function leadingJson(s)
  local open = s:sub(1, 1)
  if open ~= '{' and open ~= '[' then return nil end
  local depth, in_str, esc = 0, false, false
  for i = 1, #s do
    local ch = s:sub(i, i)
    if in_str then
      if esc then esc = false
      elseif ch == '\\' then esc = true
      elseif ch == '"' then in_str = false end
    elseif ch == '"' then in_str = true
    elseif ch == '{' or ch == '[' then depth = depth + 1
    elseif ch == '}' or ch == ']' then
      depth = depth - 1
      if depth == 0 then return s:sub(1, i) end
    end
  end
  return nil
end

local function textToolCalls(s, enabled)
  s = vim.trim(s)
  -- The first call's JSON: inside <tool_call> tags, a ``` fence, or bare.
  local body = s:match('^<tool_call>%s*(.-)%s*</tool_call>')
    or s:match('^```%w*%s*\n(.-)\n%s*```') or s
  local json = leadingJson(vim.trim(body))
  if not json then return nil end
  local ok, data = pcall(vim.json.decode, json)
  if not ok or type(data) ~= 'table' then return nil end
  local c = vim.islist(data) and data[1] or data
  if type(c) ~= 'table' then return nil end
  local fn = type(c['function']) == 'table' and c['function'] or c
  if type(fn.name) ~= 'string' or not enabled[fn.name] then return nil end
  return { { ['function'] = { name = fn.name, arguments = fn.arguments or fn.parameters or {} } } }
end
M._textToolCalls = textToolCalls

--- Run with the local Ollama API. With tools (opts.tools), the model's tool
--- calls run here and the results go back to it, round after round, until
--- it answers with text only.
local function runOllama(opts, model)
  local url = vim.g.pure_ollama_url or 'http://localhost:11434'
  local session_id = opts.resume or tostring(vim.uv.hrtime())
  local messages = {}

  local tools, enabled = ollamaTools(opts.tools)
  if no_tools[model] then tools = {} end

  if opts.resume and ollama_sessions[opts.resume] then
    messages = vim.deepcopy(ollama_sessions[opts.resume].messages or {})
  elseif #tools > 0 then
    -- Where the tools work, so relative paths mean what the model thinks.
    local where = { opts.cwd or vim.fn.getcwd() }
    vim.list_extend(where, opts.dirs or {})
    table.insert(messages, { role = 'system', content = 'You can use tools to read'
      .. ((enabled.edit_file or enabled.write_file) and ' and change' or '') .. ' files. '
      .. 'Relative paths are relative to ' .. where[1] .. '. You may only use these folders: '
      .. table.concat(where, ', ') .. '. Use the tools only when the request needs what a file '
      .. 'holds, instead of guessing it; answer anything else (general knowledge, the text already '
      .. 'given to you) directly, without tools. When done, answer with text only.' })
      -- "Only when needed": told just to prefer tools, qwen2.5-coder searched
      -- the files eleven times for "the capital of France" and gave up.
  end
  table.insert(messages, { role = 'user', content = opts.prompt })

  local text, round_text = {}, {}
  local finished, stopped = false, false
  local queued, flush_pending = {}, false
  local obj
  local id = tostring(vim.uv.hrtime())
  local rounds = 0

  local function flush()
    flush_pending = false
    if #queued == 0 or not opts.on_text then return end
    local chunk = table.concat(queued)
    queued = {}
    opts.on_text(chunk)
  end
  local function emit(piece)
    table.insert(queued, piece)
    if not flush_pending then
      flush_pending = true
      vim.defer_fn(function() if not finished then flush() end end, 60)
    end
  end

  -- Thinking is never part of the answer. It used to be emitted as answer
  -- text when a chunk had no content, so reasoning models wrote their whole
  -- reasoning into the buffer. Now it goes to opts.on_thinking (shown dimmed,
  -- never written; see showThinking). Two ways models send it: Ollama's
  -- separate `thinking` field, or <think>...</think> inside the content
  -- (older Ollama, some models), split out here even across chunks.
  local inside, carry = false, ''
  --- How much of the end of `s` could be the start of `tag`, so a tag split
  --- between two chunks is not missed.
  local function partialTail(s, tag)
    for k = math.min(#s, #tag - 1), 1, -1 do
      if s:sub(-k) == tag:sub(1, k) then return k end
    end
    return 0
  end
  local function think(piece)
    if piece ~= '' and opts.on_thinking then opts.on_thinking(piece) end
  end
  -- A round's text that may be a tool call written as text (textToolCalls)
  -- is held back, not shown, until the round ends and says which it is:
  -- nil not decided yet, true holding, false shown as it comes.
  local holding, held = nil, {}
  local function show(piece)
    table.insert(text, piece)
    emit(piece)
  end
  local function release()
    holding = false
    for _, p in ipairs(held) do show(p) end
    held = {}
  end
  local function answer(piece)
    if piece == '' then return end
    table.insert(round_text, piece)
    if #tools == 0 or holding == false then return show(piece) end
    table.insert(held, piece)
    local so_far = vim.trim(table.concat(round_text))
    if so_far == '' then return end
    local function starts(prefix)
      return so_far:sub(1, #prefix) == prefix or prefix:sub(1, #so_far) == so_far
    end
    if so_far:match('^[%[{]') or starts('```') or starts('<tool_call>') then
      holding = true
    else
      release()
    end
  end
  local function content(s, final)
    s = carry .. s
    carry = ''
    while s ~= '' do
      local tag = inside and '</think>' or '<think>'
      local at = s:find(tag, 1, true)
      local take = inside and think or answer
      if at then
        take(s:sub(1, at - 1))
        s = s:sub(at + #tag)
        inside = not inside
      else
        local keep = final and 0 or partialTail(s, tag)
        take(s:sub(1, #s - keep))
        carry = s:sub(#s - keep + 1)
        s = ''
      end
    end
  end

  local function finish(err, full)
    if finished then return end
    content('', true) -- a partial "<thi" held back is plain text after all
    flush()
    finished = true
    running[id] = nil
    if stopped then return opts.on_done('stopped', table.concat(text), session_id) end
    if not err and (opts.keep or opts.resume) then
      ollama_sessions[session_id] = { messages = messages }
    else
      ollama_sessions[session_id] = nil
    end
    opts.on_done(err, full or table.concat(text), session_id)
  end

  --- One streamed /api/chat call. At its end the tool calls run and the next
  --- round starts, or the answer is done.
  local function request()
    rounds = rounds + 1
    round_text = {}
    holding, held = nil, {}
    local calls, ollama_err, pending, err_text = {}, nil, '', {}

    local function event(line)
      line = line:gsub('\r$', '')
      if vim.trim(line) == '' then return end
      local ok, ev = pcall(vim.json.decode, line)
      if not ok or type(ev) ~= 'table' then return end
      if ev.error then
        ollama_err = ev.error
        return
      end
      local m = ev.message
      if type(m) ~= 'table' then return end
      if type(m.thinking) == 'string' then think(m.thinking) end
      if type(m.content) == 'string' then content(m.content) end
      if type(m.tool_calls) == 'table' then vim.list_extend(calls, m.tool_calls) end
    end

    local payload = vim.json.encode({
      model = model,
      messages = messages,
      stream = true,
      tools = #tools > 0 and tools or nil,
      -- num_ctx: without it Ollama runs with its small default context and
      -- silently drops the start of a long prompt (the rules, the file),
      -- which is why local models "forgot" what to do. num_predict -1: no
      -- cap on the answer, so a model may think for as long as it needs.
      options = {
        num_ctx = vim.g.pure_ollama_num_ctx or 32768,
        num_predict = -1,
      },
    })

    local ok, res_obj = pcall(vim.system, {
      'curl', '-s', '-N', '-X', 'POST', url .. '/api/chat',
      '-H', 'Content-Type: application/json', '-d', '@-',
    }, {
      stdin = payload,
      stdout = function(_, data)
        if not data then return end
        vim.schedule(function()
          if finished then return end
          pending = pending .. data
          local start = 1
          while true do
            local nl = pending:find('\n', start, true)
            if not nl then break end
            event(pending:sub(start, nl - 1))
            start = nl + 1
          end
          pending = pending:sub(start)
        end)
      end,
      stderr = function(_, data) if data then table.insert(err_text, data) end end,
    }, function(res)
      vim.schedule(function()
        if finished then return end
        if pending ~= '' then event(pending) end
        if stopped then return finish('stopped') end

        -- A model without tool support: asked again, once, without tools.
        if ollama_err and #tools > 0
            and tostring(ollama_err):lower():find('does not support tools', 1, true) then
          no_tools[model] = true
          tools = {}
          vim.notify(model .. ' cannot use tools: it answers without reading or changing files',
            vim.log.levels.WARN)
          rounds = rounds - 1
          return request()
        end
        if ollama_err then return finish('Ollama: ' .. tostring(ollama_err)) end
        if res.code ~= 0 then
          local why = vim.trim(table.concat(err_text))
          if res.code == 7 then
            why = 'Could not connect to Ollama at ' .. url .. ' (is Ollama running?)'
          elseif why == '' then
            why = 'curl exited with code ' .. res.code
          end
          return finish(why)
        end

        content('', true)
        local said = table.concat(round_text)
        local history_text = said
        if #calls == 0 and holding then
          -- Held text: a tool call written as text runs as one; anything
          -- else was an answer after all and is shown now.
          local written = textToolCalls(said, enabled)
          if written then
            calls = written
            -- Kept as that one call only: with the whole written plan in the
            -- history, the model took its guessed later steps as done.
            history_text = ''
          else
            release()
          end
        elseif holding then
          held = {} -- text before real tool calls: not part of the answer
        end
        table.insert(messages, { role = 'assistant', content = history_text, tool_calls = #calls > 0 and calls or nil })
        if #calls == 0 then
          -- The answer is the last round's text: "let me read the file",
          -- said before a tool call, is not part of it (in <leader>ai it
          -- would have been written into the buffer).
          return finish(nil, said ~= '' and said or table.concat(text))
        end
        if rounds >= MAX_ROUNDS then
          return finish('Ollama: stopped after ' .. MAX_ROUNDS .. ' rounds of tool calls')
        end
        for _, call in ipairs(calls) do
          local fn = call['function'] or {}
          local args = fn.arguments
          if type(args) == 'string' then
            local okj, decoded = pcall(vim.json.decode, args)
            args = okj and decoded or {}
          end
          if opts.on_tool then opts.on_tool(CLAUDE_NAME[fn.name] or fn.name) end
          local result = enabled[fn.name] and runTool(fn.name, args, opts)
            or ('Error: tool ' .. tostring(fn.name) .. ' is not available here')
          table.insert(messages, { role = 'tool', tool_name = fn.name, content = result })
        end
        -- A blank line between rounds' text, as runClaude puts between messages.
        if #text > 0 then show('\n\n') end
        request()
      end)
    end)
    if ok then
      obj = res_obj
    else
      finish('Could not run curl for Ollama: ' .. tostring(res_obj))
    end
  end

  running[id] = function()
    stopped = true
    if obj then kill(obj) end
  end
  local stop = running[id]
  request()
  return stop
end

--- Run one request. `opts`: prompt, tools (list), cwd, resume (session id),
--- keep (keep the session, to follow up), model, dirs (more folders it may
--- work in), write (edits files: accepted without asking), on_text(chunk),
--- on_tool(name), on_done(err, text, session). Callbacks run on the main
--- loop. Returns a function that stops it.
-- -----------------------------------------------------------------------------
--  User context
-- -----------------------------------------------------------------------------
--  A markdown file about the user that every request gets (Improvment.md in
--  the vault asked for it), whatever the model. It is kept out of every git
--  repository for privacy: in Neovim's data folder, not in this config or
--  the vault, unless vim.g.pure_llm_user_context points elsewhere.
--
--  The model can add to it: what it puts in <remember>...</remember> in its
--  answer is appended to the file (dated) and taken out of the answer, so it
--  is never shown or written into a buffer. vim.g.pure_llm_memory = false
--  turns that off (the file is still read). <leader>au opens it.

local function userContextFile()
  local p = vim.g.pure_llm_user_context
  if p == false then return nil end
  return vim.fs.normalize(vim.fn.expand(p or (vim.fn.stdpath('data') .. '/llm_user.md')))
end
M.userContextFile = userContextFile

--- The prompt's first part: the file's content and how to add to it.
local function userContextBlock()
  local path = userContextFile()
  if not path then return '' end
  local ok, lines = pcall(vim.fn.readfile, path)
  local text = ok and vim.trim(table.concat(lines, '\n')) or ''
  local parts = {}
  if text ~= '' then
    table.insert(parts, '<user_context>\nWhat the user wrote (or asked you to remember) about themselves; '
      .. 'use it when it is relevant:\n' .. text .. '\n</user_context>')
  end
  if vim.g.pure_llm_memory ~= false then
    table.insert(parts, 'If the user tells you something lasting about themselves that would help in later '
      .. 'requests (a preference, their work, how they like answers), add it at the very end of your answer '
      .. 'as <remember>one short sentence</remember>. It is saved to their context file and hidden from the '
      .. 'answer. Do not use it for anything else, and not for things already in <user_context>.')
  end
  return #parts > 0 and (table.concat(parts, '\n\n') .. '\n\n') or ''
end

--- Append `facts` to the user context file, one dated line each.
local function remember(facts)
  local path = userContextFile()
  if not path or #facts == 0 then return end
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local lines = {}
  if not vim.uv.fs_stat(path) then
    lines = { '# About me', '', 'Read by every LLM request from Neovim (pure/claude.lua). Edit freely.', '' }
  end
  for _, f in ipairs(facts) do table.insert(lines, ('- %s (%s)'):format(f, os.date('%Y-%m-%d'))) end
  vim.fn.writefile(lines, path, 'a')
  vim.notify('Remembered: ' .. table.concat(facts, '; '))
end

--- `text` without its <remember> tags, and what they held.
local function takeRemembered(text)
  local facts = {}
  text = (text or ''):gsub('%s*<remember>(.-)</remember>', function(f)
    f = vim.trim(f:gsub('%s+', ' '))
    if f ~= '' then table.insert(facts, f) end
    return ''
  end)
  return text, facts
end

--- A stream filter that keeps <remember>...</remember> out of what is shown,
--- even when a tag is split between two chunks. `feed(s)` returns what may be
--- shown now; `feed('', true)` the rest at the end.
local function rememberFilter()
  local inside, carry = false, ''
  local function partialTail(s, tag)
    for k = math.min(#s, #tag - 1), 1, -1 do
      if s:sub(-k) == tag:sub(1, k) then return k end
    end
    return 0
  end
  return function(s, final)
    s = carry .. s
    carry = ''
    local out = {}
    while s ~= '' do
      local tag = inside and '</remember>' or '<remember>'
      local at = s:find(tag, 1, true)
      if at then
        if not inside then table.insert(out, s:sub(1, at - 1)) end
        s = s:sub(at + #tag)
        inside = not inside
      else
        local keep = final and 0 or partialTail(s, tag)
        if not inside then table.insert(out, s:sub(1, #s - keep)) end
        carry = s:sub(#s - keep + 1)
        s = ''
      end
    end
    return table.concat(out)
  end
end

local function run(opts)
  local active = parseModel(opts.model)
  -- The user context goes with every new conversation (a follow-up's
  -- session already has it), and <remember> is taken out of the answer.
  opts = vim.tbl_extend('force', {}, opts)
  if not opts.resume then opts.prompt = userContextBlock() .. opts.prompt end
  local filter = rememberFilter()
  local on_text, on_done = opts.on_text, opts.on_done
  if on_text then
    opts.on_text = function(s)
      local shown = filter(s)
      if shown ~= '' then on_text(shown) end
    end
  end
  opts.on_done = function(err, text, session)
    if on_text then
      local rest = filter('', true)
      if rest ~= '' then on_text(rest) end
    end
    local clean, facts = takeRemembered(text)
    if not err and vim.g.pure_llm_memory ~= false then remember(facts) end
    return on_done(err, clean, session)
  end
  if active.backend == 'ollama' then
    return runOllama(opts, active.model)
  elseif active.backend == 'agy' then
    return runAgy(opts, active.model)
  else
    return runClaude(opts, active.model)
  end
end

function M.stop()
  local n = 0
  for _, stop in pairs(running) do
    stop()
    n = n + 1
  end
  local m_label = modelLabel()
  vim.notify(n > 0 and (m_label .. ': stopped') or (m_label .. ': nothing running'))
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

local function addHistory(kind, question, answer, session, model_spec)
  table.insert(history, {
    kind = kind,
    question = question,
    answer = answer,
    session = session,
    model = modelLabel(model_spec),
    -- The model itself, not only its label: a follow-up on an answer reached
    -- with [ / ] in the window goes to the model that gave it.
    spec = model_spec,
    time = os.time(),
  })
  if #history > 50 then table.remove(history, 1) end
end

--- A window for an answer: `question` on top, then the answer as it comes.
--- Returns an object to write into it.
local function answerWindow(title, model_spec)
  local m_label = modelLabel(model_spec)
  local win, buf = require('configs.functions').createWindow(' ' .. m_label .. ' · ' .. title .. ' ', 0.7)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'wipe'
  vim.b[buf].pure_mdview = true
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  vim.wo[win].conceallevel = 2
  local w = { win = win, buf = buf, model = model_spec }

  function w.valid() return vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) end
  function w.title(s)
    if w.valid() then pcall(vim.api.nvim_win_set_config, win, { title = ' ' .. modelLabel(w.model) .. ' · ' .. s .. ' ' }) end
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

--- A model's thinking as virtual lines (dimmed, never text: y does not copy
--- it, and it is never written into a buffer). `max`: only the last lines.
--- vim.g.pure_llm_thinking: 'show' (default) shows it while the model
--- thinks, 'hide' never does.
local function thinkingLines(text, max)
  local lines = vim.split(vim.trim(text), '\n', { plain = true })
  if max and #lines > max then lines = vim.list_slice(lines, #lines - max + 1, #lines) end
  local out = {}
  for _, l in ipairs(lines) do table.insert(out, { { '  ┊ ' .. l, 'Comment' } }) end
  return out
end

--- A dimmed status line under 0-based `row` of `buf` with the seconds since
--- it started, ticking every second: "  qwen3.5:9b is writing… 12s". Added
--- (Improvment.md) so every LLM command working in the buffer shows how long
--- it has been going, as the <leader>aa window's title already did.
--- `s.state` is the text before the seconds, `s.extra` more virtual lines
--- under it (the streamed text, the thinking); `s.draw()` after changing
--- them; `s.stop()` removes it. `s.id` is the extmark, which follows edits.
local function statusMark(buf, row, state)
  local t0 = vim.uv.hrtime()
  local s = { state = state }
  s.id = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {})
  local timer = vim.uv.new_timer()
  function s.draw()
    if not s.id or not vim.api.nvim_buf_is_valid(buf) then return end
    local secs = math.floor((vim.uv.hrtime() - t0) / 1e9)
    local lines = { { { ('  %s %ds'):format(s.state, secs), 'Comment' } } }
    vim.list_extend(lines, s.extra or {})
    local at = vim.api.nvim_buf_get_extmark_by_id(buf, ns, s.id, {})
    if at[1] then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, at[1], 0, { id = s.id, virt_lines = lines })
    end
  end
  function s.stop()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if s.id and vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_del_extmark, buf, ns, s.id) end
    s.id = nil
  end
  timer:start(1000, 1000, vim.schedule_wrap(s.draw))
  s.draw()
  return s
end

--- The thinking of one answer in the window `w`, above the answer's first
--- line (`row`). Live: its last lines. Once the answer comes: one line,
--- "▸ thought for 12s", that t in the window opens and closes like a fold.
--- Added so thinking is visible without being part of the answer.
local function showThinking(w, row)
  local th = { text = '', open = false, answered = false }
  local mark
  function th.draw()
    if not w.valid() or th.text == '' then return end
    local hide = vim.g.pure_llm_thinking == 'hide'
    local lines
    if th.open then
      lines = thinkingLines(th.text)
      table.insert(lines, 1, { { '▾ thinking (t: hide)', 'Comment' } })
    elseif th.answered then
      if hide then return end
      lines = { { { ('▸ thought for %s (t: show)'):format(th.secs or '?'), 'Comment' } } }
    else
      if hide then return end
      lines = thinkingLines(th.text, 12)
    end
    mark = vim.api.nvim_buf_set_extmark(w.buf, ns, row, 0,
      { id = mark, virt_lines = lines, virt_lines_above = true })
  end
  function th.add(s) th.text = th.text .. s; th.draw() end
  function th.answer(secs)
    if th.answered then return end
    th.answered, th.secs = true, secs
    th.draw()
  end
  w.thoughts = w.thoughts or {}
  table.insert(w.thoughts, th)
  return th
end

--- Stream one request into the window `w`.
local function askInto(w, question, prompt, opts)
  local answer = {}
  -- The answer starts on the window's last line; its thinking goes above it.
  local th = w.valid() and showThinking(w, vim.api.nvim_buf_line_count(w.buf) - 1) or nil
  local stopped = false
  -- The seconds since the question went, next to what the model is doing.
  local t0, state = vim.uv.hrtime(), 'thinking…'
  local function elapsed(decimals)
    local secs = (vim.uv.hrtime() - t0) / 1e9
    return decimals and ('%.1fs'):format(secs) or ('%ds'):format(math.floor(secs))
  end
  local timer = vim.uv.new_timer()
  local function setState(s)
    state = s
    w.title(state .. ' ' .. elapsed())
  end
  local function stopTimer()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  timer:start(1000, 1000, vim.schedule_wrap(function()
    if not w.valid() then return stopTimer() end
    w.title(state .. ' ' .. elapsed())
  end))
  setState('thinking…')
  local extra = opts.extra or {}
  local m_label = modelLabel(extra.model)
  local stop = run({
    prompt = prompt,
    tools = extra.tools or READ_TOOLS,
    model = extra.model,
    dirs = extra.dirs,
    write = extra.write,
    cwd = opts.cwd,
    resume = opts.session,
    keep = true,
    on_tool = function(name) setState(name == 'Read' and 'reading…' or 'searching…') end,
    on_thinking = function(s)
      if th then th.add(s) end
    end,
    on_text = function(s)
      table.insert(answer, s)
      if state ~= 'writing…' then
        if th then th.answer(elapsed()) end
        setState('writing…')
      end
      w.append(s)
    end,
    on_done = function(err, text, session)
      stopTimer()
      if err then
        if not stopped then
          w.append('\n\n> **Error:** ' .. err:gsub('\n', '\n> ') .. '\n')
          if not w.valid() then vim.notify(m_label .. ': ' .. err, vim.log.levels.ERROR) end
        end
        w.title((stopped and 'stopped' or 'error') .. ' ' .. elapsed(true))
        return
      end
      if th then th.answer(elapsed()) end
      -- A model may finish its tool calls (an edit) without a word; the
      -- window said nothing at all then.
      if #answer == 0 then w.append(vim.trim(text or '') ~= '' and text or '_(no text answer)_') end
      w.append('\n')
      -- This answer's time, small at its end (not text: y does not copy it);
      -- the window's total, follow-ups included, in the title.
      w.total = (w.total or 0) + (vim.uv.hrtime() - t0) / 1e9
      if w.valid() then
        -- On the answer's last line of text: the empty line after it is
        -- rewritten when a follow-up is appended, and would lose the mark.
        local last_row = math.max(vim.api.nvim_buf_line_count(w.buf) - 2, 0)
        pcall(vim.api.nvim_buf_set_extmark, w.buf, ns, last_row, 0, {
          virt_text = { { elapsed(true), 'Comment' } }, virt_text_pos = 'right_align',
        })
      end
      w.title(opts.kind .. (' %.1fs'):format(w.total) .. ' · [ ]: older/newer, a: follow up, y: copy, q: close')
      w.session = session
      w.answer = text
      addHistory(opts.kind, question, text, session, extra.model)
      w.index = #history -- where [ / ] in the window start from
      -- Chat-like: the follow-up box takes the cursor once the answer is
      -- in, if you are still in the answer (never pulled from elsewhere).
      if w.focusInput and w.valid() and vim.api.nvim_get_current_win() == w.win then w.focusInput() end
      if extra.write then vim.cmd('silent! checktime') end
    end,
  })
  w.stop = function() stopped = true; stop() end
end

local function openAnswer(kind, question, prompt, cwd, preset, extra)
  local w = answerWindow(kind, extra and extra.model)
  vim.api.nvim_buf_set_lines(w.buf, 0, -1, false, { '## ' .. (question:gsub('\n', ' ')), '', '' })
  if preset then
    vim.api.nvim_buf_set_lines(w.buf, 2, -1, false, vim.split(preset, '\n', { plain = true }))
  end

  local o = { buffer = w.buf, nowait = true, silent = true }
  local m_label = modelLabel(extra and extra.model)
  vim.keymap.set('n', 'q', function() pcall(vim.api.nvim_win_close, w.win, true) end, o)
  vim.keymap.set('n', '<Esc>', function() pcall(vim.api.nvim_win_close, w.win, true) end, o)
  vim.keymap.set('n', 'y', function()
    if not w.answer then return end
    vim.fn.setreg('+', w.answer)
    vim.fn.setreg('"', w.answer)
    vim.notify(m_label .. ': answer copied')
  end, o)
  -- t opens / closes the thinking of every answer in the window, like a fold.
  vim.keymap.set('n', 't', function()
    local thoughts = w.thoughts or {}
    if #thoughts == 0 then return vim.notify(m_label .. ': no thinking to show') end
    local open = not thoughts[#thoughts].open
    for _, th in ipairs(thoughts) do th.open = open; th.draw() end
  end, o)
  local function followUp(q)
    if not q or vim.trim(q) == '' or not w.valid() then return end
    if not w.session then return vim.notify(m_label .. ': wait for the answer first') end
    w.append('\n---\n\n## ' .. q .. '\n\n')
    -- To the model of the answer shown (it changes with [ / ]).
    local ex = vim.tbl_extend('force', extra or {}, { model = w.model })
    askInto(w, q, q, { cwd = cwd, session = w.session, kind = kind, extra = ex })
  end

  -- The follow-up box: one line docked under the answer, always there, as
  -- in a chat (Improvment.md). It replaced a vim.ui.input prompt that 'a'
  -- opened at the top of the screen and that went away after each question.
  --   in the box     Enter sends; Esc goes up to the answer; <C-u> / <C-d>
  --                  scroll the answer without leaving the box
  --   in the answer  a or i go down to the box
  -- The answer window gives up the box's 3 rows (the line and its border).
  local cfg = vim.api.nvim_win_get_config(w.win)
  local row = type(cfg.row) == 'table' and cfg.row[false] or cfg.row
  local col = type(cfg.col) == 'table' and cfg.col[false] or cfg.col
  local height = math.max(cfg.height - 3, 3)
  vim.api.nvim_win_set_config(w.win, { relative = 'editor', row = row, col = col, height = height, width = cfg.width })
  local ibuf = vim.api.nvim_create_buf(false, true)
  vim.bo[ibuf].bufhidden = 'wipe'
  -- No completion in the box: <CR> would take a suggestion instead of sending.
  vim.bo[ibuf].complete = ''
  vim.bo[ibuf].omnifunc = ''
  local iwin = vim.api.nvim_open_win(ibuf, false, {
    relative = 'editor', row = row + height + 2, col = col, width = cfg.width, height = 1,
    style = 'minimal', border = 'rounded',
    title = ' Follow up · Enter: send · Esc: to the answer ', title_pos = 'left',
  })
  w.input = { win = iwin, buf = ibuf }
  local iopts = { buffer = ibuf, nowait = true, silent = true }
  local function send()
    local q = vim.trim(vim.api.nvim_buf_get_lines(ibuf, 0, 1, false)[1] or '')
    if q == '' then return end
    if not w.session then return vim.notify(m_label .. ': wait for the answer first') end
    vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, { '' })
    followUp(q)
  end
  vim.keymap.set({ 'i', 'n' }, '<CR>', send, iopts)
  vim.keymap.set('i', '<Esc>', function()
    vim.cmd('stopinsert')
    if w.valid() then vim.api.nvim_set_current_win(w.win) end
  end, iopts)
  vim.keymap.set('n', '<Esc>', function() if w.valid() then vim.api.nvim_set_current_win(w.win) end end, iopts)
  local function scroll(keys)
    return function()
      if w.valid() then
        vim.api.nvim_win_call(w.win, function() vim.cmd('normal! ' .. vim.keycode(keys)) end)
      end
    end
  end
  vim.keymap.set({ 'i', 'n' }, '<C-u>', scroll('<C-u>'), iopts)
  vim.keymap.set({ 'i', 'n' }, '<C-d>', scroll('<C-d>'), iopts)
  --- Into the box, typing.
  function w.focusInput()
    if vim.api.nvim_win_is_valid(iwin) then
      vim.api.nvim_set_current_win(iwin)
      vim.cmd('startinsert!')
    end
  end
  vim.keymap.set('n', 'a', w.focusInput, o)
  vim.keymap.set('n', 'i', w.focusInput, o)
  -- One goes, both go.
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(iwin), once = true,
    callback = function() vim.schedule(function() pcall(vim.api.nvim_win_close, w.win, true) end) end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(w.win), once = true,
    callback = function() vim.schedule(function() pcall(vim.api.nvim_win_close, iwin, true) end) end,
  })

  -- [ / ]: the previous / next answer of this session's history, in this
  -- same window, without going through <leader>ah (Improvment.md). A follow-up
  -- (a) then continues the answer shown.
  local function showEntry(i)
    local h = history[i]
    if not h then return end
    if w.stop and not w.answer then return vim.notify(m_label .. ': wait for the answer first') end
    vim.api.nvim_buf_clear_namespace(w.buf, ns, 0, -1)
    w.thoughts = {}
    local lines = { '## ' .. (h.question:gsub('\n', ' ')), '' }
    vim.list_extend(lines, vim.split(h.answer or '', '\n', { plain = true }))
    vim.api.nvim_buf_set_lines(w.buf, 0, -1, false, lines)
    pcall(vim.api.nvim_win_set_cursor, w.win, { 1, 0 })
    w.index, w.session, w.answer, w.model, w.total = i, h.session, h.answer, h.spec, nil
    w.title(('%s %d/%d · %s · [ ]: older/newer, %sy: copy, q: close'):format(h.kind, i, #history,
      os.date('%H:%M', h.time), h.session and 'a: follow up, ' or ''))
  end
  vim.keymap.set('n', '[', function()
    local i = (w.index or (#history + 1)) - 1
    if i < 1 then return vim.notify(m_label .. ': no older answer') end
    showEntry(i)
  end, o)
  vim.keymap.set('n', ']', function()
    local i = (w.index or #history) + 1
    if i > #history then return vim.notify(m_label .. ': no newer answer') end
    showEntry(i)
  end, o)
  w.showEntry = showEntry
  -- Closing the window stops a request still running: nobody would see it.
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(w.win),
    once = true,
    callback = function() if w.stop and not w.answer then w.stop() end end,
  })

  if prompt then askInto(w, question, prompt, { cwd = cwd, kind = kind, extra = extra }) end
  return w
end

--- Ask about the buffer; the answer shows in a window.
function M.ask(question, range)
  local buf = vim.api.nvim_get_current_buf()
  range = range or selection()
  local function go(q)
    if q == nil then return end -- cancelled
    if vim.trim(q) == '' then
      -- Enter on an empty question: the last answer again, where [ / ]
      -- reach the ones before it (no need for <leader>ah).
      if #history == 0 then return vim.notify(modelLabel() .. ': no answers yet') end
      local w = openAnswer(history[#history].kind, history[#history].question, nil, workdir(buf))
      return w.showEntry(#history)
    end
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
  text = text:gsub('<think>.-</think>%s*', '')
  local lines = vim.split(vim.trim(text), '\n', { plain = true })
  if #lines >= 2 and lines[1]:match('^%s*```') and lines[#lines]:match('^%s*```%s*$') then
    return vim.list_slice(lines, 2, #lines - 1)
  end
  return vim.split((text:gsub('%s+$', '')), '\n', { plain = true })
end

--- Write into the buffer: at the cursor, or over the selection.
--- `extra` (actions): tools, model, dirs, write, cwd, label.
function M.write(instruction, range, extra)
  extra = extra or {}
  local buf = vim.api.nvim_get_current_buf()
  range = range or selection()
  local function go(q)
    if not q or vim.trim(q) == '' then return end
    if not extra.label then last = { kind = 'write', instruction = q } end
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
    local m_label = modelLabel(extra.model)
    -- The ghost lines: a status with the seconds on top ("… is writing… 12s",
    -- see statusMark), then the thinking or the text as it comes.
    local ghost = statusMark(buf, ghost_row, m_label .. ' is waiting…')
    local streamed, thought = '', ''
    local function clear()
      ghost.stop()
      for _, id in ipairs({ a_mark, hl }) do
        if id then pcall(vim.api.nvim_buf_del_extmark, buf, ns, id) end
      end
    end

    run({
      prompt = prompt,
      cwd = extra.cwd or workdir(buf),
      tools = extra.tools,
      model = extra.model,
      dirs = extra.dirs,
      write = extra.write,
      on_tool = function(name)
        if streamed ~= '' then return end
        ghost.state = m_label .. (name == 'Read' and ' is reading…' or ' is searching…')
        ghost.draw()
      end,
      -- Thinking only in the ghost lines while no answer has come: it is never
      -- written into the buffer (on_done inserts the answer text only).
      on_thinking = function(s)
        thought = thought .. s
        if streamed ~= '' then return end
        ghost.state = m_label .. ' is thinking…'
        ghost.extra = vim.g.pure_llm_thinking ~= 'hide' and thinkingLines(thought, 8) or nil
        ghost.draw()
      end,
      on_text = function(s)
        streamed = streamed .. s
        local shown = {}
        for _, l in ipairs(vim.split(streamed, '\n', { plain = true })) do
          table.insert(shown, { { l == '' and ' ' or l, 'Comment' } })
        end
        ghost.state = m_label .. ' is writing…'
        ghost.extra = shown
        ghost.draw()
      end,
      on_done = function(err, text)
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local at = vim.api.nvim_buf_get_extmark_by_id(buf, ns, a_mark, {})[1]
        clear()
        if err == 'stopped' then return end
        if err then return vim.notify(m_label .. ': ' .. err, vim.log.levels.ERROR) end
        if not vim.bo[buf].modifiable then
          return vim.notify(m_label .. ': the buffer is not modifiable', vim.log.levels.WARN)
        end
        local lines = unfence(text)
        if not at then return end
        if below then
          vim.api.nvim_buf_set_lines(buf, at + 1, at + 1, false, lines)
        else
          vim.api.nvim_buf_set_lines(buf, at, at + count, false, lines)
        end
        addHistory('write', extra.label or q, text, nil, extra.model)
        if extra.write then vim.cmd('silent! checktime') end
        vim.notify(('%s: %d line%s written (u undoes)'):format(m_label, #lines, #lines == 1 and '' or 's'))
      end,
    })
  end
  if instruction then return go(instruction) end
  vim.ui.input({ prompt = range and ' Rewrite the selection: ' or ' Write here: ' }, go)
end

--- The last request again, with the context of now.
function M.repeatLast()
  if not last then return vim.notify(modelLabel() .. ': nothing to repeat yet') end
  local range = selection()
  if last.kind == 'action' then
    local a = M._readAction(last.action)
    if not a then return vim.notify(modelLabel() .. ': the last action is gone') end
    return M.runAction(a, { buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win(), range = range })
  end
  if last.kind == 'write' then return M.write(last.instruction, range) end
  if last.kind == 'review' then return M.review(range) end
  M.ask(last.instruction, range)
end

--- Past answers of this session; picking one opens it (with follow-ups).
function M.history()
  local items = {}
  for i = #history, 1, -1 do table.insert(items, history[i]) end
  if #items == 0 then return vim.notify('Claude/LLM: no answers yet') end
  vim.ui.select(items, {
    prompt = 'Claude / Ollama answers',
    format_item = function(h)
      return ('%s  %-6s [%s] %s'):format(os.date('%H:%M', h.time), h.kind, h.model or 'Claude', (h.question:gsub('\n', ' ')))
    end,
  }, function(h)
    if not h then return end
    local w = openAnswer(h.kind, h.question, nil, vim.fn.getcwd(), h.answer)
    -- At its place in the history, so [ / ] in the window go on from it.
    for i, e in ipairs(history) do
      if e == h then return w.showEntry(i) end
    end
  end)
end

-- -----------------------------------------------------------------------------
--  Actions
-- -----------------------------------------------------------------------------
--  Requests you make often, one markdown file each, in a folder of the vault
--  (`claude/` by default, vim.g.pure_claude_actions): <leader>ax lists
--  them, and the one picked runs with the context of now (the note, the
--  selection, the cursor). A file is an action when its frontmatter has a
--  description; other files of the folder are left alone.
--
--    ---
--    description: Revisar ortografia e gramática
--    output: replace         insert | replace | window | notify
--    tools: Read, Grep       what Claude may use (Edit, Write, Bash: files)
--    dirs: vault, ~/Downloads   where it may change files
--    confirm: auto           auto (only outside git) | always | never
--    model: haiku            this action only
--    key: <leader>a1         its own key
--    context: stats.lua      more context: the text() of a Lua file of this
--                            folder, or of a module lua/pure/<name>
--    ---
--    The request. $ARGUMENTS is asked for when the action runs.
--
--  The format is the one of Claude Code's own commands (.claude/commands),
--  whose extra keys are ignored here.

local WRITE_TOOLS = { Edit = true, Write = true, MultiEdit = true, NotebookEdit = true, Bash = true }

local AGENT_RULES = 'You are running an action started from Neovim, with nobody watching: do the task '
  .. 'with your tools, in the folders you were given, without asking questions. The user\'s current '
  .. 'buffer is given as context. When you are done, answer ONLY with a short summary (at most 5 lines, '
  .. 'in the language of the request) of what you did: files created, changed or moved.'

--- The actions folder: `claude` (any case) in the vault, or an absolute path.
local function actionsDir()
  local name = vim.g.pure_claude_actions or 'claude'
  name = vim.fn.expand(name)
  if name:match('^/') or name:match('^%a:[/\\]') then
    return vim.fn.isdirectory(name) == 1 and vim.fs.normalize(name) or nil, name
  end
  local ok, zet = pcall(require, 'pure.zettelkasten')
  local vault = ok and zet.vaultPath() or nil
  if not vault or vim.fn.isdirectory(vault) == 0 then return nil end
  vault = vim.fs.normalize(vault)
  for entry, kind in vim.fs.dir(vault) do
    if kind == 'directory' and entry:lower() == name:lower() then return vault .. '/' .. entry, vault end
  end
  return nil, vault .. '/' .. name
end

--- `a, b` or `[a, b]` as a list.
local function list(value)
  if not value or value == '' then return nil end
  local out = {}
  for item in value:gsub('^%[', ''):gsub('%]$', ''):gmatch('[^,]+') do
    item = vim.trim(item):gsub('^["\']', ''):gsub('["\']$', '')
    if item ~= '' then table.insert(out, item) end
  end
  return out
end

--- The action in `path`, or nil when it has no description.
local function readAction(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines[1] or vim.trim(lines[1]) ~= '---' then return nil end
  local meta, body_start = {}, nil
  for i = 2, #lines do
    local l = lines[i]:gsub('\r$', '')
    if vim.trim(l) == '---' then
      body_start = i + 1
      break
    end
    local k, v = l:match('^([%w_-]+)%s*:%s*(.-)%s*$')
    if k then meta[k:lower()] = v:gsub('^["\'](.*)["\']$', '%1') end
  end
  if not body_start or not meta.description or meta.description == '' then return nil end
  local body = {}
  for i = body_start, #lines do table.insert(body, (lines[i]:gsub('\r$', ''))) end
  local tools = list(meta.tools or meta['allowed-tools'])
  local writes = false
  for _, t in ipairs(tools or {}) do
    if WRITE_TOOLS[t:match('^%a+')] then writes = true end
  end
  local output = (meta.output or ''):lower()
  if not ({ insert = true, replace = true, window = true, notify = true })[output] then
    output = writes and 'notify' or 'window'
  end
  return {
    path = path,
    name = vim.fn.fnamemodify(path, ':t:r'),
    description = meta.description,
    output = output,
    tools = tools,
    writes = writes,
    dirs = list(meta.dirs),
    confirm = (meta.confirm or 'auto'):lower(),
    model = meta.model ~= '' and meta.model or nil,
    key = meta.key ~= '' and meta.key or nil,
    context = list(meta.context),
    body = vim.trim(table.concat(body, '\n')),
  }
end

--- The extra context an action asks for (`context: stats.lua`): the text()
--- of each source, wrapped in a tag named after it (<stats>). A source is a
--- Lua file of the actions folder (read fresh each time: a personal script
--- lives with the actions, out of this configuration) or a module
--- lua/pure/<name>. One that fails says so instead of stopping the action.
local function extraContext(names)
  local parts = {}
  for _, name in ipairs(names or {}) do
    local tag = name:gsub('%.lua$', '')
    local ok, text = pcall(function()
      if name:match('%.lua$') then
        local dir = actionsDir()
        if not dir then error('no actions folder', 0) end
        return dofile(dir .. '/' .. name).text()
      end
      return require('pure.' .. name).text()
    end)
    if not ok then text = ('(%s unavailable: %s)'):format(name, tostring(text):match('^[^\n]*')) end
    table.insert(parts, ('<%s>\n%s\n</%s>'):format(tag, text, tag))
  end
  return table.concat(parts, '\n\n')
end

--- Every action of the folder, sorted by title (file name).
function M.actions()
  local dir = actionsDir()
  if not dir then return {} end
  local out = {}
  for name, kind in vim.fs.dir(dir, { depth = 4 }) do
    if kind == 'file' and name:match('%.md$') then
      local a = readAction(dir .. '/' .. name)
      if a then table.insert(out, a) end
    end
  end
  table.sort(out, function(x, y) return x.name:lower() < y.name:lower() end)
  return out
end

--- The folders an action may change files in: `vault`, `file` (the
--- current file's folder) or a path. The vault when none is given.
local function actionDirs(a, buf)
  local ok, zet = pcall(require, 'pure.zettelkasten')
  local vault = ok and zet.vaultPath() or nil
  local out = {}
  for _, d in ipairs(a.dirs or { 'vault' }) do
    local path
    if d == 'vault' then
      path = vault
    elseif d == 'file' then
      local name = vim.api.nvim_buf_get_name(buf)
      path = name ~= '' and vim.fs.dirname(name) or nil
    else
      path = vim.fn.expand(d)
    end
    if path and vim.fn.isdirectory(path) == 1 then table.insert(out, vim.fs.normalize(path)) end
  end
  if #out == 0 then table.insert(out, workdir(buf)) end
  return out
end

--- Whether to ask before an action that changes files runs.
local function mustConfirm(a, dirs)
  if not a.writes or a.confirm == 'never' then return false end
  if a.confirm == 'always' then return true end
  for _, d in ipairs(dirs) do
    if not vim.fs.root(d, '.git') then return true end
  end
  return false
end

--- Run action `a`. `ctx`: { buf, win, range } of where it was started.
function M.runAction(a, ctx)
  ctx = ctx or { buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win(), range = selection() }
  if vim.api.nvim_win_is_valid(ctx.win) and vim.api.nvim_win_get_buf(ctx.win) == ctx.buf then
    vim.api.nvim_set_current_win(ctx.win)
  end
  local buf = ctx.buf

  local function go(args)
    local body = a.body:gsub('%$ARGUMENTS', function() return args or '' end)
    if a.context then body = body .. '\n\n' .. extraContext(a.context) end
    local dirs = actionDirs(a, buf)
    if mustConfirm(a, dirs) then
      local choice = vim.fn.confirm(('Run "%s"?\nIt may change files in:\n  %s\nTools: %s'):format(a.description,
        table.concat(dirs, '\n  '), table.concat(a.tools or {}, ', ')), '&Yes\n&No', 1)
      if choice ~= 1 then return end
    end
    local extra = {
      tools = a.tools, model = a.model, write = a.writes,
      dirs = a.writes and vim.list_slice(dirs, 2) or nil,
      cwd = a.writes and dirs[1] or workdir(buf),
      label = a.description,
    }
    last = { kind = 'action', action = a.path }

    if a.output == 'insert' then
      return M.write(body, nil, extra)
    elseif a.output == 'replace' then
      local range = ctx.range or { 1, vim.api.nvim_buf_line_count(buf) }
      return M.write(body, range, extra)
    elseif a.output == 'window' then
      local prompt = ASK_RULES .. '\n\n' .. context(buf, ctx.range) .. '\n\nRequest: ' .. body
      return openAnswer(a.description, a.description, prompt, extra.cwd, nil, extra)
    end

    -- notify: Claude works on its own; its summary comes as a notification.
    -- Meanwhile a status with the seconds under the cursor line (statusMark),
    -- where it was started: before, nothing in the buffer said it was running.
    vim.notify('Claude: ' .. a.description .. '…')
    local used = {}
    local status = statusMark(buf, vim.api.nvim_win_get_cursor(0)[1] - 1,
      modelLabel(a.model) .. ' · ' .. a.description .. '…')
    run({
      prompt = AGENT_RULES .. '\n\n' .. context(buf, ctx.range) .. '\n\nTask: ' .. body,
      tools = a.tools or READ_TOOLS,
      model = a.model,
      write = a.writes,
      cwd = extra.cwd,
      dirs = extra.dirs,
      on_tool = function(name) used[name] = (used[name] or 0) + 1 end,
      on_done = function(err, text)
        status.stop()
        vim.cmd('silent! checktime')
        if err == 'stopped' then return end
        if err then return vim.notify('Claude: ' .. a.description .. ': ' .. err, vim.log.levels.ERROR) end
        addHistory('action', a.description, text)
        vim.notify('Claude · ' .. a.description .. '\n' .. vim.trim(text))
      end,
    })
  end

  if a.body:find('$ARGUMENTS', 1, true) then
    vim.ui.input({ prompt = ' ' .. a.description .. ': ' }, function(input)
      if input and vim.trim(input) ~= '' then go(input) end
    end)
  else
    go(nil)
  end
end

--- Pick an action and run it.
function M.pickAction()
  local ctx = { buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win(), range = selection() }
  local actions = M.actions()
  if #actions == 0 then
    local dir, where = actionsDir()
    if vim.fn.confirm(('No actions in %s yet (markdown files with a description in the frontmatter).'
      .. '\nCreate the examples there?'):format(dir or where or 'the vault'), '&Yes\n&No', 1) == 1 then
      M.examples()
    end
    return
  end
  local by_line, lines = {}, {}
  for _, a in ipairs(actions) do
    -- The action's title (its file name, as Obsidian shows it); the
    -- description is in the preview.
    local line = ('%s  [%s]\t%s'):format(a.name, a.output, a.path)
    by_line[line] = a
    table.insert(lines, line)
  end
  require('pure.fuzzyUtils').pickList(lines, {
    title = ' Claude actions ',
    -- No '%' in these: :terminal would expand it to the file name.
    fzf = [[--delimiter='\t' --with-nth=1 --preview 'cat {2}' --preview-window=right,wrap]],
  }, function(selection_line)
    local a = by_line[selection_line or '']
    if a then vim.schedule(function() M.runAction(a, ctx) end) end
  end)
end

--- Run the action whose file is `name` (without .md), with the context of
--- now: how keymaps.lua gives an action a key.
function M.runNamed(name)
  local ctx = { buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win(), range = selection() }
  for _, a in ipairs(M.actions()) do
    if a.name == name then return M.runAction(a, ctx) end
  end
  vim.notify(('Claude: no action "%s" in the actions folder'):format(name), vim.log.levels.WARN)
end

M._readAction = readAction

-- Actions with a `key:` get it (normal and visual mode).
local mapped = {}
function M.mapActionKeys()
  for lhs in pairs(mapped) do
    pcall(vim.keymap.del, { 'n', 'x' }, lhs)
  end
  mapped = {}
  for _, a in ipairs(M.actions()) do
    if a.key then
      local path = a.path
      vim.keymap.set({ 'n', 'x' }, a.key, function()
        local fresh = readAction(path)
        if fresh then M.runAction(fresh) end
      end, { desc = a.description })
      mapped[a.key] = true
    end
  end
end

local EXAMPLES = {
  ['Revisar texto.md'] = [==[
---
description: Revisar ortografia e gramática
output: replace
---
Revise a ortografia, a gramática e a pontuação do texto selecionado (ou da nota
inteira, sem seleção), em português do Brasil. Mantenha o meu estilo, o sentido e
toda a formatação markdown (links, listas, cabeçalhos). Não acrescente nada.
]==],
  ['Virar tarefas.md'] = [==[
---
description: Transformar o texto em tarefas
output: replace
---
Transforme o texto selecionado em uma lista de tarefas markdown (`- [ ] ...`),
uma ação concreta por linha, começando com um verbo. Subtarefas indentadas sob
a tarefa principal. Mantenha datas e nomes que aparecerem no texto.
]==],
  ['Sugerir links.md'] = [==[
---
description: Sugerir links para notas do vault
output: insert
tools: Read, Grep, Glob
---
Procure no vault (a pasta atual) notas relacionadas ao assunto da nota atual.
Escreva uma seção "## Relacionadas" com até 7 links no formato [[Nome da nota]],
cada um seguido de uma frase curta dizendo por que está relacionado. Só notas que
existem de verdade.
]==],
  ['Resumir.md'] = [==[
---
description: Resumir a nota (ou a seleção)
output: window
---
Resuma o texto selecionado, ou a nota inteira sem seleção, em até 7 tópicos
curtos. No fim, uma linha com a ideia principal.
]==],
  ['Nota permanente.md'] = [==[
---
description: Transformar a seleção em uma nota própria
output: replace
tools: Read, Glob, Write
dirs: vault
---
Crie uma nota nova na pasta "3-Resources" do vault (crie a pasta se não existir)
com o conteúdo da seleção, reescrito como uma nota permanente: um título claro
(que é o nome do arquivo .md), o texto organizado, e um link de volta para a nota
atual em "Origem: [[nome da nota atual]]".
Depois responda apenas com a linha que vai substituir a seleção na nota atual:
um resumo de uma frase seguido do link [[título da nota nova]].
]==],
}

--- Write the example actions into the actions folder (never over a file).
function M.examples()
  local dir, where = actionsDir()
  dir = dir or where
  if not dir then return vim.notify('No vault set: run :ZettelVault', vim.log.levels.WARN) end
  vim.fn.mkdir(dir, 'p')
  local made = {}
  for name, text in pairs(EXAMPLES) do
    local path = dir .. '/' .. name
    if not vim.uv.fs_stat(path) then
      vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
      table.insert(made, name)
    end
  end
  table.sort(made)
  vim.notify(#made > 0 and ('Created in %s:\n  %s'):format(dir, table.concat(made, '\n  '))
    or 'The examples are already there')
  M.mapActionKeys()
end

vim.api.nvim_create_user_command('ClaudeActions', M.pickAction, { desc = 'Pick a Claude action and run it' })
vim.api.nvim_create_user_command('ClaudeActionsExamples', M.examples,
  { desc = 'Write the example Claude actions into the actions folder' })

local actions_group = vim.api.nvim_create_augroup('PureClaudeActions', { clear = true })
vim.api.nvim_create_autocmd('VimEnter', { group = actions_group, once = true,
  callback = function() pcall(M.mapActionKeys) end })
if vim.v.vim_did_enter == 1 then pcall(M.mapActionKeys) end
-- A saved action file updates the keys.
vim.api.nvim_create_autocmd('BufWritePost', {
  group = actions_group,
  pattern = '*.md',
  callback = function(args)
    local dir = actionsDir()
    if dir and vim.fs.normalize(args.file):lower():find(dir:lower(), 1, true) then pcall(M.mapActionKeys) end
  end,
})

-- -----------------------------------------------------------------------------
--  Blocks in notes
-- -----------------------------------------------------------------------------

local block_begin, block_end = '<!-- claude -->', '<!-- /claude -->'

--- Every ```claude or ```llm block: { first, last (0-based fence rows), options, prompt }.
local function blocksIn(lines)
  local blocks, i = {}, 1
  while i <= #lines do
    if lines[i]:match('^%s*```%s*claude%s*$') or lines[i]:match('^%s*```%s*llm%s*$') then
      local j = i + 1
      while j <= #lines and not lines[j]:match('^%s*```%s*$') do j = j + 1 end
      local options, body, head = {}, {}, true
      for k = i + 1, j - 1 do
        local key, value = lines[k]:match('^%s*(%a+)%s*:%s*(.-)%s*$')
        if head and key and (key == 'when' or key == 'run' or key == 'model') then
          options[key] = (key == 'model') and value or value:lower()
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
    if text == block_begin or text:match('^```%s*claude') or text:match('^```%s*llm') then break end
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

  local m_label = modelLabel(block.options.model)
  -- With the seconds going (statusMark), as <leader>aa's window shows them.
  local status = statusMark(buf, block.last, m_label .. ' is answering…')
  local tick = vim.b[buf].changedtick
  run({
    prompt = prompt,
    tools = READ_TOOLS,
    model = block.options.model,
    cwd = cwd,
    on_done = function(err, text)
      block_running[id] = nil
      if not vim.api.nvim_buf_is_valid(buf) then return status.stop() end
      local at = status.id and vim.api.nvim_buf_get_extmark_by_id(buf, ns, status.id, {}) or {}
      status.stop()
      if err then return vim.notify(m_label .. ' block: ' .. err, vim.log.levels.ERROR) end
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
  -- Scheduled after the event: the buffer may be gone by then (a template
  -- that moves the note writes it, then wipes the buffer of its old name).
  if not vim.api.nvim_buf_is_valid(buf) then return end
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
  vim.notify(modelLabel() .. ': no ```claude or ```llm block under the cursor')
end

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufWritePost' }, {
  group = vim.api.nvim_create_augroup('PureClaudeBlocks', { clear = true }),
  pattern = { '*.md', '*.markdown' },
  callback = function(args) vim.schedule(function() autoBlocks(args.buf) end) end,
})

vim.api.nvim_create_user_command('ClaudeBlock', M.runBlockAtCursor, {
  desc = 'Run the ```claude block under the cursor (again)',
})

vim.api.nvim_create_user_command('ClaudeModel', function(opts)
  if opts.args and vim.trim(opts.args) ~= '' then
    M.setModel(vim.trim(opts.args))
  else
    M.selectModel()
  end
end, {
  nargs = '?',
  desc = 'Select or set the active LLM model (Ollama / Claude)',
  complete = function()
    return {
      'claude:default', 'claude:sonnet', 'claude:haiku', 'claude:opus',
      'ollama:qwen2.5-coder:14b', 'ollama:gemma4:26b',
    }
  end,
})

vim.api.nvim_create_user_command('LLMModel', function(opts)
  if opts.args and vim.trim(opts.args) ~= '' then
    M.setModel(vim.trim(opts.args))
  else
    M.selectModel()
  end
end, {
  nargs = '?',
  desc = 'Select or set the active LLM model (Ollama / Claude)',
})

M._blocksIn, M._due, M._unfence, M._run, M._extraContext = blocksIn, due, unfence, run, extraContext
M._runTool = runTool

return M
