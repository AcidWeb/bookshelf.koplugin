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

-- A widget stub: n cover rows, between lo and hi; nudging moves n.
local function stubWidget(n, lo, hi)
    local store = {}
    local settings = {
        read = function(k) return store[k] end,
        saveDeferred = function(k, v) store[k] = v end,
    }
    local self = { rows = n, store = store }
    function self:_coverRows() return self.rows end
    function self:_nudgeCoverRows(d) self.rows = math.max(lo, math.min(hi, self.rows + d)) end
    local step = load("return function(self, dir)\n" .. extract("BookshelfWidget:_topPanelRowStep(dir)") .. "\nend",
        "step", "t", { BookshelfSettings = settings, tonumber = tonumber })()
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
    eq(w.store.top_panel_rows_taken, 2, "the minimum was counted as a row taken")
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

t.test("every view steps the cover grid's count, which sizes the panel in all of them", function()
    -- "All other shelf styles are sized based on the number of cover rows"
    -- (maintainer): the panel must not change size on a view switch.
    local cr = extract("BookshelfWidget:_coverRows()")
    assert(cr:find("_asCoverGrid(", 1, true), "the count is not the cover grid's in every view")
    local nc = extract("BookshelfWidget:_nudgeCoverRows(delta)")
    assert(nc:find('saveDeferred("bookshelf_rows"', 1, true), "the step does not move the Rows editor's count")
    assert(not src:find("spine:\" .. tostring(self.chip)", 1, true)
           and not src:find("list:\" .. tostring(self.chip)", 1, true),
        "a view keeps its own count again")
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
    assert(src:find('Gestures.on("top_panel_rows")', 1, true), "no switch to turn the gesture off")
end)

-- The panel grows to show more of the book's description; its cover keeps
-- the size it had before the swipe (maintainer: "the cover grows to fill most
-- of the space and you don't see much more description").
t.test("the top panel's cover is capped at the panel's size before the swipe", function()
    local store = { top_panel_rows_taken = 1 }
    local env = {
        BookshelfSettings = { read = function(k) return store[k] end },
        tonumber = tonumber, type = type,
        _asCoverGrid = function(f) return f() end,
    }
    local cap = load("return function(self, hide_chip_bar)\n" .. extract("BookshelfWidget:_heroCoverCapH(hide_chip_bar)") .. "\nend",
        "cap", "t", env)()
    local w = { rows = 1 }
    function w:_baseShelves() return self.rows end
    function w:_collapsedGridSplit(_hide, n) return 300, 900 - 200 * n end   -- the panel shrinks per row
    eq(cap(w, false), 500, "the panel's height with the taken row back (two rows)")
    store.top_panel_rows_taken = nil
    eq(cap(w, false), nil, "nothing taken: no cap")
    local sizing = src:match("local hero_cover_w, hero_cover_h\n(.-)\n    %-%- Title bar removed")
    assert(sizing and sizing:find("self:_heroCoverCapH(hide_chip_bar)", 1, true), "the cover is not capped")
end)

t.done()
