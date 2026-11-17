-- The whole configuration loads: every module of lua/ is in package.loaded, and the vault is the fixture copy.
T.test('every module of lua/ loads', function()
  local root = vim.fs.normalize(vim.fn.stdpath('config')) .. '/lua'
  local missing = {}
  for _, f in ipairs(vim.fn.glob(root .. '/**/*.lua', true, true)) do
    local mod = vim.fs.normalize(f):sub(#root + 2):gsub('%.lua$', ''):gsub('/', '.')
    if not package.loaded[mod] then missing[#missing + 1] = mod end
  end
  T.eq(missing, {}, 'modules that did not load')
end)

T.test('the vault is the fixture copy', function()
  T.eq(require('pure.vault').dir(), vim.fs.normalize(T.vault()))
end)

T.test('org.nvim is set up on the vault', function()
  T.ok(vim.fn.exists(':Org') == 2, ':Org exists')
end)
