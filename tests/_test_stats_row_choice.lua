-- tests/_test_stats_row_choice.lua
-- Time left in a book read from the wrong statistics row (Reddit report:
-- "While reading, Koreader shows 19:15, but Bookshelf shows 27 minutes ...
-- just with this book"). KOReader keys a book's row by title + authors + md5
-- and starts a new row when the title or authors change outside its own
-- editor, so one md5 can have two rows. Bookshelf took whichever came first;
-- KOReader reads into the one it opened last. Reproduced on the rig: 31 min
-- from the old row, ~17 h from KOReader's.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t = H.runner()
local src = io.open("lib/bookshelf_book_repository.lua"):read("*a")

t.test("the book's stats come from the row KOReader opened last", function()
    local fn = src:match("function Repo.enrichStats%(book%)(.-)\nend\n")
    assert(fn, "enrichStats moved")
    assert(fn:find("FROM book WHERE md5 = ? ORDER BY last_open DESC LIMIT 1", 1, true),
        "with two rows for one md5 the stats are read from an arbitrary one")
end)

t.done()
