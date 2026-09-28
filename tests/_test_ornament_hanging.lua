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

t.test("negative padding may take a piece behind the books beside it", function()
    -- Maintainer: tightening should be able to go behind the adjacent books.
    -- So the pieces paint before the books (after the plank and the recess),
    -- and the padding may go past the drawing's edge, down to half the piece.
    local rw = shelf:match("\nfunction SpineShelf%.rowWidget%(opts%)\n(.-)\nfunction SpineShelf%.")
    local g = rw:find("children[#children + 1] = group", 1, true)
    local o = rw:find("children[#children + 1] = ornament end", 1, true)
    local gp = rw:find("children[#children + 1] = gap_ornaments[_i]", 1, true)
    assert(g and o and gp and o < g and gp < g, "pieces are painted over the books")
    local rec = rw:find("if recess then children[#children + 1] = recess end", 1, true)
    assert(rec and rec < gp, "pieces are painted under the recess shading")
    local body = shelf:match("\n(function SpineShelf%.ornPad%(base, pl%)\n.-\nend)\n")
    local env = setmetatable({ SpineShelf = {} }, { __index = _G })
    local f
    if _G.setfenv then f = assert(loadstring(body)); setfenv(f, env) else f = assert(load(body, "p", "t", env)) end
    f()
    eq(env.SpineShelf.ornPad(10, { w = 100, pad_px = -30 }), -20, "tightening stopped short of the books")
    eq(env.SpineShelf.ornPad(10, { w = 100, pad_px = -500 }), -50, "a piece may not tighten past half its width")
    eq(env.SpineShelf.ornPad(10, { w = 100, pad_px = 5 }), 15)
end)

t.test("a tall standing piece stays in front of its own shelf while its top goes behind the one above", function()
    -- Device: growing a piece until it rose above its row made it pop behind
    -- its OWN shelf too: handed wholly to the row above, it was painted
    -- before its own plank. Now the row above paints it whole (behind that
    -- shelf) and its own row paints it again, cropped to the row, in front.
    local body = shelf:match("\n(function SpineShelf%.ownRowPart%(w_, Orn%)\n.-\nend)\n")
    assert(body, "no SpineShelf.ownRowPart")
    local env = setmetatable({ SpineShelf = {} }, { __index = _G })
    local f
    if _G.setfenv then f = assert(loadstring(body)); setfenv(f, env) else f = assert(load(body, "o", "t", env)) end
    f()
    local made
    local Orn = { Ornament = { new = function(_self, t) made = t; return t end } }
    local pl = { w = 100, h = 300, entry = {}, hang = false }
    local part = env.SpineShelf.ownRowPart({ placement = pl, night = false, overlap_offset = { 40, -120 } }, Orn)
    eq(part.overlap_offset[1], 40); eq(part.overlap_offset[2], 0, "the own-row copy does not start at the row's top")
    eq(part.placement.crop.y, 120, "the risen part is not cropped away")
    eq(part.placement.crop.h, 180)
    eq(part.placement.w, 100, "the copy lost the placement")
    assert(pl.crop == nil, "the shared placement was changed")
    eq(env.SpineShelf.ownRowPart({ placement = { w = 10, h = 10, hang = true }, overlap_offset = { 0, -5 } }, Orn), nil,
       "a hanging piece got an own-row copy")
    local rw = shelf:match("\nfunction SpineShelf%.rowWidget%(opts%)\n(.-)\nfunction SpineShelf%.")
    eq(select(2, rw:gsub("SpineShelf%.ownRowPart%(", "")), 4, "every slot must keep its own-row part")
end)

t.done()
