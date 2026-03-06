local ScopeMaster = {}



local Condition = {
    equals = function(a, b) return a == b end,
    notequals = function(a, b) return a ~= b end,
    lessthan = function(a, b) return a < b end,
    morethan = function(a, b) return a > b end,
}



local U = {}

function U.force_value(val, min, max)
    return math.max(min, math.min(val, max))
end

function U.get_cur_lnum()
    return vim.fn.line(".")
end

function U.get_last_lnum()
    return vim.fn.line("$")
end

function U.get_lnum(lnum)
    return lnum == nil and U.get_cur_lnum() or lnum
end

function U.check_lnum(lnum)
    return lnum >= 1 and lnum <= U.get_last_lnum()
end

function U.force_lnum(lnum)
    return U.force_value(lnum, 1, U.get_last_lnum())
end

function U.is_empty_line(lnum)
    return vim.fn.col({lnum, "$"}) == 1
end

function U.get_indent(lnum)
    return vim.fn.indent(lnum)
end

function U.get_indent_size()
    return vim.fn.shiftwidth()
end

-- Returns the virtual column
function U.get_cur_col()
    return vim.fn.virtcol(".", 1)[1]
end

function U.force_col(lnum, col)
    return U.force_value(col, 0, U.get_indent(lnum))
end

function U.get_cur_pos()
    return { lnum = U.get_cur_lnum(), col = U.get_cur_col() }
end

function U.set_cur_pos(virt_pos)
    local lnum = U.force_lnum(virt_pos.lnum)
    local col = U.force_col(virt_pos.lnum, vim.fn.virtcol2col(0, virt_pos.lnum, virt_pos.col) - 1)
    vim.api.nvim_win_set_cursor(0, { lnum, col })
end

function U.add_to_jumplist()
    vim.cmd("normal! m'")
end

function U.make_preview_opts(border, border_lnum)
    local preview_lnum = vim.fn.line('w0')
    local preview_condition = Condition.lessthan
    local winrow = 0

    if 'bot' == border then
        preview_lnum = vim.fn.line('w$')
        preview_condition = Condition.morethan
        winrow = vim.api.nvim_win_get_height(0) - 1
    end

    return {
        preview_lnum = preview_lnum,
        should_preview = U.check_lnum(border_lnum) and preview_condition(border_lnum, preview_lnum),
        winrow = winrow,
    }
end



-- FIXME: add custom highlight?
ScopeMaster.config = {
    scope_mode = "line", -- one of: none, line, cursor
    border_preview = "both", -- one of: none, top, bot, both
    symbol = "|",
    highlight = "Comment",
    namespace = vim.api.nvim_create_namespace("ScopeMaster"),
    greedy = true,
    horizontal_wrap = true,
    vertical_wrap = true,
    text_objects = {
        around = "aS",
        inside = "iS",
    },
    motions = {
        scope_left = "g[",
        scope_right = "g]",
        scope_start = "g(",
        scope_end = "g)",
        scope_prev = "g<",
        scope_next = "g>",
        sibling_prev = "g{",
        sibling_next = "g}",
    },
}



function ScopeMaster.setup(opts)
    ScopeMaster.config = vim.tbl_deep_extend("force", ScopeMaster.config, opts or {})
    -- FIXME: add checks for config values
    ScopeMaster.create_autocmds()
    ScopeMaster.create_user_commands()
    ScopeMaster.create_motions()
    ScopeMaster.create_text_objects()
    ScopeMaster.draw()
end



function ScopeMaster.create_autocmds()
    local function create(events, callback)
        vim.api.nvim_create_autocmd(events, {
            callback = callback,
        })
    end

    create({ "CursorMoved", "CursorMovedI" }, ScopeMaster.draw)

    create({ "BufWinEnter" }, ScopeMaster.draw)

    create({ "WinClosed" }, ScopeMaster.undraw)
end



