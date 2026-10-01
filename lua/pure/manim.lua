-- =============================================================================
--  Manim preview
-- =============================================================================
--  A window that plays the Manim scene you are writing, and plays it again
--  each time the file is saved.
--
--    <leader>mm   start (or stop) the preview of the scene under the cursor
--                 (the class above it; asked when the cursor is on none)
--    <leader>ms   choose another scene of the file
--    <leader>mp   only a part: the selection, or the block the cursor is in
--                 (from the comment above it to the next one)
--    <leader>mf   a picture of the scene at the cursor line
--
--  Each keeps going on every save: the same part, the same line.
--
--  On every :w of that file, Manim renders the scene in the background
--  (`manim -ql`, low quality: fast) and the video replaces the one in the
--  window, looping. A render still running when you save again is dropped
--  for the new one. An error shows the end of the traceback, and its lines
--  go to the quickfix list (:copen).
--
--  The window is mpv (Linux, macOS and Windows), driven through its IPC
--  socket so it stays open and just loads the new video. Without mpv the
--  video opens in the system's player after each render.
--
--    vim.g.pure_manim_cmd = 'manim'   or { 'python', '-m', 'manim' }
--    vim.g.pure_manim_quality = 'l'   l (480p15), m (720p30), h (1080p60)
--    vim.g.pure_manim_args = {}       more arguments for manim
--    vim.g.pure_manim_viewer_args = {}  more for mpv ({ '--geometry=40%-0-0' }:
--                                     smaller, bottom right; '--ontop')
--
--  Videos are rendered under stdpath('cache')/manim, never next to the
--  project.
-- =============================================================================

local M = {}

local is_win = vim.fn.has('win32') == 1
local active = {}   -- buf -> { scene, job, count }
local viewer = {}   -- { proc, socket }

local function notify(msg, level) vim.notify('Manim: ' .. msg, level) end

--- Stop a process. On Windows its whole tree: pip's manim.exe is a
--- launcher, and killing it alone left Python rendering.
local function kill(obj)
  if not obj then return end
  if is_win and obj.pid then
    pcall(vim.system, { 'taskkill', '/T', '/F', '/PID', tostring(obj.pid) })
  else
    pcall(function() obj:kill(15) end)
  end
end

-- -----------------------------------------------------------------------------
--  Scenes
-- -----------------------------------------------------------------------------

--- Every scene class of the buffer: { name, row } (row 1-based).
local function scenes(buf)
  local out = {}
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local name, bases = line:match('^class%s+([%w_]+)%s*%((.-)%)%s*:')
    if name and bases:find('Scene', 1, true) then table.insert(out, { name = name, row = i }) end
  end
  return out
end

--- The scene the cursor is in (the last class at or above it), or nil.
local function sceneAtCursor(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local found
  for _, s in ipairs(scenes(buf)) do
    if s.row <= row then found = s.name end
  end
  return found
end

local function chooseScene(buf, cb)
  local list = scenes(buf)
  if #list == 0 then return notify('no Scene class in this file', vim.log.levels.WARN) end
  if #list == 1 then return cb(list[1].name) end
  vim.ui.select(vim.tbl_map(function(s) return s.name end, list), { prompt = 'Manim scene' }, function(name)
    if name then cb(name) end
  end)
end

-- -----------------------------------------------------------------------------
--  Parts of a scene
-- -----------------------------------------------------------------------------
--  Manim numbers the animations of a scene as it plays them: every
--  self.play(...) and self.wait(...), from 0. `manim -n A,B` renders only
--  animations A to B; the ones before are applied without being rendered,
--  so the part starts from the right state, and the scene stops after B.
--  Lines are turned into those numbers by counting the calls written in
--  construct() above them: a play inside a loop or in another method
--  counts once here, so there the numbers can be off (the notification
--  says which ones were rendered).

local ns = vim.api.nvim_create_namespace('pure_manim')

--- construct() of `scene`: first and last line (1-based), and the indent of
--- its body. nil when not found.
local function constructOf(buf, scene)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local class_row, def_row, class_indent
  for i, l in ipairs(lines) do
    local ind, name = l:match('^(%s*)class%s+([%w_]+)')
    if name == scene then class_row, class_indent = i, #ind end
    if class_row and i > class_row and l:match('^%s*def%s+construct%s*%(') then def_row = i break end
  end
  if not def_row then return nil end
  local def_indent = #lines[def_row]:match('^%s*')
  local body_indent, last = nil, def_row
  for i = def_row + 1, #lines do
    local l = lines[i]
    if l:match('%S') then
      local ind = #l:match('^%s*')
      if ind <= def_indent or (class_indent and ind <= class_indent) then break end
      body_indent = body_indent or ind
      last = i
    end
  end
  return { first = def_row + 1, last = last, indent = body_indent or def_indent + 4 }
end

--- How many animations the lines `from`..`to` of the buffer start.
local function countAnims(buf, from, to)
  local n = 0
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, from - 1, to, false)) do
    if not l:match('^%s*#') then
      for _ in l:gmatch('self%.play%s*%(') do n = n + 1 end
      for _ in l:gmatch('self%.wait%s*%(') do n = n + 1 end
    end
  end
  return n
