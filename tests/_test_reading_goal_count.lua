-- tests/_test_reading_goal_count.lua
-- The yearly reading goal (Reddit report from a reader moving from SimpleUI:
-- "now the count for my annual reading goal is off. I knew how to manually
-- change the count before, but I can't figure out a way to do it").
--
-- Two fixes. A book counts under the year (and month) it was MARKED FINISHED,
-- not the year it was last opened: a book finished in December and opened
-- again in January counted for the new year. And books read outside KOReader
-- can be added to the year's count, as SimpleUI's "physical books" could, with
-- a SimpleUI reader's number brought across once.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq

local saved = {}
package.loaded["lib/bookshelf_settings_store"] = {
    read = function(k, d) if saved[k] == nil then return d end return saved[k] end,
    save = function(k, v) saved[k] = v end,
}
package.loaded["lib/bookshelf_i18n"] = { gettext = function(s) return s end }
package.loaded["ffi/util"] = { template = function(s) return s end }
local sui_physical
_G.G_reader_settings = { readSetting = function(_self, k)
    if k == "navbar_reading_goal_physical" then return sui_physical end
end }
local M = dofile("micromodules/reading_goal.lua")
local X = M._test
assert(X, "the module exposes no test hooks")

local function ts(y, m, d) return os.time{ year = y, month = m, day = d, hour = 12 } end
local NOW = { year = 2026, month = 10, day = 1 }
local YEAR_START = ts(2026, 1, 1) - 12 * 3600

t.test("a book counts in the year it was marked finished, not the year it was opened", function()
    local hist = {
        { file = "/a", time = ts(2026, 1, 5) },   -- finished 2025-12-30, opened again in January
        { file = "/b", time = ts(2026, 3, 1) },   -- finished 2026-03-01
        { file = "/c", time = ts(2026, 10, 1) },  -- finished this month
        { file = "/d", time = ts(2026, 9, 9) },   -- reading, not finished
    }
    local status = { ["/a"] = "finished", ["/b"] = "finished", ["/c"] = "finished", ["/d"] = "reading" }
    local on = { ["/a"] = "2025-12-30", ["/b"] = "2026-03-01", ["/c"] = "2026-10-01" }
    local month, year = X.countFinished(hist, NOW, YEAR_START,
        function(fp) return status[fp] end, function(fp) return on[fp] end)
    eq(year, 2, "last year's book was counted, or this year's missed")
    eq(month, 1)
end)

t.test("with no finished date, when it was last opened stands in", function()
    local hist = { { file = "/e", time = ts(2026, 10, 1) }, { file = "/f", time = ts(2026, 2, 1) } }
    local month, year = X.countFinished(hist, NOW, YEAR_START,
        function() return "finished" end, function() return nil end)
    eq(year, 2); eq(month, 1)
end)

t.test("the finished date's other shapes are understood", function()
    eq(select(1, X.dateYM("2026-03-04")), 2026)
    eq(select(2, X.dateYM("2026-03-04")), 3)
    eq(select(1, X.dateYM(ts(2025, 6, 1))), 2025)
    eq(select(2, X.dateYM({ year = 2024, month = 2, day = 1 })), 2)
    eq(X.dateYM("soon"), nil)
end)

t.test("a book in history twice counts once", function()
    local hist = { { file = "/g", time = ts(2026, 5, 1) }, { file = "/g", time = ts(2026, 4, 1) } }
    local _m, year = X.countFinished(hist, NOW, YEAR_START,
        function() return "finished" end, function() return "2026-04-01" end)
    eq(year, 1)
end)

t.test("other books start at nothing, or at a SimpleUI reader's number, once", function()
    saved = {}; sui_physical = nil
    eq(X.readOtherBooks(2026), 0)
    saved = {}; sui_physical = 7
    eq(X.readOtherBooks(2026), 7, "the SimpleUI number was not brought across")
    sui_physical = 9
    eq(X.readOtherBooks(2026), 7, "brought across again after the first time")
end)

t.test("other books belong to their year", function()
    saved = { micromodule_reading_goal_other_books = { year = 2025, n = 4 } }
    eq(X.readOtherBooks(2026), 0, "last year's books carried into this year")
    eq(X.readOtherBooks(2025), 4)
end)

t.test("the yearly card adds the other books; the monthly one does not", function()
    local src = io.open("micromodules/reading_goal.lua"):read("*a")
    assert(src:find("year_books  = year_books + readOtherBooks(t.year)", 1, true), "other books are not in the year's count")
    assert(src:find('_("Books read outside KOReader this year: %1")', 1, true), "no row to set them")
end)

t.test("the progress read records the finished date it already has open", function()
    local repo = io.open("lib/bookshelf_book_repository.lua"):read("*a")
    local rp = repo:match("function Repo.readProgress%(filepath%)(.-)\nend\n")
    assert(rp and rp:find("_finished_on[filepath] = summary.modified or false", 1, true),
        "readProgress does not keep the finished date, so finishedOn opens every sidecar again")
    local inv = repo:match("function Repo.invalidateProgressCache%(filepath%)(.-)\nend\n")
    assert(inv and inv:find("_finished_on[filepath] = nil", 1, true), "a status change keeps the old finished date")
end)

t.done()
