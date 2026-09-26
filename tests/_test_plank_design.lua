-- tests/_test_plank_design.lua
package.path = "./?.lua;" .. package.path
local t  = dofile("tests/_helpers.lua").runner()
local eq = dofile("tests/_helpers.lua").eq
local src = io.open("lib/bookshelf_spine_shelf.lua"):read("*a")
local body = src:match("(function SpineShelf%.plankDesignLayout%(.-\nend)\n")
assert(body, "plankDesignLayout not found")
local SpineShelf = {}
assert(load("local SpineShelf = ...\n" .. body))(SpineShelf)
local L = SpineShelf.plankDesignLayout

t.test("three equal bands: the middle band is the plank's drawn height", function()
    local l = L(1000, 40, 120, 60, 90, 60)   -- image 120 tall -> scale 1
    eq(l.h, 120); eq(l.mid_w, 90); eq(l.left_w, 60); eq(l.right_x, 940)
    eq(l.tiles[1], 0); eq(l.tiles[#l.tiles] < 1000, true)
end)

t.test("scales with the plank", function()
    local l = L(1000, 20, 120, 60, 90, 60)   -- plank half the image band -> scale 0.5
    eq(l.h, 60); eq(l.mid_w, 45); eq(l.left_w, 30)
end)

t.test("mismatched plank heights: scaled from the middle image", function()
    local l = L(500, 30, 90, nil, 90, nil)
    eq(l.left_w, 0); eq(l.right_w, 0); eq(l.h, 90)
end)

t.test("narrow row: ends never overlap past each other", function()
    local l = L(100, 40, 120, 80, 90, 80)
    eq(l.left_w, 50); eq(l.right_w, 50); eq(l.right_x, 50)
end)

t.test("slots render see-through over a plank design, and repainters redraw it", function()
    assert(src:find("function SpineShelf.seeThrough()", 1, true), "no seeThrough")
    local slot = src:match("function SpineBookSlot:paintTo%(.-\nend")
    assert(slot and not slot:find("SpineShelf.has_wallpaper", 1, true),
        "slot paint still keys transparency on the wallpaper alone")
    local key = src:match("function SpineBookSlot:_renderKey%(.-\nend")
    assert(key and key:find("seeThrough()", 1, true), "render key ignores the design")
    -- fillLiftGap and nickFromBelow copy neighbouring SCREEN pixels, which
    -- already carry the design; only the two that paint computed plank
    -- colour need to put it back.
    for _i, fn in ipairs({ "LiftShadow:paintTo", "FaceOutFeet:paintTo" }) do
        local b = src:match("function " .. fn:gsub("%.", "%%."):gsub(":", "%%:") .. "%(.-\nend")
        assert(b and b:find("redrawDesign(", 1, true), fn .. " paints plank colour over the design")
    end
end)


t.test("redrawDesign never blits a strip the cache has freed", function()
    local rd = src:match("function SpineShelf%.redrawDesign%(.-\nend")
    assert(rd and rd:find("_strip_cache[r.key]", 1, true),
        "regions must look their strip up by key at redraw time")
    local pd = src:match("function PlankDesign:paintTo%(.-\nend")
    assert(pd and pd:find("key = ", 1, true), "a region must record its strip's cache key")
end)

t.done()
