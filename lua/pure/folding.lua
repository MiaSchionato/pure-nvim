local M = {}
local fold_group = vim.api.nvim_create_augroup("PureFoldingAuto", { clear = true })

-- -----------------------------------------------------------------------------
--- A markdown line as it reads: links as their text, [[a|b]] as b, the
--- checkbox as an icon. A synced Todoist task shows only the task itself,
--- without the link to it and the date / priority / project after it.
local function plainMarkdown(line)
    local box, rest = line:match("^[-*] %[(.)%] (.*)$")
    local icon = box and (box == " " and "󰄱 " or "󰄲 ") or ""
    -- A task with a [[link]] is written as its text and then [↗](url).
    local linked = rest and rest:match("^(.-)%s*%[↗%]%(https://app%.todoist%.com/app/task/")
    if linked and linked:find("[[", 1, true) then
        rest = linked
    else
        -- The task's own text may hold escaped brackets: \[1\].
        local task = rest and rest:match("^%[(.-)%]%(https://app%.todoist%.com/app/task/")
        if task then
            return icon .. task:gsub("\\([%[%]])", "%1")
        end
    end
    line = (box and (icon .. rest) or line)
        :gsub("%[%[([^%]|]-)|([^%]]-)%]%]", "%2")  -- [[target|alias]]
        :gsub("%[%[([^%]]-)%]%]", "%1")            -- [[note]]
        :gsub("%[([^%]]*)%]%b()", "%1")            -- [text](url)
    return line
end

-- -----------------------------------------------------------------------------
--  Folding tasks by state (<leader>zt / <leader>zT, asked for in the vault's
--  Improvment.md): the done tasks folded away to see what is left, or the
--  open ones to see what was done. A task's sub-items and indented lines go
--  with it; headings and other text stay. <leader>zr (M.auto) goes back.
--
--  vim.g.pure_tasks_done: the checkbox states that count as done, default
--  "xX-" (done, cancelled), as the vault's legend has them; every other
--  state ([ ], [~], [!], [>]...) is open.
-- -----------------------------------------------------------------------------

--- The state of the task on `line` (the character in its box), or nil.
local function taskState(line)
    return line:match("^%s*[-*+] %[(.)%]") or line:match("^%s*%d+[.)] %[(.)%]")
end

local function isDone(state)
    return (vim.g.pure_tasks_done or "xX-"):find(state, 1, true) ~= nil
end

--- Per line of `buf`: whether it belongs to a task that is folded away in
--- `mode` ('done' hides done tasks, 'open' hides open ones). Cached by
--- changedtick: foldexpr asks once per line.
local task_cache = {}
local function hiddenLines(buf, mode)
    local c = task_cache[buf]
    local tick = vim.b[buf].changedtick
    if c and c.tick == tick and c.mode == mode then return c.hidden end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local hidden = {}
    local i = 1
    while i <= #lines do
        local state = taskState(lines[i])
        if state and (isDone(state) == (mode == "done")) then
            -- The task and everything indented deeper under it.
            local indent = #lines[i]:match("^%s*")
            hidden[i] = true
            local j = i + 1
            while j <= #lines do
                local l = lines[j]
                if l:match("^%s*$") then
                    -- A blank line is the task's only when more of it follows.
                    local nxt = lines[j + 1]
                    if not nxt or nxt:match("^%s*$") or #nxt:match("^%s*") <= indent then break end
                elseif #l:match("^%s*") <= indent then
                    break
                end
                hidden[j] = true
                j = j + 1
            end
            i = j
        else
            i = i + 1
        end
    end
    task_cache[buf] = { tick = tick, mode = mode, hidden = hidden }
    return hidden
end

--- foldexpr while a task view is on: the hidden task lines are one fold.
function M.taskFoldExpr(lnum)
    local buf = vim.api.nvim_get_current_buf()
    return hiddenLines(buf, vim.w.pure_task_fold or "done")[lnum] and "1" or "0"
end

