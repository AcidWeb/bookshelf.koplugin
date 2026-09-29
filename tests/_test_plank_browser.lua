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

t.done()
