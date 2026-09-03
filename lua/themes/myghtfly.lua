-- That's the nightfly palette, with just some tweaks to fit my own taste
-- gitgub.com/bluz71/vim-nightfly-colors
--

-- Basic Palette ---------------------------------------------------------------------------------------------
-- -----------------------------------------------------------------------------------------------------------
local M = {}
-- NOTE: g:colors_name is set by colors/myghtfly.lua, the real colorscheme
-- entrypoint. Setting it here (at require time) made Neovim believe the theme
-- was already active, so its highlights were never actually applied.

-- Background and foreground
if vim.g.neovide then
  local bg = "NONE"
else
end

local none = "NONE"
local black = "#011627"
local white = "#c3ccdc"

-- Variations of midnight-blue
local black_blue = "#081e2f"
local dark_blue = "#092236"
local ink_blue = "#09243a"
local deep_blue = "#0e293f"
local storm_blue = "#1b2633"
local stone_blue = "#252c3f"
local slate_blue = "#2c3043"
local pickle_blue = "#38507a"
local cello_blue = "#1f4462"
local regal_blue = "#1d3b53"
local carbon_blue = "#334e65"
local steel_blue = "#4b6479"
local grey_blue = "#7c8f8f"
local graphite_blue = "#768799"
local cadet_blue = "#a1aab8"
local ash_blue = "#acb4c2"
local white_blue = "#d6deeb"

-- Core theme colors
local red = "#fc514e"
local watermelon = "#ff5874"
local cinnamon = "#ed9389"
local orchid = "#e39aa6"
local orange = "#f78c6c"
local peach = "#ffcb8b"
local tan = "#ecc48d"
local yellow = "#e3d18a"
local lime = "#85dc85"
local green = "#a1cd5e"
local emerald = "#21c7a8"
local turquoise = "#7fdbca"
local malibu = "#87bcff"
local blue = "#82aaff"
local lavender = "#b0b2f4"
local violet = "#c792ea"
local purple = "#ae81ff"

-- Extra colors
local lighter_blue = "#8AB9F9"
local light_blue = "#4187cc"
local cyan_blue = "#316394"
local bay_blue = "#24567f"
local kashmir = "#4d618e"
local plant = "#2a4e57"
local bermuda = "#6e8da6"
local haze = "#87a3ba"

-- Setting the colorscheme -----------------------------------------------------------------------------------
-- -----------------------------------------------------------------------------------------------------------




