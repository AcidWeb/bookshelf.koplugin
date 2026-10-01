-- tests/_test_page_count_words.lua
-- Page counts from stated word counts (GitHub issue 455): "determine page
-- counts by dividing them with a certain word count (250 or 500)? I have epubs
-- that are not books (fanfiction) and they only have word count metadata."
--
-- Nothing here COUNTS words: it reads the count fan fiction states about
-- itself (FanFicFare's title page, AO3's preface) or a Calibre words column.
-- Rendering at the reader's own settings counts any EPUB, fan fiction too, and
-- matches what they see, so the stated count is a fallback beside the Calibre
-- column and the file name: used when the render is off, or failed on a book.
-- No dialog option; the words a page is a library setting (maintainer).
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local main = io.open("main.lua"):read("*a")
local dlg = io.open("lib/bookshelf_page_count_dialog.lua"):read("*a")
local ss = io.open("lib/bookshelf_spine_shelf.lua"):read("*a")
local st = io.open("lib/bookshelf_settings.lua"):read("*a")
local body = main:match("function Bookshelf:scanPageCounts%(opts%)(.-)\nend\n")
assert(body, "scanPageCounts moved")

t.test("the dialog offers no word-count option", function()
    assert(not dlg:find("Word counts (fast)", 1, true), "the dialog still offers word counts as a source")
    assert(not dlg:find("words_per_page", 1, true), "the dialog still carries the words a page")
end)

t.test("stated word counts run with the fallbacks, after the Calibre column and before the file name", function()
    local _n, chains = body:gsub("filenamePass%(wordsPass%(calibrePass%(", "")
    eq(chains, 2, "both fallback chains (render off, and books the render failed on) should try word counts")
    assert(not body:find("todo = wordsPass(todo)", 1, true), "word counts still run ahead of the render")
    assert(not body:find("opts.words", 1, true), "word counts still wait for a dialog tick")
end)

t.test("the words a page comes from the library setting", function()
    local pass = body:match("local function wordsPass%(list%)(.-)\n        end\n")
    assert(pass and pass:find('BookshelfSettings.read("words_per_page")', 1, true),
        "the pass does not read the words a page setting")
    assert(pass:find("Repo.calibreWordColumn", 1, true), "the Calibre words column is not used")
end)

t.test("library settings has the words a page row", function()
    local lib = st:match("function Settings:_librarySubItems%(%)(.-)\nend\n")
    assert(lib and lib:find('_("Words a page for fan fiction")', 1, true), "no row in library settings")
    assert(lib:find('BookshelfSettings.save("words_per_page", n)', 1, true), "the row does not save the setting")
    assert(lib:find("{ 250, 300, 500 }", 1, true), "the choices changed")
end)

t.test("word-derived counts are shown and kept, as any scanned count", function()
    assert(body:find('psrc == "words"', 1, true), "a word-count book is counted again on every scan")
    assert(ss:find("SHOWN_TAGS = {[^}]*words = true"), "word-derived counts are stored but never shown")
    assert(ss:find("SCAN_TAGS  = {[^}]*words = true"), "word-derived counts are not a scan's")
end)

t.done()
