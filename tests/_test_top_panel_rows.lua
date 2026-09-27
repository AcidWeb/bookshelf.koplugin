-- tests/_test_top_panel_rows.lua
-- Issue 465: a swipe down on the top panel takes a row off the shelf (the
-- panel grows into it); a swipe up gives back rows taken that way, and once
-- there are none to give back it goes to full screen shelves as before
-- (maintainer: "add a row only if you previously removed a row"). Neither may
-- get in the way of KOReader's own swipe down from the top edge.
--
-- Usage (from plugin root): lua tests/_test_top_panel_rows.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local helpers = dofile("tests/_helpers.lua")
local t  = helpers.runner()
local eq = helpers.eq
local src = io.open("lib/bookshelf_widget.lua"):read("*a")

local function extract(name)
    local pat = "\nfunction " .. name:gsub("[%.%(%)]", "%%%0") .. "\n(.-)\nend\n"
    local body = src:match(pat)
    assert(body, name .. " not found")
    return body
end

-- A widget stub: n rows on screen, between lo and hi; nudging moves n.
local function stubWidget(n, lo, hi, mode)
    local store = {}
    local settings = {
        read = function(k) return store[k] end,
        saveDeferred = function(k, v) store[k] = v end,
        nilOrTrue = function(k) return store[k] ~= false end,
    }
    local self = { chip = "c1", rows = n, store = store }
    function self:_isListMode() return mode == "list" end
    function self:_isSpineMode() return mode == "spine" end
    function self:_nShelves() return self.rows end
    function self:_nudgeRows(d) self.rows = math.max(lo, math.min(hi, self.rows + d)) end
    local key = load("return function(self)\n" .. extract("BookshelfWidget:_topPanelRowsKey()") .. "\nend")()
    self._topPanelRowsKey = key
    local step = load("return function(self, dir)\n" .. extract("BookshelfWidget:_topPanelRowStep(dir)") .. "\nend",
        "step", "t", { BookshelfSettings = settings, next = next, pairs = pairs, tostring = tostring, type = type, tonumber = tonumber })()
    self._topPanelRowStep = step
    return self
end

t.test("down takes a row; up gives it back; then up is full screen's again", function()
    local w = stubWidget(3, 1, 4)
    assert(w:_topPanelRowStep(-1), "the swipe down was not taken")
    eq(w.rows, 2)
    assert(w:_topPanelRowStep(-1)); eq(w.rows, 1)
    assert(w:_topPanelRowStep(-1), "at one row the swipe is still consumed")
    eq(w.rows, 1, "no fewer than the minimum")
    assert(w:_topPanelRowStep(1)); eq(w.rows, 2)
    assert(w:_topPanelRowStep(1)); eq(w.rows, 3)
    eq(w:_topPanelRowStep(1), false, "with nothing taken, swipe up goes to full screen")
    eq(w.rows, 3, "and adds nothing")
end)

t.test("swipe up with nothing taken leaves the rows alone", function()
    local w = stubWidget(2, 1, 4)
    eq(w:_topPanelRowStep(1), false)
    eq(w.rows, 2)
end)

t.test("a row count that can no longer grow forgets what it owed", function()
    local w = stubWidget(3, 1, 4)
    w:_topPanelRowStep(-1)               -- 2, one owed
    w.rows = 4                            -- the reader set 4 in the Rows editor meanwhile
    eq(w:_topPanelRowStep(1), false, "nothing to give back: full screen")
    eq(w:_topPanelRowStep(1), false, "and it stays forgotten")
end)

t.test("each view keeps its own count: covers, and each shelf's spines or list", function()
    local a = stubWidget(3, 1, 4, "spine")
    a:_topPanelRowStep(-1)
    eq(a:_topPanelRowsKey(), "spine:c1")
    local taken = a.store.top_panel_rows_taken
    eq(taken["spine:c1"], 1)
    local b = stubWidget(3, 1, 4)
    eq(b:_topPanelRowsKey(), "covers")
    local c = stubWidget(3, 1, 4, "list")
    eq(c:_topPanelRowsKey(), "list:c1")
end)

t.test("the swipes are wired on the top panel only, and down stays clear of KOReader's edge", function()
    local up = extract("BookshelfWidget:onSwipeShelvesUp(_, ges)")
    assert(up:find("self:_isHeroSwipe(ges)", 1, true) and up:find("_topPanelRowStep(1)", 1, true),
        "a swipe up on the top panel does not give rows back")
    local down = extract("BookshelfWidget:onSwipeShelvesDown(_, ges)")
    local i_row = down:find("_topPanelRowStep(-1)", 1, true)
    assert(i_row and down:find("self:_isHeroSwipe(ges)", 1, true), "a swipe down on the top panel does not take a row")
    -- The top 1/8 is left out of the range (KOReader's menu swipe starts there).
    assert(src:find("SwipeShelvesDown = {", 1, true), "the swipe-down range moved")
    assert(src:find('gesture_top_panel_rows', 1, true), "no switch to turn the gesture off")
end)

t.done()
