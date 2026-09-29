-- tests/_test_reading_goal_i18n.lua
-- The reading goal cards' text goes through gettext: the daily card's
-- " / 30 min" was English in every language (GitHub issue 474).
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t = H.runner()
local src = io.open("micromodules/reading_goal.lua"):read("*a")

t.test("the daily card's minutes unit is translatable", function()
    assert(not src:find('" min"', 1, true), 'a bare " min" is concatenated into the card')
    assert(src:find('T(_("%1 min"), target)', 1, true), "the daily suffix does not use a msgid")
end)

t.done()
