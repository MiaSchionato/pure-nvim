-- Run at the end of lua/configs/configs.lua when PURE_TEST_SETTINGS names this file (tests/run.lua does):
-- the settings that name folders point at the fixture copies in the test's HOME, whatever configs.lua says.
local home = vim.env.PURE_TEST_HOME
local g = vim.g

g.pure_vault = home .. '/vault-org'
g.orgls_inbox = 'inbox.org'
g.pure_vault_notes = nil
g.pure_llm_actions = home .. '/vault-org/ai/actions'
g.pure_llm_personas = home .. '/vault-org/ai/personas'
g.pure_llm_private = {}
g.pure_llm_blocks = false
g.pure_outside_folders = {}
g.pure_todoist_sync = false
g.pure_todoist_archive = nil
g.pure_calendar_sync = false
g.remote_socket = false
g.remote_address_file = false
