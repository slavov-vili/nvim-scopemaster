local ScopeMaster = {}



local function get_cur_lnum()
    return vim.fn.line(".")
end

local function get_last_lnum()
    return vim.fn.line("$")
end

local function get_indent(lnum)
    return math.max(0, vim.fn.indent(lnum))
end

local function pad_line(text, pad_size)
    return string.rep(' ', pad_size) .. text
end

local function find_border(lnum, cur_indent, side)
    local increment = -1
    local next_lnum_finder = vim.fn.prevnonblank
    if side == "bot" then
        increment = 1
        next_lnum_finder = function (lnum)
            local nextnonblank = vim.fn.nextnonblank(lnum)
            return nextnonblank == 0 and get_last_lnum() + 1 or nextnonblank
        end
    end

    local next_indent = cur_indent
    local next_lnum = lnum
    while next_indent >= cur_indent and lnum > 0 and lnum <= get_last_lnum() do
        next_lnum = next_lnum_finder(next_lnum + increment)
        next_indent = get_indent(next_lnum)
    end

    return next_lnum
end



ScopeMaster.config = {
    scope_mode = "line",
    symbol = "|",
    highlight = "Comment",
    namespace = vim.api.nvim_create_namespace("IndentLevel"),
    greedy = true,
}



function ScopeMaster.setup(opts)
    ScopeMaster.config = vim.tbl_deep_extend("force", ScopeMaster.config, opts or {})
    ScopeMaster.register_autocommands()
    ScopeMaster.register_user_commands()
    ScopeMaster.draw()
end



function ScopeMaster.find_scope(lnum)
    local indent = get_indent(lnum)
    if ScopeMaster.config.scope_mode == "cursor" then
        indent = math.min(indent, vim.api.nvim_win_get_cursor(0)[2] + 1)
    end
    local top = find_border(lnum, indent, "top")
    local bot = find_border(lnum, indent, "bot")
    -- TODO: add config on whether to get top, bot or min or something?
    local border_indent = get_indent(top)
    return {
        indent = indent,
        border_indent = border_indent,
        top = top,
        bot = bot,
    }
end



function ScopeMaster.get_bot_border_for_draw(lnum)
    local lnum_for_draw = lnum - 1
    return ScopeMaster.config.greedy and lnum_for_draw or vim.fn.prevnonblank(lnum_for_draw)
end



function ScopeMaster.draw_scope()
    vim.api.nvim_buf_clear_namespace(0, ScopeMaster.config.namespace, 0, -1)

    local lnum = get_cur_lnum()
    if ScopeMaster.config.scope_mode == "" or get_indent(lnum) <= 0 then
        return
    end

    local scope = ScopeMaster.find_scope(lnum)
    print("Found scope: indent=" .. scope.indent .. ", top =" .. scope.top .. ", bot=" .. scope.bot)

    -- NOTE: extmarks are 0-based, but lnums are 1-based
    for lnum_extmark = scope.top, ScopeMaster.get_bot_border_for_draw(scope.bot) - 1 do
        local extmark_level = scope.border_indent
        local virt_text = ScopeMaster.config.symbol

        if vim.fn.col({lnum_extmark + 1, "$"}) < extmark_level then
            virt_text = pad_line(virt_text, extmark_level)
            extmark_level = 0
        end

        vim.api.nvim_buf_set_extmark(0, ScopeMaster.config.namespace, lnum_extmark, extmark_level, {
            virt_text = {
                { virt_text, ScopeMaster.config.highlight }
            },
            virt_text_pos = "overlay"
        })
    end
end



function ScopeMaster.draw()
    ScopeMaster.draw_scope()
end



function ScopeMaster.register_user_commands()
    vim.api.nvim_create_user_command("ScopeMasterDraw",
        function()
            ScopeMaster.draw()
        end,
    { desc = "Draws the current line's indentation scope" })
end



function ScopeMaster.register_autocommands()
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        callback = function() ScopeMaster.draw() end,
    })
end



return ScopeMaster
