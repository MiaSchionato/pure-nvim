> **Done (2026-10-28).** The transparency toggle ended up simpler than this plan: one state variable and a re-applied
> colorscheme instead of saved highlights. See "Transparency" in `ui.md`. Kept as the record of the original plan.

# Plan: Default Colorized Backgrounds, Unified Transparency Toggle & Theme Persistence

This document provides a step-by-step configuration plan for your Neovim setup to achieve three goals:

1. **Default Colorized Backgrounds**: All themes start with their native, opaque backgrounds (no theme starts transparent).
2. **Unified `<leader>ox` Transparency Toggle**:
   - In **Neovide**: toggles `vim.g.neovide_opacity` and `vim.g.neovide_normal_opacity` between `1.0` (opaque) and `vim.g.transparencyAmount` (translucent).
   - In **Terminal**: toggles highlight group backgrounds (`Normal`, `NormalFloat`, etc.) between their colorized theme values and `"NONE"` (revealing your terminal's transparency).
   - Changing colorschemes resets the toggle state so new themes always start with their proper colors.
3. **Last Used Theme as Default**: No hardcoded theme (like `NeoSolarized`); Neovim remembers whichever colorscheme you were last using across restarts.

---

## Summary of File Modifications

| File | What Goes Away (Delete/Remove) | What Goes Where (Add/Update) |
|---|---|---|
| `lua/themes/myghtfly.lua` | `Normal = { bg = none }` in the non-Neovide branch | Keep `Normal = { bg = "#011627", fg = white }` in all environments |
| `lua/themes/colorschemes.lua` | Hardcoded `vim.g.MY_THEME = "NeoSolarized"` & commented-out blocks | Explicit `setup({ transparent = false })` for themes that default to transparent (`NeoSolarized`, `solarized-osaka`) |
| `lua/configs/autocmds.lua` | Hardcoded fallback to `NeoSolarized`, `pcall(mod.setup, { transparent = true })`, and commented-out float hacks | Read last-saved theme from storage, apply it without forcing transparency, and auto-save active theme on `ColorScheme` |
| `lua/configs/functions.lua` | Commented-out `syncFloatBg` and brittle toggle logic | Clean `M.toggleTransparency()` supporting both Neovide opacity and Terminal highlight clearing |
| `lua/configs/neovide.lua` | Hardcoded background overrides (`#060b1e`) and commented-out commands | Initialize Neovide opacity to `1.0` (opaque by default) |
| `lua/pure/fuzzyUtils.lua` | Commented-out `vim.api.nvim_set_hl(0, 'Normal', ...)` | Clean exit from `pickList` |

---

## Detailed Step-by-Step Instructions

### Step 1: `lua/themes/myghtfly.lua`
**Goal**: Ensure `myghtfly` has a solid `#011627` background by default in terminal as well as Neovide.

#### What goes away:
Lines ~267–282 currently split Neovide and non-Neovide, setting `bg = none` when `not vim.g.neovide`:
```lua
-- DELETE THIS BRANCH:
else
  neovideSupport = {
    Normal           = { bg = none, fg = white },
    NormalNC         = { bg = none },
    NormalFloat      = { bg = none, fg = blue },
    PureNotifyNormal = { bg = none, fg = malibu },
  }
end
```

#### What goes in:
Unify `neovideSupport` so `Normal` always has `bg = "#011627"`:
```lua
local defaultHighlights = {
  Normal           = { bg = "#011627", fg = white },
  NormalFloat      = { bg = none, fg = blue },
  PureNotifyNormal = { bg = none, fg = malibu },
}
```
In `M.setup()`, apply `defaultHighlights`.

---

### Step 2: `lua/themes/colorschemes.lua`
**Goal**:
1. Remove hardcoded `NeoSolarized` default.
2. Ensure plugins that default to transparent (`NeoSolarized.nvim` and `solarized-osaka.nvim`) are configured with `transparent = false`.
3. Clean up dead/commented-out code.

#### What goes away:
- Delete `vim.g.MY_THEME = vim.g.MY_THEME or "NeoSolarized"`
- Delete the commented-out `vim.schedule(...)` block.
- Delete the commented-out `savedHl` and `<leader>ox` mapping block at the bottom (this belongs in `functions.lua` and `keymaps.lua`).

#### What goes in:
Configure both themes with `transparent = false`:
```lua
local M = {}

local colorschemes = {
  ["solarized-osaka"]  = "craftzdog/solarized-osaka.nvim",
  eldritch             = "eldritch-theme/eldritch.nvim",
  ethereal             = "bjarneo/ethereal.nvim",
  catppuccin           = "catppuccin/nvim",
  tokyonight           = "folke/tokyonight.nvim",
  ["rose-pine"]        = "rose-pine/neovim",
  tokyodark            = "tiagovla/tokyodark.nvim",
  ["night-owl"]        = "oxfist/night-owl.nvim",
  NeoSolarized         = "Tsuzat/NeoSolarized.nvim",
  Palenight            = "drewtempelmeyer/palenight.vim",
  Solarized_highlight  = "lifepillar/vim-solarized8",
}

local specs = {}
for name, link in pairs(colorschemes) do
  table.insert(specs, { src = 'https://github.com/' .. link, name = name })
end
vim.pack.add(specs)

-- Plugins whose internal default is transparent = true: explicitly disable it
local okNeo, NeoSolarized = pcall(require, "NeoSolarized")
if okNeo and NeoSolarized then
  NeoSolarized.setup({ style = "dark", transparent = false })
end

local okOsaka, Solarized_osaka = pcall(require, "solarized-osaka")
if okOsaka and Solarized_osaka then
  Solarized_osaka.setup({ style = "dark", transparent = false })
end

-- Highlight groups affected by terminal transparency toggle
M.groups = {
  "Normal",
  "NormalNC",
  "NormalFloat",
  "FloatBorder",
  "FloatTitle",
  "WinBar",
  "WinBarNC",
  "WinSeparator",
  "VertSplit",
  "SignColumn",
  "LineNr",
  "CursorLineNr",
  "FoldColumn",
  "EndOfBuffer",
  "StatusLine",
  "StatusLineNC",
  "TabLine",
  "TabLineFill",
  "TabLineSel",
  "Pmenu",
  "PmenuSel",
  "PmenuSbar",
  "PmenuThumb",
  "Question",
  "QuickFixLine",
  "MsgArea",
}

return M
```

---

### Step 3: `lua/configs/autocmds.lua`
**Goal**:
1. Default to the last used theme saved in `stdpath('data')/colorscheme`.
2. Stop forcing `pcall(mod.setup, { transparent = true })`.
3. Automatically save any newly applied colorscheme whenever `:colorscheme <name>` or `<leader>fc` runs.
4. Clean up commented-out float background code.

#### What goes away:
- Delete `theme = vim.g.MY_THEME or 'NeoSolarized'`
- Delete lines 28–31:
  ```lua
  local ok, mod = pcall(require, theme)
  if ok and type(mod) == 'table' and type(mod.setup) == 'function' then
    pcall(mod.setup, { transparent = true })
  end
  ```
- Delete all commented-out `syncFloatBg` and `Normal` highlight lines (lines 49–69).

#### What goes in:
Replace the initial `VimEnter` colorscheme block (lines 1–58) with:
```lua
-- Apply last-used colorscheme on startup
vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    local okOm, omarchy = pcall(require, 'pure.omarchy-theme')
    local theme = okOm and omarchy.saved() or vim.g.MY_THEME

    if theme == 'omarchy' and okOm then
      local scheme, why = omarchy.resolved()
      if not scheme then
        vim.notify('Omarchy theme: ' .. tostring(why), vim.log.levels.WARN)
      end
      theme = scheme
    end

    -- If no theme has ever been saved yet, fall back gracefully to a solid default
    theme = theme or 'tokyonight'

    if theme and theme ~= 'solarized-osaka' then
      local applied = pcall(vim.cmd.colorscheme, theme)
      if not applied and theme ~= 'myghtfly' then
        applied = pcall(vim.cmd.colorscheme, 'myghtfly')
      end
    end

    -- Disable annoying commenting while coding
    vim.api.nvim_set_hl(0, "DiagnosticUnnecessary", {})
  end,
})

-- Persist whatever colorscheme is applied (via :colorscheme, <leader>fc, etc.)
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function(args)
    local scheme = args.match
    if scheme and scheme ~= "" then
      vim.g.MY_THEME = scheme
      local okOm, omarchy = pcall(require, 'pure.omarchy-theme')
      if okOm then
        omarchy.save(scheme)
      end
    end
  end,
})
```

---

### Step 4: `lua/configs/functions.lua`
**Goal**: Provide a clean, robust `M.toggleTransparency()` that checks for Neovide and handles both environments cleanly.

#### What goes away:
- Remove commented-out `function M.syncFloatBg(fresh)` (lines 27–36).
- Replace lines 414–446 with the unified implementation.

#### What goes in:
```lua
local savedHl = nil
local groups = require('themes.colorschemes').groups

-- Whenever the colorscheme changes, discard the saved transparent state so the new theme starts opaque
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    savedHl = nil
  end,
})

function M.toggleTransparency()
  if vim.g.neovide then
    local target = vim.g.transparencyAmount or 0.9
    -- If currently transparent/translucent, toggle back to opaque 1.0; otherwise set to target opacity
    if (vim.g.neovide_opacity or 1.0) < 1.0 then
      vim.g.neovide_opacity = 1.0
      vim.g.neovide_normal_opacity = 1.0
    else
      vim.g.neovide_opacity = target
      vim.g.neovide_normal_opacity = target
    end
  else
    -- Terminal environment: toggle background between solid theme color and NONE
    if savedHl then
      -- Restore original colors
      for name, hl in pairs(savedHl) do
        vim.api.nvim_set_hl(0, name, hl)
      end
      savedHl = nil
    else
      -- Save current colors and clear backgrounds
      savedHl = {}
      for _, name in ipairs(groups) do
        local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
        savedHl[name] = hl
        vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", hl, { bg = "NONE", ctermbg = "NONE" }))
      end
    end
  end
end
```

---

### Step 5: `lua/configs/neovide.lua`
**Goal**: Make Neovide start with an opaque background (`1.0`) so all themes look rich and opaque until the user triggers `<leader>ox`. Clean out dead code.

#### What goes away:
- Delete:
  ```lua
  vim.g.neovide_opacity = transparencyAmount
  vim.g.neovide_normal_opacity = transparencyAmount
  ```
- Delete all commented-out code at lines 13–31.

#### What goes in:
```lua
if vim.g.neovide then
  vim.g.neovide_floating_blur_amount_x = 5.0
  vim.g.neovide_floating_blur_amount_y = 5.0
  vim.g.neovide_floating_corner_radius = 0.6

  vim.g.neovide_window_blurred = false
  vim.g.neovide_floating_shadow = false

  -- Default to fully opaque on startup
  vim.g.neovide_opacity = 1.0
  vim.g.neovide_normal_opacity = 1.0
end
```

---

### Step 6: `lua/pure/fuzzyUtils.lua`
**Goal**: Clean up leftover commented-out background overrides.

#### What goes away:
Lines 608–610:
```lua
-- DELETE:
-- if vim.g.neovide then
--   vim.api.nvim_set_hl(0, 'Normal', { bg = "#060b1e" })
-- end
```

---

## Verification & Testing Procedure

Once applied:
1. **Startup Check**:
   Launch Neovim in terminal. Verify that the editor has a solid, colorized background matching the last used theme.
2. **Switch Colorscheme**:
   Run `:colorscheme NeoSolarized` and `:colorscheme solarized-osaka`. Check with `:hi Normal` that `guibg` is a hex color (e.g. `#002b36`), **not** `NONE`.
3. **Persistence Check**:
   Switch to any theme (e.g. `:colorscheme tokyonight`). Quit Neovim (`:qa`) and relaunch. Verify that Neovim opens directly in `tokyonight`.
4. **Terminal Toggle Check (`<leader>ox`)**:
   Press `<leader>ox`. The background should clear to your terminal's transparency. Press `<leader>ox` again; the solid background should be restored.
5. **Neovide Toggle Check**:
   Launch in Neovide. The window is opaque by default. Press `<leader>ox`; window opacity transitions to `0.9`. Press again; it returns to `1.0`.
