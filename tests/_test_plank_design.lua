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

t.done()
