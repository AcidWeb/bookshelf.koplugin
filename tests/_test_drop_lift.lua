-- tests/_test_drop_lift.lua
-- A tap on empty space drops the lifted book back onto the shelf (maintainer:
-- "tapping anywhere off the book in empty space should drop the book back").
-- _dropLift is pulled out of the widget by name and run against a stub, and
-- handleEvent is checked to offer it a tap only after our own widgets and
-- KOReader's touch zones have passed on it.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local src = io.open("lib/bookshelf_widget.lua"):read("*a")
local body = src:match("\n(function BookshelfWidget:_dropLift%(.-\nend)\n")

local dirty = {}
local function load_drop()
    assert(body, "no BookshelfWidget:_dropLift")
    local env = setmetatable({
        BookshelfWidget = {},
        Screen = { scaleBySize = function(_s, v) return v end },
        UIManager = { setDirty = function(_u, w, f) dirty[#dirty + 1] = { w, f } end },
    }, { __index = _G })
    local chunk = assert((loadstring or load)(body, "=_dropLift", "t", env))
    if setfenv then setfenv(chunk, env) end
    chunk()
    return env.BookshelfWidget._dropLift
end

local function widget(o)
    local w = { calls = {}, _spine_lift_headroom = 8 }
    for k, v in pairs(o) do w[k] = v end
    function w:_selectedFilepath()
        if self._cursor_idx then return "cursor.epub" end
        return self._tap_selected_fp or (self._preview_book and self._preview_book.filepath)
    end
    function w:_shelfSlotRect(fp)
        if fp == self.visible then return { x = 10, y = 100, w = 20, h = 80, copy = function(r) return r end } end
    end
    function w:_repaintSelectionHighlight(a, b) self.calls[#self.calls + 1] = { "repaint", a, b } end
    function w:_rebuildRefreshHeroAndChips() self.calls[#self.calls + 1] = { "hero" } end
    return w
end

t.test("a tap-twice lift drops, and only its slot repaints", function()
    local drop = load_drop()
    local w = widget{ _tap_selected_fp = "a.epub", visible = "a.epub" }
    eq(drop(w), true)
    eq(w._tap_selected_fp, nil)
    eq(w.calls[1], { "repaint", "a.epub", nil })
end)

t.test("a previewed book drops: the hero goes back to the book being read", function()
    local drop = load_drop()
    dirty = {}
    local w = widget{ _preview_book = { filepath = "b.epub" }, _hero_mode = "preview", visible = "b.epub" }
    eq(drop(w), true)
    eq(w._preview_book, nil); eq(w._hero_mode, "current")
    eq(w.calls[1], { "hero" })
    eq(#dirty, 1, "the row the book stood out of is refreshed too")
end)

t.test("nothing lifted on this page: the tap is left alone", function()
    local drop = load_drop()
    local w = widget{ _preview_book = { filepath = "b.epub" }, visible = "other.epub" }
    eq(drop(w), false); eq(w._preview_book.filepath, "b.epub")
    eq(drop(widget{}), false)
end)

t.test("a d-pad cursor is not a lift to drop", function()
    local drop = load_drop()
    local w = widget{ _cursor_idx = 3, visible = "cursor.epub" }
    eq(drop(w), false)
end)

t.test("handleEvent offers a tap to _dropLift after our widgets and KOReader's zones", function()
    local he = src:match("function BookshelfWidget:handleEvent%(event%)(.-)\nend\n")
    assert(he, "handleEvent moved")
    local kids = he:find("InputContainer.handleEvent(self, event)", 1, true)
    local fmz = he:find("GestureZones.tryFMZones(ev, fm)", 1, true)
    local drop = he:find("self:_dropLiftOnTap(ev)", 1, true)
    assert(kids and fmz and drop and kids < fmz and fmz < drop, "the drop runs before something that should come first")
    local tap = src:match("function BookshelfWidget:_dropLiftOnTap%(ev%)(.-)\nend\n")
    assert(tap and tap:find('ev.ges ~= "tap"', 1, true), "the drop is not limited to a plain tap")
end)

t.done()