--- <leader>zt ('done') / <leader>zT ('open'): fold those tasks away; the
--- same key again goes back to the automatic folds.
function M.tasks(mode)
    if vim.w.pure_task_fold == mode then return M.auto() end
    local buf = vim.api.nvim_get_current_buf()
    local any = next(hiddenLines(buf, mode)) ~= nil
    if not any then
        return vim.notify(mode == "done" and "No done tasks to fold" or "No open tasks to fold")
    end
    -- The foldlevel of before, for M.auto to put back: this view closes
    -- every fold (0), and leaving it at 0 closed the whole note afterwards.
    if not vim.w.pure_task_fold then
        vim.w.pure_task_prev_foldlevel = vim.wo.foldlevel
        vim.w.pure_task_prev_foldminlines = vim.wo.foldminlines
    end
    -- A task of one line is a fold of one line, which 'foldminlines' (1)
    -- never closes: with the open tasks one line each, <leader>zT did nothing.
    vim.wo.foldminlines = 0
    vim.w.pure_task_fold = mode
    -- Through manual: from one task view to the other the foldexpr is the
    -- same string, and Neovim recomputes expr folds only when it changes.
    vim.wo.foldmethod = "manual"
    vim.wo.foldexpr = "v:lua.require'pure.folding'.taskFoldExpr(v:lnum)"
    vim.wo.foldmethod = "expr"
    vim.wo.foldlevel = 0
    -- Setting foldlevel to the 0 it already was (the other task view) does
    -- not close the new folds; zX applies it to them. Neovim recomputes the
    -- folds only when they are next asked for, so they are asked for first
    -- (foldlevel()), or zX works on the old ones.
    vim.fn.foldlevel(1)
    vim.cmd("normal! zX")
end

--- <leader>zz: open or close the fold that STARTS on this line. It was za,
--- which closes the fold around the line: on a list item of a markdown
--- note that is the whole section, and in the last section everything to
--- the end of the buffer went with it. A line where no fold starts (and
--- that is not in a closed one) is left alone.
function M.toggleHere()
    local lnum = vim.fn.line(".")
    if vim.fn.foldclosed(lnum) ~= -1 then return vim.cmd("normal! zo") end
    local here, above = vim.fn.foldlevel(lnum), lnum > 1 and vim.fn.foldlevel(lnum - 1) or 0
    if here > 0 and here > above then return vim.cmd("normal! zc") end
    vim.notify("No fold starts on this line", vim.log.levels.INFO)
end

-- Example: "function foo() ... 󰁂 15 lines"
function _G.PureFoldText()
    local pos = vim.v.foldstart
    local line = vim.api.nvim_buf_get_lines(0, pos - 1, pos, false)[1]
    local lines_count = vim.v.foldend - vim.v.foldstart + 1

    -- A fold of the task view says what it holds: "󰄲 5 done tasks".
    local mode = vim.w.pure_task_fold
    if mode then
        local n = 0
        for _, l in ipairs(vim.api.nvim_buf_get_lines(0, pos - 1, vim.v.foldend, false)) do
            local state = taskState(l)
            if state and isDone(state) == (mode == "done") then n = n + 1 end
        end
        local indent = line:match("^%s*")
        return ("%s%s %d %s task%s"):format(indent, mode == "done" and "󰄲" or "󰄱", n, mode, n == 1 and "" or "s")
    end

    local clean_line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if vim.bo.filetype == "markdown" then
        clean_line = plainMarkdown(clean_line)
    end

    -- "lines", not the Portuguese "linhas" it said: text in the code is
    -- English in this configuration.
    return clean_line .. " ... 󰁂 " .. lines_count .. " lines "
end

-- A folded line: no background, its text in the colorscheme's blue (the
-- Directory colour) instead of the solid Folded bar (Improvment.md). Set
-- again after every colorscheme, which would bring the bar back.
local function foldedHighlight()
    local dir = vim.api.nvim_get_hl(0, { name = "Directory", link = false })
    vim.api.nvim_set_hl(0, "Folded", { fg = dir.fg, bg = "NONE", ctermbg = "NONE" })
end
foldedHighlight()
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("PureFoldedHighlight", { clear = true }),
    callback = foldedHighlight,
})

-- Automatic folds for the current window: treesitter when the buffer has a
-- parser, indentation otherwise. Also what <leader>zr goes back to after
-- folding by hand; the manual folds are dropped then.
function M.auto()
    -- Out of the task view, if it was on, with the foldlevel of before it.
    if vim.w.pure_task_fold then
        vim.w.pure_task_fold = nil
        vim.wo.foldlevel = vim.w.pure_task_prev_foldlevel or vim.o.foldlevel
        vim.wo.foldminlines = vim.w.pure_task_prev_foldminlines or vim.o.foldminlines
    end
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
