---@brief
---
--- https://github.com/razzmatazz/csharp-language-server
---
--- Language Server for C#.
---
--- csharp-ls requires the [dotnet-sdk](https://dotnet.microsoft.com/download) to be installed.
---
--- The preferred way to install csharp-ls is with `dotnet tool install --global csharp-ls`.

---@type vim.lsp.Config
return {
  cmd = function(dispatchers, config)
    return vim.lsp.rpc.start({ 'csharp-ls' }, dispatchers, {
      -- csharp-ls attempt to locate sln, slnx or csproj files from cwd, so set cwd to root directory.
      -- If cmd_cwd is provided, use it instead.
      cwd = config.cmd_cwd or config.root_dir,
      env = config.cmd_env,
      detached = config.detached,
    })
  end,
  -- The nearest folder with a solution, else with a project file: each kind
  -- is searched on its own so a .sln further up still wins over a .csproj.
  root_dir = function(bufnr, on_dir)
    for _, ext in ipairs({ '%.sln$', '%.slnx$', '%.csproj$' }) do
      local root = vim.fs.root(bufnr, function(name) return name:match(ext) ~= nil end)
      if root then return on_dir(root) end
    end
  end,
  filetypes = { 'cs' },
  init_options = {
    AutomaticWorkspaceInit = true,
  },
}
