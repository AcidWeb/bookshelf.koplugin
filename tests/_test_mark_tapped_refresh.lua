-- tests/_test_mark_tapped_refresh.lua
-- The tap mark on a folder or OPDS tile (GitHub issue 448). It used to repaint
-- the whole screen with the widget's dither hint, and on a colour Kobo with
-- HW dithering on, a Book stack folder's page edges came out as black and
-- white noise next to the ring. The mark is a black ring, nothing in it needs
-- dithering, so it refreshes the tile alone and undithered.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t = H.runner()
local src = io.open("lib/bookshelf_widget.lua"):read("*a")
local body = src:match("function BookshelfWidget:_markTapped%(fp%)(.-)\nend\n")
assert(body, "_markTapped moved or was renamed")

t.test("the mark refreshes the tapped tile's own rect", function()
    assert(body:find("_tapTileRect(fp)", 1, true), "the tile's rect is not looked up")
    assert(body:find('return "ui", rect, false', 1, true), "the refresh is not scoped to the tile, undithered")
end)

t.test("the widget's dither hint is off for that one repaint and restored after", function()
    local off = body:find("self.dithered = nil", 1, true)
    local paint = body:find("UIManager:forceRePaint()", 1, true)
    local back = body:find("self.dithered = keep", 1, true)
    assert(off and paint and back and off < paint and paint < back,
        "UIManager ORs the widget's dithered flag into every refresh, so it has to be cleared around the repaint")
end)

t.test("a tile it cannot find still gets a whole-screen mark", function()
    assert(body:find('UIManager:setDirty(self, "ui")', 1, true), "no fallback when the tile is not found")
end)

t.test("the lookup matches a folder by its first book before its front cover", function()
    local fn = src:match("function BookshelfWidget:_tapTileRect%(fp%)(.-)\nend\n")
    assert(fn, "no _tapTileRect")
    local folder = fn:find("first_book", 1, true)
    local book = fn:find("node.book", 1, true)
    assert(folder and book and folder < book,
        "a stack's front cover would match first, and its rect leaves out the pile behind it")
end)

t.test("the hero's copy of the book is never taken for the tile", function()
    -- Review finding: the hero sits at the top of the same column and carries
    -- a .book, usually this very book, so a walk from the top refreshed the
    -- hero and the ring never reached the panel.
    local fn = src:match("(function BookshelfWidget:_tapTileRect%(fp%).-\nend\n)")
    local chunk = "local BookshelfWidget = {}\n" .. fn .. "\nreturn BookshelfWidget"
    local BW = load(chunk)()
    local function rect(x, y, w, h)
        return { x = x, y = y, w = w, h = h, copy = function(r) return { x = r.x, y = r.y, w = r.w, h = r.h } end }
    end
    local fp = "/b/Author/Book.epub"
    local hero = { { book = { filepath = fp }, dimen = rect(10, 10, 200, 300) } }
    local stack = { folder = { path = "/b/Author", first_book = { filepath = fp } },
                    dimen = rect(40, 600, 270, 398),
                    { book = { filepath = fp }, dimen = rect(40, 600, 243, 371) } }
    local self = { _inner_vgroup = { hero, {}, { stack } },
                   _shelf_dims = { shelf_top_idx = 3, n_shelves = 1 } }
    local r = BW._tapTileRect(self, fp)
    assert(r, "the tile was not found")
    H.eq(r.y, 600, "the hero's rect was taken for the tile")
    H.eq(r.w, 270, "the front cover's rect was taken instead of the whole stack")
end)

t.done()