function ScopeMaster.create_user_commands()
    local function create(name, func, description)
        vim.api.nvim_create_user_command(name, func, { desc = description })
    end

    create("ScopeMasterSelectA",
        function() ScopeMaster.select_scope(true) end,
        "Selects around the current line's indentation scope"
    )

    create("ScopeMasterSelectI",
        function() ScopeMaster.select_scope() end,
        "Selects inside the current line's indentation scope"
    )

    create("ScopeMasterDraw",
        function() ScopeMaster.draw() end,
        "Draws the current line's indentation scope"
    )

    create("ScopeMasterUndraw",
        function() ScopeMaster.undraw() end,
        "Undraws the current line's indentation scope"
    )
end



function ScopeMaster.create_text_objects()
    vim.keymap.set({'o', 'x'}, ScopeMaster.config.text_objects.around,
        function() ScopeMaster.select_scope(true) end,
        { desc = 'Around current scope' }
    )

    vim.keymap.set({'o', 'x'}, ScopeMaster.config.text_objects.inside,
        function() ScopeMaster.select_scope() end,
        { desc = 'Inside current scope' }
    )
end



function ScopeMaster.select_scope(around)
    local scope = ScopeMaster.find_scope()
    local top = around and scope.top or scope.top + 1
    local bot = around and scope.bot or scope.bot - 1

    local col = U.get_cur_pos().col

    vim.cmd("normal! V")
    U.set_cur_pos({lnum = bot, col = col})
    vim.cmd("normal! o")
    U.set_cur_pos({lnum = top, col = col})
end



function ScopeMaster.create_motions()
    function create(keymap, func, desc)
        if keymap then
            vim.keymap.set({'n','o','x'}, keymap, func, { desc = desc })
        end
    end

    create(ScopeMaster.config.motions.scope_left,
        function() ScopeMaster.goto_scope_horizontal("left", ScopeMaster.config.horizontal_wrap) end,
        'Go to the next scope to the left'
    )

    create(ScopeMaster.config.motions.scope_right,
        function() ScopeMaster.goto_scope_horizontal("right", ScopeMaster.config.horizontal_wrap) end,
        'Go to the next scope to the right'
    )

    create(ScopeMaster.config.motions.scope_start,
        function() ScopeMaster.goto_scope_end("top") end,
        'Go to the start of the current scope'
    )

    create(ScopeMaster.config.motions.scope_end,
        function() ScopeMaster.goto_scope_end("bot") end,
        'Go to the end of the current scope'
    )

    create(ScopeMaster.config.motions.scope_prev,
        function() ScopeMaster.goto_scope_vertical("up",
            {
                condition = Condition.lessthan,
                bounded = true,
                wrap = false,
            }, true)
        end,
        'Go to the end of the parent scope'
    )

    create(ScopeMaster.config.motions.scope_next,
        function() ScopeMaster.goto_scope_vertical("down",
            {
                condition = Condition.morethan,
                bounded = true,
                wrap = false,
            }, true)
        end,
        'Go to the beginning of the next child scope'
    )

    create(ScopeMaster.config.motions.sibling_prev,
        function() ScopeMaster.goto_scope_vertical("up",
            {
                condition = Condition.equals,
                bounded = true,
                wrap = true,
            }, true)
        end,
        'Go to the previous sibling scope'
    )

    create(ScopeMaster.config.motions.sibling_next,
        function() ScopeMaster.goto_scope_vertical("down",
            {
                condition = Condition.equals,
                bounded = true,
                wrap = true,
            }, true)
        end,
        'Go to the next sibling indentation scope'
    )
end



function ScopeMaster.goto_scope_horizontal(direction, wrap)
    local pos = U.get_cur_pos()
    if U.is_empty_line(pos.lnum) then
        return
    end

    local indent_size = U.get_indent_size()
    local increment = direction == "right" and 1 or -1

    local max_indent_level = math.floor(U.get_indent(pos.lnum) / indent_size)
    local cur_indent_level = math.floor(pos.col / indent_size)
    local next_level = cur_indent_level + vim.v.count1 * increment
    if wrap then
        next_level = next_level % (max_indent_level + 1)
    end
    pos.col = next_level * indent_size + 1
    U.set_cur_pos(pos)
