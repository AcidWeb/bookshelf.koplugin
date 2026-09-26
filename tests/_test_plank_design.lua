-- tests/_test_plank_design.lua
package.path = "./?.lua;" .. package.path
local t  = dofile("tests/_helpers.lua").runner()
local eq = dofile("tests/_helpers.lua").eq
local src = io.open("lib/bookshelf_spine_shelf.lua"):read("*a")
local body = src:match("(function SpineShelf%.plankDesignLayout%(.-\nend)\n")
assert(body, "plankDesignLayout not found")
local SpineShelf = { PLANK_SURFACE_SHARE = 0.8 }
assert(load("local SpineShelf = ...\n" .. body))(SpineShelf)
local L = SpineShelf.plankDesignLayout

-- The layout: plank.middle.png covers the ORIGINAL plank exactly; the ends
-- are anchored to the screen edges, or placed by their plank_end marker.
local function args(o)
    local a = { screen_w = 1236, row_x = 37, row_w = 1162, surf_h = 48, face_h = 9,
                mid = { w = 960, h = 360 }, left = nil, right = nil }
    for k, v in pairs(o or {}) do a[k] = v end
    return a
end

t.test("vertical: the middle band splits 80/20 into surface and face, each fitted", function()
    local l = L(args())
    eq(l.surf0, 96); eq(l.face0, 24)            -- native: band 120 -> 96 + 24
    eq(l.top_h, math.floor(120 * 57 / 120 + 0.5), "outer bands scale with the plank")
    eq(l.bot_h, l.top_h)
    eq(l.surf_h, 48); eq(l.face_h, 9)
end)

t.test("the middle tiles cover the original plank, no more, no less", function()
    local l = L(args())
    eq(l.tiles[1], 37, "starts at the plank's left end")
    eq(l.clip_x0, 37); eq(l.clip_x1, 37 + 1162, "clipped at its right end")
    eq(l.tiles[#l.tiles] < 37 + 1162, true)
    eq(l.tiles[#l.tiles] + l.mid_w >= 37 + 1162, true, "and reaches it")
end)

t.test("ends without a marker sit flush with the screen edges", function()
    local l = L(args{ left = { w = 200, h = 360 }, right = { w = 200, h = 360 } })
    eq(l.left_x, 0); eq(l.right_x + l.right_w, 1236)
    eq(l.left_w, math.floor(200 * 57 / 120 + 0.5))
end)

t.test("an end's plank_end marker lands on the real plank end", function()
    local l = L(args{ left = { w = 200, h = 360, edge = 60 }, right = { w = 200, h = 360, edge = 60 } })
    local e = math.floor(60 * 57 / 120 + 0.5)
    eq(l.left_x + e, 37, "left marker on the plank's left end")
    eq(l.right_x + l.right_w - e, 37 + 1162, "right marker on its right end")
end)

t.test("narrow screen: ends never exceed half the screen", function()
    local l = L(args{ screen_w = 100, row_x = 5, row_w = 90,
                      left = { w = 900, h = 360 }, right = { w = 900, h = 360 } })
    eq(l.left_w <= 50, true); eq(l.right_w <= 50, true)
end)

t.test("slots render see-through over a plank design, and repainters redraw it", function()
    assert(src:find("function SpineShelf.seeThrough()", 1, true), "no seeThrough")
    local slot = src:match("function SpineBookSlot:paintTo%(.-\nend")
    assert(slot and not slot:find("SpineShelf.has_wallpaper", 1, true),
        "slot paint still keys transparency on the wallpaper alone")
    local key = src:match("function SpineBookSlot:_renderKey%(.-\nend")
    assert(key and key:find("seeThrough()", 1, true), "render key ignores the design")
    -- fillLiftGap and nickFromBelow copy neighbouring SCREEN pixels, which
    -- already carry the design. The two that paint computed plank colour
    -- must, over a design, DARKEN it instead: the shadow is kept, and the
    -- design is not painted out.
    for _i, fn in ipairs({ "LiftShadow:paintTo", "FaceOutFeet:paintTo" }) do
        local b = src:match("function " .. fn:gsub("%.", "%%."):gsub(":", "%%:") .. "%(.-\nend")
        assert(b and b:find("activePlankDesign()", 1, true) and b:find("shadeDesign(", 1, true),
            fn .. " must shade a plank design, not paint over it")
        assert(not b:find("redrawDesign(", 1, true), fn .. " still paints the shadow out")
    end
end)



t.test("the plank design goes UNDER the recess, so the books' shadows fall on it", function()
    local rw = src:match("function SpineShelf%.rowWidget%(.-\nend\n")
    local d  = rw:find("children[#children + 1] = design", 1, true)
    local r  = rw:find("children[#children + 1] = recess", 1, true)
    local g  = rw:find("children[#children + 1] = group", 1, true)
    assert(d and r and g and d < r and r < g, "order must be plank, design, recess, books")
end)


t.test("the plank design runs edge to edge of the screen, not just the row", function()
    local pd = src:match("function PlankDesign:paintTo%(.-\nend")
    assert(pd and pd:find("Screen:getWidth()", 1, true), "design is clipped to the row's margins")
end)


t.test("the middle's above/below bands fade out at the plank ends (no hard shadow edge)", function()
    local ds = src:match("local function _designStrip%(.-\nend\n")
    assert(ds and ds:find("_taperBands(", 1, true), "the middle's outer bands are cut square at the plank ends")
end)

t.done()
