-- tests/_test_gestures_menu.lua
-- Settings > Behavior > Bookshelf gestures: a checkbox for each of
-- Bookshelf's own gestures, so a reader can find them and switch any of them
-- off (maintainer: discovery, and locking a device down for kids).
--
-- Usage (from plugin root): lua tests/_test_gestures_menu.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["lib/bookshelf_i18n"] = { gettext = function(s) return s end }
local helpers = dofile("tests/_helpers.lua")
local t  = helpers.runner()
local eq = helpers.eq

local mem = {}
local G = dofile("lib/bookshelf_gestures.lua")
local saves, flushes = 0, 0
G._store = { read = function(k) return mem[k] end,
             save = function(k, v) saves = saves + 1; mem[k] = v end,
             saveDeferred = function(k, v) mem[k] = v end,
             flush = function() flushes = flushes + 1 end }

t.test("every gesture is on until switched off, and off reads back", function()
    for _i, g in ipairs(G.list()) do assert(G.on(g.id), g.id .. " starts off") end
    G.set("book_hold", false)
    eq(G.on("book_hold"), false)
    eq(mem.gesture_book_hold, false)
    G.set("book_hold", true)
    eq(mem.gesture_book_hold, nil, "on is stored as the default, not as true")
end)

t.test("the old swipe-down setting is the same switch, so nobody's choice changes", function()
    mem.expanded_swipe_back = false
    eq(G.on("full_screen_down"), false)
    mem.expanded_swipe_back = nil
    eq(G.key("top_panel_rows"), "gesture_top_panel_rows", "the top-panel rows switch shipped under this key")
end)

t.test("an unknown id is on: a typo never disables a gesture", function()
    eq(G.on("no_such_gesture"), true)
end)

t.test("the menu is an all row, then one checkbox per gesture, in order", function()
    local items = G.menuItems()
    eq(#items, #G.list() + 1)
    assert(items[1].separator, "no separator under the all row")
    items[2].callback()
    eq(items[2].checked_func(), false, "the checkbox did not switch it off")
    items[2].callback()
    eq(items[2].checked_func(), true)
end)

t.test("the all row switches every gesture off, then every one on", function()
    for k in pairs(mem) do mem[k] = nil end
    local all = G.menuItems()[1]
    eq(all.checked_func(), true, "all on: ticked")
    saves, flushes = 0, 0
    all.callback()
    eq(saves, 0, "each gesture flushed the settings file on its own")
    eq(flushes, 1, "one flush for the lot")
    for _i, g in ipairs(G.list()) do eq(G.on(g.id), false, g.id .. " is still on") end
    eq(all.checked_func(), false)
    all.callback()
    for _i, g in ipairs(G.list()) do eq(G.on(g.id), true, g.id .. " is still off") end
    -- Some off: the row is unticked, and a tap switches everything on.
    G.set("rate", false)
    eq(all.checked_func(), false, "some off: not ticked")
    all.callback()
    eq(G.on("rate"), true)
end)

-- Where each gesture is honoured. Source-matched: each check sits in the
-- handler that would otherwise act.
local function has(file, needle, what)
    local src = io.open(file):read("*a")
    assert(src:find(needle, 1, true), what .. " (" .. file .. ")")
end
local W = "lib/bookshelf_widget.lua"
t.test("each gesture's handler asks before acting", function()
    for _i, g in ipairs(G.list()) do
        if g.id ~= "full_screen_down" then
            local found = false
            for _j, f in ipairs({ W, "lib/bookshelf_chip_bar.lua", "lib/bookshelf_hero_modules.lua",
                                  "lib/bookshelf_start_menu.lua", "lib/bookshelf_hero_card.lua" }) do
                local src = io.open(f):read("*a")
                if src:find('Gestures.on("' .. g.id .. '")', 1, true) then found = true break end
            end
            assert(found, "nothing checks the '" .. g.id .. "' switch")
        end
    end
    has(W, 'nilOrTrue("expanded_swipe_back")', "the swipe-down switch is no longer read")
end)

t.test("the menu lives in Behavior, and the old row moved into it", function()
    local st = io.open("lib/bookshelf_settings.lua"):read("*a")
    assert(st:find('_("Bookshelf gestures")', 1, true), "no Bookshelf gestures menu")
    assert(st:find('require("lib/bookshelf_gestures").menuItems()', 1, true), "the menu is not built from the list")
    assert(not st:find('text = _("Swipe down leaves full screen shelves")', 1, true),
        "the old row is still in Behavior as well")
end)

t.done()
