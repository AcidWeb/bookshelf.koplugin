-- tests/_test_pack_editor.lua
-- The pack editor's page layout: pieces left to right from the margin, a new
-- row when the next would run past the far margin, a new page after n rows.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local src = io.open("lib/bookshelf_pack_editor.lua"):read("*a")
local fn = src:match("(function M%.layout%(items, row_w, n_rows, margin%).-\nend\n)")
assert(fn, "layout moved")
local M = {}
assert(load("local M = ...\n" .. fn))(M)

local function slots(...)
    local out = {}
    for i, v in ipairs({ ... }) do out[i] = { slot = v } end
    return out
end

t.test("pieces fill a row from the margin, then wrap", function()
    local pages = M.layout(slots(40, 40, 40), 120, 3, 10)   -- 100px of room
    eq(#pages, 1); eq(#pages[1], 2)
    eq(pages[1][1][1].x, 10); eq(pages[1][1][2].x, 50)
    eq(pages[1][2][1].i, 3, "the third piece did not wrap")
    eq(pages[1][2][1].x, 10)
end)

t.test("a new page after the last row", function()
    local pages = M.layout(slots(90, 90, 90, 90), 120, 2, 10)
    eq(#pages, 2); eq(#pages[2], 2)
    eq(pages[2][1][1].i, 3)
end)

t.test("a piece wider than a row still gets a row of its own", function()
    local pages = M.layout(slots(500, 40), 120, 3, 10)
    eq(#pages[1], 2); eq(pages[1][1][1].i, 1); eq(pages[1][2][1].i, 2)
end)

t.test("no pieces, no pages", function()
    eq(#M.layout({}, 120, 3, 10), 0)
end)

t.done()
