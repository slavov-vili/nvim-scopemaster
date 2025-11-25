local ScopeMaster = {}



local function get_cur_lnum()
    return vim.fn.line(".")
end

local function get_last_lnum()
    return vim.fn.line("$")
end

local function get_lnum(lnum)
    return lnum == nil and get_cur_lnum() or lnum
end

local function check_lnum(lnum)
    return lnum >= 1 and lnum <= get_last_lnum()
end


local function force_lnum(lnum)
    return math.max(1, math.min(lnum, get_last_lnum()))
end

local function is_empty_line(lnum)
    return vim.fn.col({lnum, "$"}) == 1
end

local function get_indent(lnum)
    return vim.fn.indent(lnum)
end

local function get_indent_size()
    return vim.fn.shiftwidth()
end

-- Returns the virtual column
local function get_cur_col()
    return vim.fn.virtcol(".", 1)[1]
end

local function force_col(lnum, col)
    return math.max(0, math.min(col, get_indent(lnum)))
end

local function get_cur_pos()
    return { lnum = get_cur_lnum(), col = get_cur_col() }
end

local function set_cur_pos(virt_pos)
    local lnum = force_lnum(virt_pos.lnum)
    local col = force_col(virt_pos.lnum, vim.fn.virtcol2col(0, virt_pos.lnum, virt_pos.col) - 1)
    vim.api.nvim_win_set_cursor(0, { lnum, col })
end

local function add_to_jumplist()
    vim.cmd("normal! m'")
end



local Condition = {}
Condition.equals = function(a, b) return a == b end
Condition.notequals = function(a, b) return a ~= b end
Condition.lessthan = function(a, b) return a < b end
Condition.morethan = function(a, b) return a > b end



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

    local col = get_cur_pos().col

    vim.cmd("normal! V")
    set_cur_pos({lnum = bot, col = col})
    vim.cmd("normal! o")
    set_cur_pos({lnum = top, col = col})
end



function ScopeMaster.create_motions()
    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_left,
    function() ScopeMaster.goto_scope_horizontal("left") end,
    'Go to the next scope to the left')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_right,
    function() ScopeMaster.goto_scope_horizontal("right") end,
    'Go to the next scope to the right')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_start,
    function() ScopeMaster.goto_scope_end("top") end,
    'Go to the start of the current scope')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_end,
    function() ScopeMaster.goto_scope_end("bot") end,
    'Go to the end of the current scope')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_prev,
    function() ScopeMaster.goto_scope_vertical("up", Condition.lessthan) end,
    'Go to the end of the parent scope')

    ScopeMaster.create_motion(ScopeMaster.config.motions.scope_next,
    function() ScopeMaster.goto_scope_vertical("down", Condition.morethan) end,
    'Go to the beginning of the next child scope')

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
    local pos = get_cur_pos()
    if is_empty_line(pos.lnum) then
        return
    end

    local indent_size = get_indent_size()
    local increment = direction == "right" and 1 or -1

    local max_indent_level = math.floor(get_indent(pos.lnum) / indent_size)
    local cur_indent_level = math.floor(pos.col / indent_size)
    local next_level = (cur_indent_level + vim.v.count1 * increment) % (max_indent_level + 1)
    pos.col = next_level * indent_size + 1
    set_cur_pos(pos)
end



-- TODO: wrap around at each end? Watch out for when not equal?
-- FIXME: add flag for only searching within the scope?
function ScopeMaster.goto_scope_vertical(direction, condition, is_jump)
    local increment = 1
    local next_line = vim.fn.nextnonblank
    if direction == "up" then
        increment = -1
        next_line = vim.fn.prevnonblank
    end

    local lnum = get_cur_lnum()
    local next_indent = nil
    for _ = 1, vim.v.count1 do
        local indent = ScopeMaster.get_indent_for_scope(lnum)
        indent = indent == 0 and -1 or indent
        repeat
            lnum = next_line(lnum + increment)
            next_indent = ScopeMaster.get_indent_for_scope(lnum)
        until lnum <= 0 or condition(next_indent, indent)
    end

    if lnum == 0 then
        return
    end

    local pos = get_cur_pos()
    pos.lnum = lnum
    pos.col = next_indent + 1
    if is_jump then
        add_to_jumplist()
    end
    set_cur_pos(pos)
end



function ScopeMaster.goto_scope_end(border)
    local pos = get_cur_pos()
    local scope = ScopeMaster.find_scope(pos.lnum)
    pos.lnum = ScopeMaster.get_scope_end(scope, border)
    pos.col = pos.col
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
    local indent = get_indent(lnum)
    if ScopeMaster.config.scope_mode == "cursor" then
        indent = math.min(indent, get_cur_col())
        local indent_size = get_indent_size()
        indent = math.ceil(indent / indent_size) * indent_size
    end
    return indent
end



-- Add configuration for maximum lines to search
function ScopeMaster.find_border(lnum, cur_indent, direction)
    local increment = -1
    local next_lnum_finder = vim.fn.prevnonblank
    if direction == "down" then
        increment = 1
        next_lnum_finder = function (lnum)
            local next_lnum = ScopeMaster.config.greedy and vim.fn.nextnonblank(lnum) or lnum + 1
            return next_lnum == 0 and get_last_lnum() + 1 or next_lnum
        end
    end


    local next_lnum = lnum
    local next_indent = cur_indent
    repeat
        next_lnum = next_lnum_finder(next_lnum + increment)
        next_indent = get_indent(next_lnum)
    until not check_lnum(next_lnum) or next_indent < cur_indent

    return next_lnum
end



function ScopeMaster.find_scope(lnum)
    local lnum = get_lnum(lnum)
    if is_empty_line(lnum) then
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



function ScopeMaster.draw_scope(lnum)
    -- TODO: only clear if scope changes?
    vim.api.nvim_buf_clear_namespace(0, ScopeMaster.config.namespace, 0, -1)

    if ScopeMaster.config.scope_mode == "" then
        return
    end

    local scope = ScopeMaster.find_scope(lnum)
    if scope.indent <= 0 then
        return
    end

    -- NOTE: extmarks are 0-based, but lnums are 1-based
    -- although top is the border, the extmark is drawn on the next line
    -- Bot needs to be decremented
    for i = scope.top, ScopeMaster.get_scope_end(scope, "bot") - 1, 1 do
        local extmark_level = scope.indent - get_indent_size()
        local virt_text = ScopeMaster.config.symbol

        vim.api.nvim_buf_set_extmark(0, ScopeMaster.config.namespace, i, 0, {
            virt_text = { { virt_text, ScopeMaster.config.highlight } },
            virt_text_win_col = extmark_level
        })
    end
end



function ScopeMaster.draw()
    ScopeMaster.draw_scope(get_cur_lnum())
end



return ScopeMaster
