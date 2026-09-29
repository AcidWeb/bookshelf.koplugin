-- tests/_test_plank_browser.lua
-- The plank picker: the plain colour, Oak, then each pack's planks, one per
-- row. Pins what each tab lists, what a row chooses, which reads as in use,
-- and when the quiet "more planks come with packs" line shows.
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg = function() end, info = function() end,
                             warn = function() end, err = function() end }
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local chosen = "oak"
local with_packs = true
package.loaded["lib/bookshelf_theme_pack"] = {
    plankOptions = function()
        local o = { { kind = "colour" }, { kind = "oak", plank = { id = "builtin:oak", name = "Oak" } } }
        if with_packs then
            o[3] = { kind = "pack", pack = "Planks", plank = { id = "Planks/theme/plank.Walnut", name = "Walnut" } }
        end
        return o
    end,
    plankChoice = function() return chosen end,
    choosePlank = function(c) chosen = c end,
}
-- A stand-in renderer: a "bitmap" as tall as its row asks, twice the plank
-- for a design with tall ends, recording frees.
package.loaded["device"] = package.loaded["device"] or { screen = { night_mode = false } }
local made = {}
package.loaded["lib/bookshelf_spine_shelf"] = {
    plankPreview = function(design, w, row_h)
        local h = (design and design.tall) and row_h or math.floor(row_h / 3)
        local bb = { h = h, freed = false }
        function bb:getHeight() return self.h end
        function bb:free() self.freed = true end
        made[#made + 1] = bb
        return bb
    end,
    plankSurface = function(h) return math.floor(h / 6) end,
    plankFace = function(h) return math.floor(h / 12) end,
}
local PB = dofile("lib/bookshelf_plank_browser.lua")

t.test("All lists colour, Oak and the packs' planks; Built-in only the first two", function()
    eq(#PB.entries(PB.ALL), 3); eq(#PB.entries(PB.BUILTIN), 2); eq(#PB.entries("Planks"), 1)
end)

t.test("each option's choice value", function()
    local e = PB.entries(PB.ALL)
    eq(PB.choiceOf(e[1]), "colour"); eq(PB.choiceOf(e[2]), "oak"); eq(PB.choiceOf(e[3]), "Planks/theme/plank.Walnut")
end)

t.test("the option in use is the one chosen", function()
    chosen = "Planks/theme/plank.Walnut"
    local e = PB.entries(PB.ALL)
    eq(PB.inUse(e[3]), true); eq(PB.inUse(e[2]), false)
end)

t.test("the more-planks line shows only when no pack has planks", function()
    with_packs = true; eq(PB.showsMoreHint(), false)
    with_packs = false; eq(PB.showsMoreHint(), true)
    local e = PB.entries(PB.ALL)
    eq(#e, 3); eq(e[3].kind, "hint"); eq(PB.inUse(e[3]), false); eq(PB.choiceOf(e[3]), nil)
    with_packs = true
end)

t.test("a page of tall designs never frees a preview still on show", function()
    local shown = {}
    for i = 1, 6 do
        local o = { kind = "pack", pack = "P", plank = { id = "P/" .. i, middle = "/m" .. i, tall = true } }
        local bb = PB._fit(o, 900, 400, 120)
        assert(bb and bb:getHeight() <= 120, "a preview taller than its box")
        shown[#shown + 1] = bb
    end
    for i, bb in ipairs(shown) do eq(bb.freed, false, "preview " .. i .. " was freed while on screen") end
    local freed = 0
    for _i, bb in ipairs(made) do if bb.freed then freed = freed + 1 end end
    eq(freed > 0, true, "the oversized attempts are freed, not kept")
end)

t.test("the picker opens on the page of the plank in use", function()
    with_packs = true; chosen = "Planks/theme/plank.Walnut"
    local e = PB.entries(PB.ALL)
    eq(PB.startPage(e, 2), 2); eq(PB.startPage(e, 6), 1)
    chosen = "nothing"; eq(PB.startPage(e, 2), 1)
end)

t.done()