local groups = {
  -- Markdown render
  none =  {bg = none, fg = none},
  markdownH1 = { fg = "#e06c75", bold = true },
  markdownH2 = { fg = "#98c379", bold = true },
  RenderMarkdownH1Bg = { bg = none },
  RenderMarkdownH2Bg = { bg = none },
  RenderMarkdownH3Bg = { bg = none },
  RenderMarkdownH4Bg = { bg = none },
  RenderMarkdownH5Bg = { bg = none },
  RenderMarkdownH6Bg = { bg = none },

  -- Misc
  ColorColumn = { link = "String" },
  --
  --Custom Statusline
  BlueMode =  { bg = blue, fg = dark_blue },
  EmeraldMode =  { bg = emerald, fg = dark_blue },
  PurpleMode =  { bg = purple, fg = dark_blue },
  WatermelonMode =  { bg = watermelon, fg = dark_blue },
  TanMode =  { bg = tan, fg = dark_blue },
  TurquoiseMode =  { bg = turquoise, fg = dark_blue },
  PlantMode =  { bg = plant, fg = dark_blue },

  -- Syntax
  Delimiter = {fg = white_blue},
  Function = { fg = blue },
  String = { fg = tan },
  Boolean = { fg = watermelon },
  Identifier = {fg = violet },
  Title = { fg = orange },
  StorageClass = {fg = violet },
  Type = { fg = lavender },
  Constant = {fg = orange },
  Character = {fg = purple },
  Exception = {fg = watermelon },
  PreProc = {fg = watermelon },
  Label = {fg = malibu },
  Operator = {fg = watermelon },
  Repeat = {fg = violet },
  CurSearch = { bg = malibu, fg = black },
  IncSearch = { bg = peach, fg = black },
  Special = {fg = watermelon },
  Statement = { fg = violet },
  Structure = {fg = blue },

  -- Default Interface
   EndOfBuffer = { bg = none },
   Comment = { fg = grey_blue, italic = true },
   Search = { bg = pickle_blue, fg = white_blue },
   Cursor = { fg = bg, bg = blue },

   -- Command line
   ErrorMsg = {bg = none, fg = red},
   MoreMsg = {bg = none, fg = cello_blue},

   --visual
   Visual = { bg = regal_blue },
   VisualNOS = { bg = regal_blue, fg = white },
   VisualNonText = { bg = regal_blue, fg = steel_blue },

   -- Transparent moode 
   Statusline = { bg = none },
   StatusLineNC = { bg = none },
   WinSeparator = { bg = none },
   LineNr= { bg = none, fg = steel_blue }, -- numberline,
   SignColumn= { bg = none },
   NonText= { fg = blue, bold = true },

   -- Pmenu
   Pmenu= { bg = none, fg = blue },
   PmenuSel= { bg = cyan_blue, fg = white_blue },
   PmenuSbar= { bg = none },
   PmenuThumb= { bg = none },
   WildMenu = { bg = cyan_blue, fg = white_blue },

  -- Floating window's ,
   FloatBorder = { bg = none , fg = blue},
   FloatTitle = { bg = none, fg = malibu },

  -- tabview,
   TabLine= { bg = none, fg = blue, bold = true }, -- Active,
   TabLineSel= { bg = none, fg = malibu }, -- inactive,
   TabLineFill= { bg = none }, -- tabline bg

  -- lsp,
   DiagnosticSignWarn= { bg = none, fg = tan },

  -- Indent,
   MiniIndentscopeSymbol= { fg = blue }, -- tabline bg

  -- Pick,
   MiniPickNormal= { bg = none,},
   MiniPickBorder= { bg = none,},
   MiniPickBorderText= { bg = none,},
   MiniPickMatchCurrent= { fg = blue},
   MiniPickPreviewLine= { fg = blue},

  -- Mini Files,
   MiniFilesTitle= {bg = none, fg = blue},
   MiniFilesTitleFocused= {bg = none, fg = blue},

   -- Diffs
    DiffAdd =  { bg = plant },
    DiffChange =  { bg = slate_blue },
    DiffDelete =  { bg = slate_blue, fg = steel_blue },
    DiffText =  { bg = kashmir },

    --Icons
    IconsBlue = {fg = blue},
    IconsGrey = { fg = grey_blue},
    IconsPurple = { fg = purple},
    IconsOrange = { fg = orange},
    IconsYellow = { fg = yellow},

    -- Misc
    Directory = {bg = none, fg = blue},

    -- Git
   GitSignAdd = { fg = "#7efb67", bold = true },
   GitSignDel = { fg = "#ff5189", bold = true },

--"Neovim Tree-sitter
  ["@attribute"] = { fg= blue },
  ["@comment.error"] = { fg= red },
  ["@comment.note"] = { fg= grey_blue },
  ["@comment.ok"] = { fg= green },
  ["@comment.todo"] = { fg= orange },
  ["@comment.warning"] = { fg= yellow },
  ["@constant"] = { fg= bay_blue },
  ["@constant.builtin"] = { fg= orange },
  ["@constant.macro"] = { fg= violet },
  ["@constructor"] = { fg= emerald },
  ["@diff.delta"] = { link = "DiffChange" },
  ["@diff.minus"] = { link = "DiffDelete" },
  ["@diff.plus"] = { link = "DiffAdd" },
  ["@function.builtin"] = { link = "Function" },
  ["@function.call"] = { link = "Function" },
  ["@function.macro"] = { fg  = lavender },
  ["@function.method"] = { link = "Function" },
  ["@function.method.call"] = { link = "Function" },
  ["@keyword.conditional"] = { link = "Conditional" },
  ["@keyword.directive"] = { link = "PreProc" },
  ["@keyword.directive.define"] = { link = "Define" },
  ["@keyword.exception"] = { fg = violet },
  ["@keyword.import"] = { link = "Include" },
  ["@keyword.operator"] = { fg = violet },
  ["@keyword.repeat"] = { link = "Repeat" },
  ["@keyword.storage"] = { link = "StorageClass" },
  ["@keyword.return"] = { link = "Statement" },
  ["@markup.environment"] = { fg = violet },
  ["@markup.environment.name"] = { fg = lavender },
  ["@markup.heading"] = { fg = violet },
  ["@markup.italic"] = { fg = orchid, italic = true },
  ["@markup.link"] = { fg = green },
  ["@markup.link.label"] = { fg = green },
  ["@markup.link.url"] = { fg = purple, underline = true, sp = grey_blue },
  ["@markup.list"] = { fg = watermelon },
  ["@markup.list.checked"] = { fg = lavender },
  ["@markup.list.unchecked"] = { fg = blue },
  ["@markup.math"] = { fg = malibu },
  ["@markup.quote"] = { fg = grey_blue },
  ["@markup.raw"] = { link = "String" },
  ["@markup.strikethrough"] = { strikethrough = true },
  ["@markup.strong"] = { fg = orchid },
  ["@markup.underline"] = { underline = true },
  ["@module"] = { fg = lavender },
  ["@module.builtin"] = { fg = green },
  ["@none"] = {},
  ["@parameter.builtin"] = { fg = orchid },
  ["@property"] = { fg = lavender },
  ["@string.documentation"] = { fg = lavender },
  ["@string.regexp"] = { fg = lavender },
  ["@string.special.path"] = { fg = orchid },
  ["@string.special.symbol"] = { fg = purple },
  ["@string.special.url"] = { fg = purple },
  ["@tag"] = { fg = blue },
  ["@tag.attribute"] = { fg = lavender },
  ["@tag.builtin"] = { fg = blue },
  ["@tag.delimiter"] = { fg = green },
  ["@type.builtin"] = { fg = lavender },
  ["@type.qualifier"] = { fg = violet },
  ["@variable"] = { fg =  white_blue },
  ["@variable.builtin"] = { fg = green },
  ["@variable.member"] = { fg = lavender },
  ["@variable.parameter"] = { fg = lavender },
}

