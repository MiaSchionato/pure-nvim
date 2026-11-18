-- Loaded with --cmd by tests/run.lua, before the configuration: modules that would reach outside the test
-- are replaced. pure.protonpass would read the Todoist and Google Calendar secrets (and Todoist would then
-- write the real tasks into the fixture vault): here it knows no secret, so both stay off.
package.preload['pure.protonpass'] = function()
  local M = {}
  function M.prefetch() end
  function M.on_ready(cb) if cb then cb() end end
  function M.get() return nil end
  function M.set() return false end
  function M.reset() end
  return M
end
