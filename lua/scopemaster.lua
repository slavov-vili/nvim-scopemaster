local ScopeMaster = {}



local function get_cur_lnum()
    return vim.fn.line(".")
end

local function get_cur_col()
    return vim.fn.virtcol(".", 1)[1]
end

local function get_cur_pos()
    return vim.fn.getpos(".")
end

local function set_cur_pos(new_pos)
    vim.fn.setpos(".", new_pos)
end


local function get_last_lnum()
    return vim.fn.line("$")
end

local function get_lnum(lnum)
    return lnum == nil and get_cur_lnum() or lnum
end

local function get_indent_size()
    return vim.fn.shiftwidth()
end

local function get_indent(lnum)
    return vim.fn.indent(lnum)
end

local function is_empty_line(lnum)
    return vim.fn.col({lnum, "$"}) == 1
end

local function get_padding(pad_size)
    return string.rep(' ', pad_size)
end

local function add_to_jumplist()
    vim.cmd("normal! m'")
end

local function find_border(lnum, cur_indent, direction)
    local increment = -1
    local next_lnum_finder = vim.fn.prevnonblank
    if direction == "down" then
        increment = 1
        next_lnum_finder = function (lnum)
            local nextnonblank = vim.fn.nextnonblank(lnum)
            return nextnonblank == 0 and get_last_lnum() + 1 or nextnonblank
        end
    end

    local next_lnum = lnum
    local next_indent = cur_indent
    repeat
        next_lnum = next_lnum_finder(next_lnum + increment)
        next_indent = get_indent(next_lnum)
    until next_indent < cur_indent

    return next_lnum
end



local Condition = {}
Condition.equals = function(a, b) return a == b end
Condition.notequals = function(a, b) return a ~= b end



ScopeMaster.config = {
    scope_mode = "line",
    symbol = "|",
    highlight = "Comment",
    namespace = vim.api.nvim_create_namespace("ScopeMaster"),
    greedy = true,
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
    ScopeMaster.create_autocmds()
    ScopeMaster.create_user_commands()
    ScopeMaster.create_motions()
    ScopeMaster.create_text_objects()
    ScopeMaster.draw()
end



function ScopeMaster.create_autocmds()
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        callback = function() ScopeMaster.draw() end,
    })
end



function ScopeMaster.create_user_commands()

    vim.api.nvim_create_user_command("ScopeMasterSelectA",
        function()
            ScopeMaster.select_scope(true)
        end,
    { desc = "Selects around the current line's indentation scope" })

    vim.api.nvim_create_user_command("ScopeMasterSelectI",
        function()
            ScopeMaster.select_scope()
        end,
    { desc = "Selects inside the current line's indentation scope" })

    vim.api.nvim_create_user_command("ScopeMasterDraw",
        function()
            ScopeMaster.draw()
        end,
    { desc = "Draws the current line's indentation scope" })
end



function ScopeMaster.create_text_objects()
    vim.keymap.set({'o', 'x'}, ScopeMaster.config.text_objects.around, function()
      ScopeMaster.select_scope(true)
    end, {desc = 'Around current scope'})

    vim.keymap.set({'o', 'x'}, ScopeMaster.config.text_objects.inside, function()
      ScopeMaster.select_scope()
    end, {desc = 'Inside current scope'})
end



function ScopeMaster.select_scope(around)
    local scope = ScopeMaster.find_scope()
    local top = around and scope.top or scope.top + 1
    local bot = around and scope.bot or scope.bot - 1

    vim.cmd("normal! V")
    set_cur_pos({0, top, 1, 0})
    vim.cmd("normal! o")
    set_cur_pos({0, bot, 1, 0})
end



-- FIXME: motions should work with virtual columns, not indent size
function ScopeMaster.create_motions()
    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_left,
    function() ScopeMaster.goto_scope_horizontal("left") end,
    'Go to the next scope to the left')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_right,
    function() ScopeMaster.goto_scope_horizontal("right") end,
    'Go to the next scope to the right')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_start,
    function() ScopeMaster.goto_scope_end("top") end,
    'Go to the top end of the current scope')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_end,
    function() ScopeMaster.goto_scope_end("bot") end,
    'Go to the bot end of the current scope')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_prev,
    function() ScopeMaster.goto_scope_vertical("up", Condition.notequals) end,
    'Go to the end of the previous differing scope')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_next,
    function() ScopeMaster.goto_scope_vertical("down", Condition.notequals) end,
    'Go to the beginning of the next differing indentation scope')

    ScopeMaster.create_motion(ScopeMaster.config.motions.sibling_prev,
    function() ScopeMaster.goto_scope_vertical("up", Condition.equals, true) end,
    'Go to the previous sibling scope')

    ScopeMaster.create_motion(ScopeMaster.config.motions.sibling_next,
    function() ScopeMaster.goto_scope_vertical("down", Condition.equals, true) end,
    'Go to the next sibling indentation scope')