end

--- The block the cursor is in: from the comment line above it (in the
--- body of construct) to the line before the next one, as in a notebook
--- cell. Without such comments, the whole construct.
local function blockAt(buf, c, row)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local function isMark(i)
    local l = lines[i] or ''
    return #l:match('^%s*') == c.indent and l:match('^%s*#') ~= nil
  end
  local first, last = c.first, c.last
  for i = math.min(row, c.last), c.first, -1 do
    if isMark(i) then first = i break end
  end
  for i = math.max(row, first) + 1, c.last do
    if isMark(i) then last = i - 1 break end
  end
  while last > first and not (lines[last] or ''):match('%S') do last = last - 1 end
  return first, last
end

-- -----------------------------------------------------------------------------
--  The window (mpv)
-- -----------------------------------------------------------------------------

local function socketPath()
  if is_win then return ([[\\.\pipe\pure-manim-%d]]):format(vim.uv.os_getpid()) end
  return ('%s/pure-manim-%d.sock'):format(vim.fn.stdpath('run'), vim.uv.os_getpid())
end

--- Send one command to the running mpv; `cb(ok)`.
local function send(command, cb)
  local pipe = vim.uv.new_pipe(false)
  pipe:connect(viewer.socket, function(err)
    if err then
      pipe:close()
      return cb and vim.schedule(function() cb(false) end)
    end
    pipe:write(vim.json.encode({ command = command }) .. '\n', function()
      pipe:close()
      if cb then vim.schedule(function() cb(true) end) end
    end)
  end)
end

local function startViewer(path)
  viewer.socket = socketPath()
  if not is_win then os.remove(viewer.socket) end
  local cmd = { 'mpv', '--loop-file=inf', '--keep-open=yes', '--force-window=yes', '--no-terminal',
    '--image-display-duration=inf',
    '--title=Manim preview', '--input-ipc-server=' .. viewer.socket }
  vim.list_extend(cmd, vim.g.pure_manim_viewer_args or {})
  table.insert(cmd, path)
  local ok, proc = pcall(vim.system, cmd, {}, function()
    vim.schedule(function() viewer.proc = nil end)
  end)
  if not ok then
    viewer.proc = nil
    return notify('could not start mpv: ' .. tostring(proc), vim.log.levels.ERROR)
  end
  viewer.proc = proc
end

--- Show `path` in the window, starting it if needed.
local function show(path)
  if vim.fn.executable('mpv') == 0 then
    -- No mpv: the system's player, once per render.
    return vim.ui.open(path)
  end
  if not viewer.proc then return startViewer(path) end
  send({ 'loadfile', path, 'replace' }, function(sent)
    -- The window was closed by hand (and the socket with it): a new one.
    if not sent then startViewer(path) end
  end)
end

function M.closeViewer()
  if viewer.proc then
    kill(viewer.proc)
    viewer.proc = nil
  end
  if viewer.socket and not is_win then os.remove(viewer.socket) end
end

-- -----------------------------------------------------------------------------
--  Rendering
-- -----------------------------------------------------------------------------

local function manimCmd()
  local cmd = vim.g.pure_manim_cmd or 'manim'
  if type(cmd) == 'table' then return vim.deepcopy(cmd) end
  if vim.fn.executable(cmd) == 1 then return { cmd } end
  -- Installed with pip but not on the PATH: through Python.
  for _, py in ipairs(is_win and { 'py', 'python' } or { 'python3', 'python' }) do
    if vim.fn.executable(py) == 1 then return { py, '-m', 'manim' } end
  end
  return nil
end

--- The rendered file: the newest `name`.`ext` under `dir`.
local function findOutput(dir, name, ext)
  local best, best_time
  for _, p in ipairs(vim.fn.globpath(dir, '**/' .. name .. '.' .. ext, false, true)) do
    local st = vim.uv.fs_stat(p)
    if st and (not best_time or st.mtime.sec > best_time) then best, best_time = p, st.mtime.sec end
  end
  return best
end