end



function ScopeMaster.goto_scope_vertical(direction, search_opts, is_jump)
    local increment = 1
    local next_line = vim.fn.nextnonblank
    if direction == "up" then
        increment = -1
        next_line = vim.fn.prevnonblank
    end

    local lnum = U.get_cur_lnum()
    local bounds = ScopeMaster.get_scope_bounds(lnum)

    local next_lnum = lnum
    local next_indent = nil
    for _ = 1, vim.v.count1 do
        local indent = ScopeMaster.get_indent_for_scope(next_lnum)

        -- FIXME: what is this here for?
        -- prevents infinite loops ?
        -- indent = indent == 0 and -1 or indent

        while true do
            next_lnum = next_line(next_lnum + increment)
            next_indent = ScopeMaster.get_indent_for_scope(next_lnum)

            if (not U.check_lnum(next_lnum)) then
                print("Line check was false!")
                next_lnum = lnum
                break
            end

            if search_opts.condition(next_indent, indent) then
                break
            end

            if search_opts.bounded then
                -- FIXME: do this for wrapping, bounding just leaves things as they are!
                if next_lnum > bounds.bot then
                    next_lnum = search_opts.wrap and bounds.top or lnum
                    break
                elseif next_lnum < bounds.top then
                    next_lnum = search_opts.wrap and bounds.bot or lnum
                    break
                end
            end
        end
    end

    local pos = U.get_cur_pos()
    pos.lnum = next_lnum
    pos.col = next_indent + 1
    if is_jump then
        U.add_to_jumplist()
    end
    U.set_cur_pos(pos)
end



function ScopeMaster.goto_scope_end(border)
    local pos = U.get_cur_pos()
    local scope = ScopeMaster.find_scope(pos.lnum)
    pos.lnum = ScopeMaster.get_scope_end(scope, border)
    pos.col = pos.col
    U.add_to_jumplist()
    U.set_cur_pos(pos)
end



function ScopeMaster.get_scope_end(scope, border)
    local lnum_border = scope[border]
    if border == "bot" then
        local lnum_end = lnum_border - 1
        return ScopeMaster.config.greedy and vim.fn.prevnonblank(lnum_end) or lnum_end
    end

    return scope["top"] + 1
end



function ScopeMaster.get_indent_for_scope(lnum)
    local indent = U.get_indent(lnum)
    if ScopeMaster.config.scope_mode == "cursor" then
        indent = math.min(indent, U.get_cur_col())
        local indent_size = U.get_indent_size()
        indent = math.ceil(indent / indent_size) * indent_size
    end
    return indent
end



-- TODO: Add configuration for maximum lines to search?
function ScopeMaster.find_border(lnum, cur_indent, direction)
    local increment = -1
    local next_lnum_finder = vim.fn.prevnonblank
    if direction == "down" then
        increment = 1
        next_lnum_finder = function (prev_lnum)
            local next_lnum = ScopeMaster.config.greedy and vim.fn.nextnonblank(prev_lnum) or prev_lnum + 1
            return next_lnum == 0 and U.get_last_lnum() + 1 or next_lnum
        end
    end


    local next_lnum = lnum
    local next_indent = cur_indent
    repeat
        next_lnum = next_lnum_finder(next_lnum + increment)
        next_indent = U.get_indent(next_lnum)
    until not U.check_lnum(next_lnum) or next_indent < cur_indent

    return next_lnum
end



