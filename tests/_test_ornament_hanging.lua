-- tests/_test_ornament_hanging.lua
-- A piece that hangs from the shelf above (maintainer, 5.3 review): the
-- height nudge still moves it, so a piece whose image has room above its
-- drawing can connect to the shelf; and it is painted BEHIND the shelf above
-- and its shadow, which means the row above paints it, before its plank.
-- Usage (from plugin root): lua tests/_test_ornament_hanging.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local helpers = dofile("tests/_helpers.lua")
local t, eq = helpers.runner(), helpers.eq
local widget = io.open("lib/bookshelf_widget.lua"):read("*a")
local shelf = io.open("lib/bookshelf_spine_shelf.lua"):read("*a")
local orn = io.open("lib/bookshelf_ornaments.lua"):read("*a")

local function extract(src, name)
    local pat = "\nfunction " .. name:gsub("[%.%(%)]", "%%%0") .. "\n(.-)\nend\n"
    local body = src:match(pat)
    assert(body, name .. " not found")
    return body
end

t.test("a hanging piece moves to the row above, first, one row pitch down", function()
    local hang = load("return function(self, rows, pitch)\n"
        .. extract(widget, "BookshelfWidget:_hangUnder(rows, pitch)") .. "\nend",
        "hang", "t", { ipairs = ipairs, table = table })()
    local plank1, plank2 = { name = "plank1" }, { name = "plank2" }
    local bat = { name = "bat", overlap_offset = { 900, -40 } }
    local rows = { { plank1 }, { plank2, _hanging = { bat } } }
    hang({}, rows, 300)
    eq(rows[1][1], bat, "not painted first by the row above (so before its plank)")
    eq(rows[1][2], plank1)
    eq(bat.overlap_offset[1], 900); eq(bat.overlap_offset[2], 260, "not moved down by the pitch")
    eq(#rows[2]._hanging, 0, "left behind in its own row too: painted twice")
    for _i, w in ipairs(rows[2]) do assert(w ~= bat, "still a child of its own row") end
end)

t.test("both ways a page is built hand them over", function()
    local n = select(2, widget:gsub("self:_hangUnder%(rows, ", ""))
    eq(n, 2, "the rebuild and the swap in place must both move hanging pieces")
    assert(widget:find("row_pitch            = shelf_h + grid_between", 1, true), "the swap has no pitch to use")
end)

t.test("the row keeps hanging pieces out of its own children, in all three slots", function()
    local n = select(2, shelf:gsub("hanging%[#hanging %+ 1%] = w_", ""))
    eq(n, 3, "row end, section gap and a lead piece at a row's start")
    assert(shelf:find("if ornament and SpineShelf.behindAbove(ornament.placement, ornament.overlap_offset[2], opts) then", 1, true), "bare plank")
    assert(shelf:find("row_group._hanging = hanging", 1, true))
end)

t.test("the height nudge moves a hanging piece (+ up, into the shelf above)", function()
    assert(shelf:find("- (pl.hang_lift or 0)", 1, true), "ornamentY ignores the nudge for a hanging piece")
    assert(orn:find("hang_lift = hang and math.floor((entry.lift or 0) * height + 0.5) or 0", 1, true))
end)

t.test("a piece that rises above its row goes behind the shelf above, like a hanging one", function()
    -- Maintainer: large pieces rose over the row above; like hanging pieces
    -- they should go behind the shelf above. Not on a page's first row: there
    -- is no shelf above to go behind.
    local body = shelf:match("\n(function SpineShelf%.behindAbove%(pl, y, opts%)\n.-\nend)\n")
    assert(body, "no SpineShelf.behindAbove")
    local env = setmetatable({ SpineShelf = {} }, { __index = _G })
    local f
    if _G.setfenv then f = assert(loadstring(body)); setfenv(f, env) else f = assert(load(body, "b", "t", env)) end
    f()
    local ba = env.SpineShelf.behindAbove
    eq(ba({ hang = true }, 10, { row_index = 2 }), true, "a hanging piece")
    eq(ba({ hang = false }, -5, { row_index = 2 }), true, "a piece rising above its row")
    eq(ba({ hang = false }, 0, { row_index = 2 }), false, "a piece within its row")
    eq(ba({ hang = false }, -5, { row_index = 1 }), false, "the first row has no shelf above")
    local rw = shelf:match("\nfunction SpineShelf%.rowWidget%(opts%)\n(.-)\nfunction SpineShelf%.")
    local n = select(2, rw:gsub("SpineShelf%.behindAbove%(", ""))
    eq(n, 4, "the row end, the section gap, the lead piece and the bare plank must all decide this way")
end)

t.done()