--- Where the error is, as quickfix items, and its message. Manim prints
--- tracebacks in boxes (rich), with long paths wrapped across lines, so
--- the frames are found by the file's own name ("cena.py:6 in construct");
--- plain Python tracebacks ('File "x", line 6') are read too.
local function parseError(output, file)
  local items = {}
  local base = vim.pesc(vim.fs.basename(file))
  for lnum, where in output:gmatch(base .. ':(%d+) in ([%w_]+)') do
    table.insert(items, { filename = file, lnum = tonumber(lnum), text = 'in ' .. where })
  end
  for path, lnum in output:gmatch('File "([^"]+)", line (%d+)') do
    table.insert(items, { filename = path, lnum = tonumber(lnum) })
  end
  -- The message: the last line that is not part of a box.
  local message
  for line in output:gmatch('[^\n]+') do
    if not line:match('^%s*[│╭╰]') and line:match('%S') and not line:match('^%s*INFO') then
      message = vim.trim(line)
    end
  end
  for _, it in ipairs(items) do it.text = (it.text and (it.text .. ': ') or '') .. (message or '') end
  return items, message
end

local function render(buf)
  local st = active[buf]
  if not st then return end
  local file = vim.api.nvim_buf_get_name(buf)
  local cmd = manimCmd()
  if not cmd then return notify('manim is not installed (pip install manim)', vim.log.levels.ERROR) end

  -- A render still running is replaced by this one.
  if st.job then kill(st.job) end

  -- A new name each time: on Windows the video mpv is playing is locked
  -- and could not be written over.
  st.count = (st.count or 0) + 1
  local name = ('%s-%d'):format(st.scene, st.count)
  local dir = vim.fn.stdpath('cache') .. '/manim/' .. vim.fn.sha256(file):sub(1, 12)
  vim.list_extend(cmd, { '-q' .. (vim.g.pure_manim_quality or 'l'), '--media_dir', dir, '-o', name,
    '--progress_bar', 'none' })
  vim.list_extend(cmd, vim.g.pure_manim_args or {})

  -- A part or a frame: which animations, from the marked lines as they are
  -- now (edits above them move the marks along).
  local what, ext = st.scene, 'mp4'
  if st.mode ~= 'scene' then
    local c = constructOf(buf, st.scene)
    if not c then return notify('no construct() in ' .. st.scene, vim.log.levels.WARN) end
    local a = vim.api.nvim_buf_get_extmark_by_id(buf, ns, st.marks[1], {})[1] + 1
    local b = vim.api.nvim_buf_get_extmark_by_id(buf, ns, st.marks[2], {})[1] + 1
    local before = countAnims(buf, c.first, a - 1)
    if st.mode == 'part' then
      local inside = countAnims(buf, a, b)
      if inside == 0 then
        return notify(('lines %d-%d play no animation (no self.play / self.wait)'):format(a, b), vim.log.levels.WARN)
      end
      vim.list_extend(cmd, { '-n', ('%d,%d'):format(before, before + inside - 1) })
      what = inside == 1 and ('%s, animation %d'):format(st.scene, before)
        or ('%s, animations %d-%d'):format(st.scene, before, before + inside - 1)
    else
      -- frame: the scene as it is after the animations up to this line.
      local upto = before + countAnims(buf, a, a) - 1
      if upto < 0 then return notify('no animation before line ' .. a .. ' yet', vim.log.levels.WARN) end
      vim.list_extend(cmd, { '-s', '-n', ('0,%d'):format(upto) })
      what, ext = ('%s after animation %d (line %d)'):format(st.scene, upto, a), 'png'
    end
  end
  vim.list_extend(cmd, { file, st.scene })

  local started = vim.uv.hrtime()
  notify(('rendering %s…'):format(what))
  local job
  local ok, obj = pcall(vim.system, cmd, {
    cwd = vim.fs.dirname(file),
    text = true,
    env = { NO_COLOR = '1', TERM = 'dumb' },
  }, vim.schedule_wrap(function(res)
    if not active[buf] or active[buf].job ~= job then return end -- stopped or replaced
    st.job = nil
    if res.signal ~= 0 then return end
    local secs = (vim.uv.hrtime() - started) / 1e9
    local output = (res.stdout or '') .. '\n' .. (res.stderr or '')
    M.last_output = output
    if res.code ~= 0 then
      local items, message = parseError(output, file)
      vim.fn.setqflist({}, 'r', { title = 'Manim ' .. st.scene, items = items })
      local here = items[1] and items[1].filename == file and (' (line ' .. items[1].lnum .. ')') or ''
      return notify(('%s failed%s: %s\n:copen for the place, :ManimLog for the whole output'):format(
        what, here, message or ('exit code ' .. res.code)), vim.log.levels.ERROR)
    end
    local out = findOutput(dir, name, ext)
    if not out then return notify('rendered, but nothing found in ' .. dir, vim.log.levels.WARN) end
    notify(('%s ready (%.1fs)'):format(what, secs))
    show(out)
    -- The ones shown before: removed once the new one is showing (a moment
    -- later, as Windows keeps the one mpv still has open locked). Only
    -- those: a render that finishes meanwhile keeps its file.
    local old = st.shown or {}
    st.shown = { out }
    vim.defer_fn(function()
      for _, p in ipairs(old) do pcall(os.remove, p) end
    end, 2000)
  end))
  if not ok then return notify('could not run manim: ' .. tostring(obj), vim.log.levels.ERROR) end
  job = obj
  st.job = obj