end

function ScopeMaster.create_motion(keymap, func, desc)
    if keymap then
        vim.keymap.set({'n','o','x'}, keymap, func, { desc = desc })
    end
end



function ScopeMaster.goto_scope_horizontal(direction)
    local lnum = get_cur_lnum()
    local indent_size = get_indent_size()
    local max_indent = get_indent(lnum)

    local limit_enforcer = function(next_indent) return math.max(0, next_indent) end
    local increment = -indent_size
    if direction == "right" then
        limit_enforcer = function(next_indent) return math.min(max_indent, next_indent) end
        increment = indent_size
    end

    local count = vim.v.count1
    local pos = get_cur_pos()
    local next_indent = pos[3] + count * increment
    next_indent = next_indent - (next_indent % indent_size)
    pos[2] = lnum
    pos[3] = limit_enforcer(next_indent) + 1
    set_cur_pos(pos)
end



function ScopeMaster.goto_scope_vertical(direction, condition, is_jump)
    local next_line = vim.fn.nextnonblank
    local increment = 1
    if direction == "up" then
        next_line = vim.fn.prevnonblank
        increment = -1
    end

    local lnum = get_cur_lnum()
    local next_indent = nil
    for _ = 1, vim.v.count1 do
        local indent = get_indent(lnum)
        repeat
            lnum = next_line(lnum + increment)
            next_indent = get_indent(lnum)
        until condition(indent, next_indent)
    end

    local pos = get_cur_pos()
    pos[2] = lnum
    pos[3] = next_indent + 1
    if is_jump then
        add_to_jumplist()
    end
    set_cur_pos(pos)
end



-- FIXME: empty lines are always at cursor position 0, which breaks things... (going from indent 8 to empty line, now can't go back, because the line is at 0)
function ScopeMaster.goto_scope_end(border)
    local pos = get_cur_pos()
    local scope = ScopeMaster.find_scope(pos[2])
    pos[2] = ScopeMaster.get_scope_end(scope, border)
    add_to_jumplist()
    set_cur_pos(pos)
end



function ScopeMaster.get_scope_end(scope, border)
    local lnum_border = scope[border]
    if border == "bot" then
        local lnum_end = lnum_border - 1
        return ScopeMaster.config.greedy and lnum_end or vim.fn.prevnonblank(lnum_end)
    end

    return scope["top"] + 1
end



function ScopeMaster.get_indent_for_scope(lnum)
    -- local lnum = is_empty_line(lnum) and vim.fn.prevnonblank(lnum - 1) or lnum
    local indent = get_indent(lnum)
    if ScopeMaster.config.scope_mode == "cursor" then
        -- print("Indent = " .. indent .. ", cur_col = " .. get_cur_col())
        indent = math.min(indent, get_cur_col())
        local indent_size = get_indent_size()
        indent = math.ceil(indent / indent_size) * indent_size
        -- print("ceil(indent / indent_size) * indent_size = " .. indent .. ", with indent_size = " .. indent_size)
    end
    return indent
end



function ScopeMaster.find_scope(lnum)
    local lnum = get_lnum(lnum)
    local indent = ScopeMaster.get_indent_for_scope(lnum)

    local top = find_border(lnum, indent, "up")
    local bot = find_border(lnum, indent, "down")
    return {
        indent = indent,
        top = top,
        bot = bot,
    }
end



function ScopeMaster.draw_scope(lnum)
    -- FIXME: only clear if indent changes?
    vim.api.nvim_buf_clear_namespace(0, ScopeMaster.config.namespace, 0, -1)

    if ScopeMaster.config.scope_mode == "" then
        return
    end

    local scope = ScopeMaster.find_scope(lnum)
    if scope.indent == 0 then
        return
    end

    -- print("Found scope: indent=" .. scope.indent .. ", top =" .. scope.top .. ", bot=" .. scope.bot)

    -- NOTE: extmarks are 0-based, but lnums are 1-based
    -- although top is the border, the extmark is drawn on the next line
    -- Bot needs to be decremented
    for lnum_extmark = scope.top, ScopeMaster.get_scope_end(scope, "bot") - 1 do
        local extmark_level = scope.indent - get_indent_size()
        local virt_text = ScopeMaster.config.symbol
        -- print("Drawing extmark at " .. lnum_extmark .. ", " .. extmark_level)

        -- if is_empty_line(lnum_extmark + 1) then
        --     virt_text = get_padding(extmark_level) .. virt_text
        --     extmark_level = 0
        -- end

        vim.api.nvim_buf_set_extmark(0, ScopeMaster.config.namespace, lnum_extmark, 0, {
            virt_text = { { virt_text, ScopeMaster.config.highlight } },
            virt_text_win_col = extmark_level
        })
    end




end



function ScopeMaster.draw()
    ScopeMaster.draw_scope(get_cur_lnum())
end



return ScopeMaster
