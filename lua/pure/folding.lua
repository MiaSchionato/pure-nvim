local M = {}
local fold_group = vim.api.nvim_create_augroup("PureFoldingAuto", { clear = true })

-- -----------------------------------------------------------------------------
-- Exemplo: "function foo() ... (15 lines)"
function _G.PureFoldText()
    local pos = vim.v.foldstart
    local line = vim.api.nvim_buf_get_lines(0, pos - 1, pos, false)[1]
    local lines_count = vim.v.foldend - vim.v.foldstart + 1

    local clean_line = line:gsub("^%s+", ""):gsub("%s+$", "")

    return clean_line .. " ... 󰁂 " .. lines_count .. " linhas "
end

vim.api.nvim_create_autocmd("FileType", {
    group = fold_group,
    pattern = "*",
    callback = function()
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
})

return M