end

-- -----------------------------------------------------------------------------
--  Commands
-- -----------------------------------------------------------------------------

--- Start previewing `scene`: the whole of it, or (`range`: { first, last }
--- lines) only a part or the frame at a line.
local function start(buf, scene, mode, range)
  local old = active[buf]
  if old and old.job then kill(old.job) end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local st = { scene = scene, mode = mode or 'scene', count = old and old.count, shown = old and old.shown }
  if range then
    st.marks = {
      vim.api.nvim_buf_set_extmark(buf, ns, range[1] - 1, 0, {}),
      vim.api.nvim_buf_set_extmark(buf, ns, range[2] - 1, 0, {}),
    }
  end
  active[buf] = st
  if vim.bo[buf].modified then vim.cmd('silent write') else render(buf) end
end

--- The visual selection as lines, leaving visual mode; nil outside it.
local function selection()
  if not vim.fn.mode():match('^[vV\22]') then return nil end
  local a, b = vim.fn.line('v'), vim.fn.line('.')
  vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
  return { math.min(a, b), math.max(a, b) }
end

--- Preview only part of the scene: the selection, or the block the cursor
--- is in (from the comment above it to the next). Saving renders that part
--- again.
function M.part()
  local buf = vim.api.nvim_get_current_buf()
  local range = selection()
  local scene = sceneAtCursor(buf)
  if not scene then return notify('put the cursor inside a scene', vim.log.levels.WARN) end
  local c = constructOf(buf, scene)
  if not c then return notify('no construct() in ' .. scene, vim.log.levels.WARN) end
  if not range then
    local first, last = blockAt(buf, c, vim.api.nvim_win_get_cursor(0)[1])
    range = { first, last }
  end
  start(buf, scene, 'part', range)
end

--- The scene as it is at the cursor line, as a picture. Saving draws it
--- again.
function M.frame()
  local buf = vim.api.nvim_get_current_buf()
  local scene = sceneAtCursor(buf)
  if not scene then return notify('put the cursor inside a scene', vim.log.levels.WARN) end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  start(buf, scene, 'frame', { row, row })
end

--- Start the preview of the scene under the cursor, or stop it.
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  if active[buf] and active[buf].mode == 'scene' then return M.stop(buf) end
  if vim.api.nvim_buf_get_name(buf) == '' then return notify('save the file first', vim.log.levels.WARN) end
  local scene = sceneAtCursor(buf)
  if scene then return start(buf, scene) end
  chooseScene(buf, function(name) start(buf, name) end)
end

--- Choose another scene for the preview (and start it).
function M.pick()
  local buf = vim.api.nvim_get_current_buf()
  chooseScene(buf, function(name)
    if active[buf] and active[buf].job then kill(active[buf].job) end
    start(buf, name)
  end)
end

function M.stop(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = active[buf]
  if st and st.job then kill(st.job) end
  active[buf] = nil
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  if next(active) == nil then M.closeViewer() end
  notify('preview stopped')
end

local group = vim.api.nvim_create_augroup('PureManim', { clear = true })
vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  pattern = '*.py',
  callback = function(args) if active[args.buf] then render(args.buf) end end,
})
vim.api.nvim_create_autocmd('BufWipeout', {
  group = group,
  callback = function(args)
    if active[args.buf] then M.stop(args.buf) end
  end,
})
vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = M.closeViewer })

vim.api.nvim_create_user_command('ManimPreview', function(o)
  local buf = vim.api.nvim_get_current_buf()
  if o.args ~= '' then return start(buf, o.args) end
  M.toggle()
end, {
  nargs = '?',
  complete = function() return vim.tbl_map(function(s) return s.name end, scenes(0)) end,
  desc = 'Preview a Manim scene, again on every save',
})
vim.api.nvim_create_user_command('ManimLog', function()
  if not M.last_output then return notify('nothing rendered yet') end
  local _, buf = require('configs.functions').createWindow(' Manim output ', 0.8)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(M.last_output, '\n'))
  vim.bo[buf].bufhidden = 'wipe'
  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf, nowait = true })
end, { desc = 'The output of the last Manim render' })
vim.api.nvim_create_user_command('ManimStop', function() M.stop() end, { desc = 'Stop the Manim preview' })

M._scenes, M._sceneAtCursor, M._constructOf, M._countAnims, M._blockAt =
  scenes, sceneAtCursor, constructOf, countAnims, blockAt

return M
