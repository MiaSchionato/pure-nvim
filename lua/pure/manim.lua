-- =============================================================================
--  Manim preview
-- =============================================================================
--  A window that plays the Manim scene you are writing, and plays it again
--  each time the file is saved.
--
--    <leader>mm   start (or stop) the preview of the scene under the cursor
--                 (the class above it; asked when the cursor is on none)
--    <leader>ms   choose another scene of the file
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

--- The rendered video: the newest `name`.mp4 under `dir`.
local function findVideo(dir, name)
  local best, best_time
  for _, p in ipairs(vim.fn.globpath(dir, '**/' .. name .. '.mp4', false, true)) do
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
  vim.list_extend(cmd, { file, st.scene })

  local started = vim.uv.hrtime()
  notify(('rendering %s…'):format(st.scene))
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
        st.scene, here, message or ('exit code ' .. res.code)), vim.log.levels.ERROR)
    end
    local video = findVideo(dir, name)
    if not video then return notify('rendered, but no video found in ' .. dir, vim.log.levels.WARN) end
    notify(('%s ready (%.1fs)'):format(st.scene, secs))
    show(video)
    -- The previous videos: removed once the new one is playing.
    vim.defer_fn(function()
      for _, p in ipairs(vim.fn.globpath(dir, '**/' .. st.scene .. '-*.mp4', false, true)) do
        if vim.fs.basename(p) ~= name .. '.mp4' then pcall(os.remove, p) end
      end
    end, 2000)
  end))
  if not ok then return notify('could not run manim: ' .. tostring(obj), vim.log.levels.ERROR) end
  job = obj
  st.job = obj
end

-- -----------------------------------------------------------------------------
--  Commands
-- -----------------------------------------------------------------------------

local function start(buf, scene)
  active[buf] = { scene = scene }
  if vim.bo[buf].modified then vim.cmd('silent write') else render(buf) end
end

--- Start the preview of the scene under the cursor, or stop it.
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  if active[buf] then return M.stop(buf) end
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

M._scenes, M._sceneAtCursor = scenes, sceneAtCursor

return M
