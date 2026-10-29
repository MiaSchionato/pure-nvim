vim.pack.add({ { src = 'https://github.com/xheisenbugx/org.nvim', name = 'org' } })

require('org').setup({
  org_directory = '~/Flora',
  agenda_files = { '~/Flora/**/*.org' },
  default_notes_file = '~/Flora/inbox.org',
  capture = {
    templates = {
      t = {
        description = 'Task',
        template = '* TODO %?\n  %u',
        target = 'tasks.org',
      },
    },
  },
})
