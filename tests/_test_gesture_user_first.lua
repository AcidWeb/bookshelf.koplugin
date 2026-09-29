-- tests/_test_gesture_user_first.lua
-- A KOReader gesture the reader set up on an edge swipe or a corner hold
-- wins over bookshelf's own use of it (GitHub issue 476: bottom and top
-- edge swipes turned shelf pages, the top right hold opened book details).
-- Only zones the reader configured, and only those kinds: an unset zone,
-- or any other gesture, is left to bookshelf as before.
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg = function() end, info = function() end,
                             warn = function() end, err = function() end }
package.loaded["ui/uimanager"] = package.loaded["ui/uimanager"] or {}
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local GZ = dofile("lib/bookshelf_gesture_zones.lua")

local fired = {}
local function zone(id)
    -- As KOReader's GestureRange does: a zone matches its own kind of gesture.
    local kind = id:match("^hold") and "hold" or id:match("swipe") and "swipe" or "tap"
    return { def = { id = id }, gs_range = { match = function(_r, ev) return ev.ges == kind end },
             handler = function() fired[#fired + 1] = id; return true end }
end
local function fm(user)
    return { gestures = { gestures = user },
             _ordered_touch_zones = { zone("filemanager_tap"), zone("one_finger_swipe_bottom_edge_right"),
                                      zone("hold_top_right_corner"), zone("tap_top_right_corner") } }
end

t.test("a configured edge swipe or corner hold runs the reader's action first", function()
    fired = {}
    local f = fm({ one_finger_swipe_bottom_edge_right = { toggle_frontlight = true },
                   hold_top_right_corner = { night_mode = true } })
    eq(GZ.tryUserFirst({ ges = "swipe" }, f), true)
    eq(fired[1], "one_finger_swipe_bottom_edge_right")
    fired = {}
    eq(GZ.tryUserFirst({ ges = "hold" }, f), true)
    eq(fired[1], "hold_top_right_corner")
end)

t.test("unset zones, taps and KOReader's own zones are left to bookshelf", function()
    fired = {}
    eq(GZ.tryUserFirst({ ges = "swipe" }, fm({})), false)
    eq(GZ.tryUserFirst({ ges = "tap" }, fm({ tap_top_right_corner = { x = true } })), false)
    eq(#fired, 0)
    eq(GZ.tryUserFirst({ ges = "swipe" }, nil), false)
end)

t.test("the shelf asks before its own widgets do", function()
    local src = io.open("lib/bookshelf_widget.lua"):read("*a")
    local he = src:match("function BookshelfWidget:handleEvent%(event%)(.-)\nend\n")
    local first = he and he:find("GestureZones.tryUserFirst(", 1, true)
    local kids = he and he:find("if InputContainer.handleEvent(self, event) then return true end", 1, true)
    assert(first and kids and first < kids, "bookshelf's widgets get the gesture before the reader's own setting")
end)

t.done()