function ScopeMaster.find_scope(lnum)
    local lnum = U.get_lnum(lnum)
    if U.is_empty_line(lnum) then
        return ScopeMaster.find_scope(vim.fn.prevnonblank(lnum))
    end
    local indent = ScopeMaster.get_indent_for_scope(lnum)

    local top = ScopeMaster.find_border(lnum, indent, "up")
    local bot = ScopeMaster.find_border(lnum, indent, "down")
    return {
        indent = indent,
        top = top,
        bot = bot,
    }
end



function ScopeMaster.get_scope_bounds(lnum)
    local bounds = ScopeMaster.find_scope(lnum)
    bounds.top = bounds.top + 1
    bounds.bot = bounds.bot - 1
    return bounds
end



function ScopeMaster.draw_a_border(scope, border)
    local border_lnum = scope[border]
    local preview_opts = U.make_preview_opts(border, border_lnum)
    local winid = nil

    if preview_opts and preview_opts.should_preview then
        winid = vim.api.nvim_open_win(0, false, {
            relative = 'win',
            row = preview_opts.winrow,
            col = 0,
            width = vim.api.nvim_win_get_width(0),
            height = 1,
            focusable = false,
            mouse = true,
            zindex = 90,
            noautocmd = true,
        })
        vim.api.nvim_win_set_cursor(winid, { U.force_lnum(border_lnum), 0 })
    end

    return winid
end



function ScopeMaster.get_border_preview_winids()
    local winids = vim.w.scopemaster_border_winids
    return winids and winids or {}
end

function ScopeMaster.set_border_preview_winid(border, winid)
    local winids = vim.w.scopemaster_border_winids
    winids = winids and winids or {}
    winids[border] = winid
    vim.w.scopemaster_border_winids = winids
end



function ScopeMaster.undraw_borders()
    for border, winid in pairs(ScopeMaster.get_border_preview_winids()) do
        vim.api.nvim_win_close(winid, true)
        ScopeMaster.set_border_preview_winid(border, nil)
    end
end



function ScopeMaster.draw_borders(scope)
    ScopeMaster.undraw_borders()

    local border_preview = ScopeMaster.config.border_preview
    for _, border in ipairs({ 'top', 'bot' }) do
        if border_preview == 'both' or border_preview == border then
            local winid = ScopeMaster.draw_a_border(scope, border)
            ScopeMaster.set_border_preview_winid(border, winid)
        end
    end
end



function ScopeMaster.undraw_scope()
    vim.api.nvim_buf_clear_namespace(0, ScopeMaster.config.namespace, 0, -1)
end



function ScopeMaster.draw_scope(scope)
    -- TODO: only clear if scope changes?
    ScopeMaster.undraw_scope()

    if scope.indent <= 0 then
        return
    end

    -- NOTE: extmarks are 0-based, but lnums are 1-based
    -- although top is the border, the extmark is drawn on the next line
    -- Bot needs to be decremented
    for i = scope.top, ScopeMaster.get_scope_end(scope, "bot") - 1, 1 do
        local extmark_level = scope.indent - U.get_indent_size()
        local virt_text = ScopeMaster.config.symbol

        vim.api.nvim_buf_set_extmark(0, ScopeMaster.config.namespace, i, 0, {
            virt_text = { { virt_text, ScopeMaster.config.highlight } },
            virt_text_win_col = extmark_level
        })
    end
end



function ScopeMaster.undraw()
    ScopeMaster.undraw_scope()
    ScopeMaster.undraw_borders()
end



function ScopeMaster.draw()
    local lnum = U.get_cur_lnum()
    local scope = nil
    if ScopeMaster.config.scope_mode == "line" or ScopeMaster.config.scope_mode == "cursor" then
        scope = scope and scope or ScopeMaster.find_scope(lnum)
        ScopeMaster.draw_scope(scope)
    end

    if ScopeMaster.config.border_preview == "top" or ScopeMaster.config.border_preview == "bot"
        or ScopeMaster.config.border_preview == "both" then
        scope = scope and scope or ScopeMaster.find_scope(lnum)
        ScopeMaster.draw_borders(scope)
    end
end



return ScopeMaster
