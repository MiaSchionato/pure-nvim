local M = {}
local fold_group = vim.api.nvim_create_augroup("PureFoldingAuto", { clear = true })

-- -----------------------------------------------------------------------------
--- A markdown line as it reads: links as their text, [[a|b]] as b, the
--- checkbox as an icon. A synced Todoist task shows only the task itself,
--- without the link to it and the date / priority / project after it.
local function plainMarkdown(line)
    local box, rest = line:match("^[-*] %[(.)%] (.*)$")
    local icon = box and (box == " " and "󰄱 " or "󰄲 ") or ""
    -- The task's own text may hold escaped brackets: \[1\].
    local task = rest and rest:match("^%[(.-)%]%(https://app%.todoist%.com/app/task/")
    if task then
        return icon .. task:gsub("\\([%[%]])", "%1")
    end
    line = (box and (icon .. rest) or line)
        :gsub("%[%[([^%]|]-)|([^%]]-)%]%]", "%2")  -- [[target|alias]]
        :gsub("%[%[([^%]]-)%]%]", "%1")            -- [[note]]
        :gsub("%[([^%]]*)%]%b()", "%1")            -- [text](url)
    return line
end

-- Exemplo: "function foo() ... (15 lines)"
function _G.PureFoldText()
    local pos = vim.v.foldstart
    local line = vim.api.nvim_buf_get_lines(0, pos - 1, pos, false)[1]
    local lines_count = vim.v.foldend - vim.v.foldstart + 1

    local clean_line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if vim.bo.filetype == "markdown" then
        clean_line = plainMarkdown(clean_line)
    end

    return clean_line .. " ... 󰁂 " .. lines_count .. " linhas "
end

-- Automatic folds for the current window: treesitter when the buffer has a
-- parser, indentation otherwise. Also what <leader>zr goes back to after
-- folding by hand; the manual folds are dropped then.
function M.auto()
    local ok, parser = pcall(vim.treesitter.get_parser)

    -- The fallback used to sit *inside* the success branch, where `ok` is
    -- always true, so it was dead code and buffers without a parser kept
    -- whatever foldmethod happened to be set.
    if ok and parser then
        vim.opt_local.foldmethod = "expr"
        vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
    else
        vim.opt_local.foldmethod = "indent"
    end
end

vim.api.nvim_create_autocmd("FileType", {
    group = fold_group,
    pattern = "*",
    callback = M.auto,
})

return M
