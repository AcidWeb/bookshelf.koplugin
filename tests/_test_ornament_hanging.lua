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
    assert(shelf:find("row_group._hanging, row_group._orn_list = hanging, orn_list", 1, true))
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
    eq(ba({}, -5, { row_index = 2 }), true, "a piece rising above its row")
    eq(ba({}, 0, { row_index = 2 }), false, "a piece within its row")
    eq(ba({}, -5, { row_index = 1 }), false, "the first row has no shelf above")
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
    local pl = { w = 100, h = 300, entry = {} }
    local part = env.SpineShelf.ownRowPart({ placement = pl, night = false, overlap_offset = { 40, -120 } }, Orn)
    eq(part.overlap_offset[1], 40); eq(part.overlap_offset[2], 0, "the own-row copy does not start at the row's top")
    eq(part.placement.crop.y, 120, "the risen part is not cropped away")
    eq(part.placement.crop.h, 180)
    eq(part.placement.w, 100, "the copy lost the placement")
    assert(pl.crop == nil, "the shared placement was changed")
    eq(env.SpineShelf.ownRowPart({ placement = { w = 10, h = 10 }, overlap_offset = { 0, 5 } }, Orn), nil,
       "a piece within its row got an own-row copy")
    local rw = shelf:match("\nfunction SpineShelf%.rowWidget%(opts%)\n(.-)\nfunction SpineShelf%.")
    eq(select(2, rw:gsub("SpineShelf%.ownRowPart%(", "")), 4, "every slot must keep its own-row part")
end)

t.test("height is a place between the two shelves: 100% meets the shelf above whatever the sizes", function()
    -- Maintainer: a piece set to just touch the shelf above drifted off it
    -- when the shelf size or row count changed, because height was measured
    -- in the piece's own height. Now 0 = standing, 1 = the DRAWING's top (its
    -- transparent top room skipped) against the underside of the shelf above,
    -- worked out from the actual geometry each paint.
    local body = shelf:match("\n(function SpineShelf%.ornamentY%(pl, stand_h, opts%)\n.-\nend)\n")
    assert(body, "ornamentY not found")
    local env = setmetatable({ SpineShelf = {}, Screen = { scaleBySize = function(_s, v) return v end } },
                             { __index = _G })
    local f
    if _G.setfenv then f = assert(loadstring(body)); setfenv(f, env) else f = assert(load(body, "y", "t", env)) end
    f()
    local Y = env.SpineShelf.ornamentY
    for _i, g in ipairs({ { stand = 280, head = 40 }, { stand = 190, head = 30 }, { stand = 400, head = 60 } }) do
        local pl = { above = 200, h = 200, t = 1, content_top = 25 }
        local top = Y(pl, g.stand, { lift_headroom = g.head })
        eq(top + pl.content_top, -(g.head + 2), "100% does not meet the shelf above at stand " .. g.stand)
        pl.t = 0
        eq(Y(pl, g.stand, { lift_headroom = g.head }), g.stand - 200, "0% is not standing")
        pl.t = 0.5
        local mid = Y(pl, g.stand, { lift_headroom = g.head })
        local lo, hi = g.stand - 200, -(g.head + 2) - 25
        assert(math.abs(mid - (lo + hi) / 2) <= 1, "50% is not halfway")
    end
    local pl = { above = 200, h = 200, t = -0.2, content_top = 0 }
    assert(Y(pl, 280, { lift_headroom = 40 }) > 80, "below 0% does not dangle")
    assert(not shelf:find("hang_lift", 1, true), "the old hang offset is still read")
end)

t.test("a height is corrected to the real gap between rows before anything is handed up", function()
    -- Rig: a piece at 100% stopped short of the shelf above by the screen
    -- slack GridMargins spreads between rows, which is only known after the
    -- rows are built. Each row notes its pieces off 0% with the gap they
    -- were built against; _hangUnder moves them by height x the difference.
    local hang = load("return function(self, rows, pitch)\n"
        .. extract(widget, "BookshelfWidget:_hangUnder(rows, pitch)") .. "\nend",
        "hang", "t", { ipairs = ipairs, table = table, math = math })()
    local up = { name = "up", overlap_offset = { 10, 50 } }
    local half = { name = "half", overlap_offset = { 20, 100 } }
    local crop = { x = 0, y = 30, w = 50, h = 170 }
    local risen = { name = "risen", overlap_offset = { 30, -30 } }
    local part = { name = "part", overlap_offset = { 30, 0 }, placement = { h = 200, crop = crop } }
    local row2 = { { name = "plank2" }, up, half, part, _hanging = { risen },
                   _orn_list = { { w = up, t = 1, gap = 40, rh = 280 },
                                 { w = half, t = 0.5, gap = 40, rh = 280 },
                                 { w = risen, t = 1.2, gap = 40, rh = 280, part = part } } }
    local rows = { { { name = "plank1" } }, row2 }
    hang({}, rows, 280 + 60)                -- the real gap is 60, built against 40
    eq(up.overlap_offset[2], 30, "100% did not move up by the whole slack")
    eq(half.overlap_offset[2], 90, "50% did not move up by half of it")
    eq(risen.overlap_offset[2], -54 + 340, "a risen piece was not corrected before it was handed up")
    eq(crop.y, 54, "its own-row copy's crop did not follow"); eq(crop.h, 146)
end)

t.test("a piece dangling into the row below is painted in front of that row's books", function()
    -- Device: glasses on row 1 lowered to -10% hung behind the books of row
    -- 2, which paints later. The row below now paints the part below its own
    -- top AFTER its books; the piece's own row keeps the rest (cropped, so
    -- no part is painted twice).
    local made = {}
    local Orn = { Ornament = { new = function(_s, t) made[#made + 1] = t; return t end } }
    local hang = load("return function(self, rows, pitch)\n"
        .. extract(widget, "BookshelfWidget:_hangUnder(rows, pitch)") .. "\nend",
        "hang", "t", { ipairs = ipairs, table = table, math = math, setmetatable = setmetatable,
                       require = function(m) if m == "lib/bookshelf_ornaments" then return Orn end return require(m) end })()
    local pl = { w = 300, h = 120, entry = {} }
    local glasses = { name = "glasses", placement = pl, overlap_offset = { 50, 300 } }
    local books2 = { name = "books2" }
    local rows = { { { name = "plank1" }, glasses, _orn_list = { { w = glasses, t = -0.1, gap = 40, rh = 340 } } },
                   { { name = "plank2" }, books2 } }
    hang({}, rows, 380)                      -- row 2 starts 380 below row 1's top
    local below = rows[2][#rows[2]]
    assert(below ~= books2 and below.placement, "the row below does not paint the dangling part after its books")
    eq(below.overlap_offset[1], 50); eq(below.overlap_offset[2], 0)
    eq(below.placement.crop.y, 80, "the part below row 2's top does not start there")
    eq(below.placement.crop.h, 40)
    eq(glasses.placement.crop.h, 80, "the own row still paints the part the row below does")
    assert(pl.crop == nil, "the shared placement was changed")
    local within = { name = "w", placement = { w = 10, h = 10 }, overlap_offset = { 0, 100 } }
    local rows2 = { { within, _orn_list = { { w = within, t = -0.1, gap = 40, rh = 340 } } }, { { name = "p" } } }
    hang({}, rows2, 380)
    eq(#rows2[2], 1, "a piece that stays in its row was copied into the row below")
end)

t.done()