-- Clearing all highlitghs
-- Background / foreground, which differ between Neovide and a terminal.
--
-- Built *before* setup() runs. Previously the neovideSupport table captured
-- Normal/NormalNC while both were still nil (they were only assigned in the
-- if/else below it), so the apply-loop iterated over an empty table and Normal
-- kept Neovim's default background -- the theme never took the background over.
-- MiniNotifyNormal was declared `local` inside each branch and discarded, so it
-- never applied either.
local neovideSupport
if vim.g.neovide then
  neovideSupport = {
    Normal           = { bg = "#011627", fg = white },
    -- NormalNC      = { bg = "#011627" },
    NormalFloat      = { bg = none, fg = blue },
    MiniNotifyNormal = { bg = none, fg = malibu },
  }
else
  neovideSupport = {
    Normal           = { bg = none, fg = white },
    NormalNC         = { bg = none },
    NormalFloat      = { bg = none, fg = blue },
    MiniNotifyNormal = { bg = none, fg = malibu },
  }
end

function M.setup()
  -- No 'highlight clear' here: colors/myghtfly.lua, the colorscheme entrypoint,
  -- already clears highlights and resets syntax before setting g:colors_name.
  -- Clearing a second time from inside setup() wiped g:colors_name back to nil.
  --
  -- (The old guard was `if vim.fn.exists("syntax_on")`, always true in Lua
  -- because exists() returns 0 or 1 and 0 is truthy.)
  for key, value in pairs(groups) do
    vim.api.nvim_set_hl(0, key, value)
  end

  for key, value in pairs(neovideSupport) do
    vim.api.nvim_set_hl(0, key, value)
  end
end

-- =============================================================================
 M.icons_group = {
  -- Languages
  lua                    = { icon = '󰢱', hl = 'IconsBlue' },
  go                     = { icon = '󰟓', hl = 'IconsBlue'  },
  c                      = { icon = '󰙱', hl = 'IconsBlue'   },
  python                 = { icon = '󰌠', hl = 'IconsYellow' },
  perl                   = { icon = '', hl = 'IconsBlue'  },
  rust                   = { icon = '󱘗', hl = 'IconsOrange' },
  zig                    = { icon = '', hl = 'IconsOrange' },

  -- Misc
  dockerfile             = { icon = '󰡨', hl = 'IconsBlue'   },
  yaml                   = { icon = '', hl = 'IconsPurple' },
  markdown               = { icon = '󰍔', hl = 'IconsGrey'   },

  -- Shell
  bash                   = { icon = '', hl = 'IconsGrey'   },
  zsh                   = { icon = '', hl = 'IconsGrey'   },
  fish                   = { icon = '', hl = 'IconsGrey'   },
  shell                   = { icon = '', hl = 'IconsGrey'   },
  terminal                   = { icon = " ", hl = 'IconsGrey'   },

  -- Default icon
 default_icon        = { icon = '󰀵', hl = 'IconsBlue'},
 -- default_icon = { icon = "󰈚", hl = "StatusLine" },
}


return M
