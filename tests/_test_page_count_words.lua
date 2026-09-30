-- tests/_test_page_count_words.lua
-- Page counts from word counts (GitHub issue 455): "determine page counts by
-- dividing them with a certain word count (250 or 500)? I have epubs that are
-- not books (fanfiction) and they only have word count metadata."
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local main = io.open("main.lua"):read("*a")
local dlg = io.open("lib/bookshelf_page_count_dialog.lua"):read("*a")
local ss = io.open("lib/bookshelf_spine_shelf.lua"):read("*a")

t.test("the source is off until ticked, at 250 words a page", function()
    package.loaded["lib/bookshelf_settings_store"] = { read = function() return nil end, save = function() end }
    package.loaded["ui/widget/confirmbox"] = {}
    package.loaded["ui/widget/infomessage"] = {}
    package.loaded["ui/uimanager"] = {}
    package.loaded["ffi/util"] = { template = function(s) return s end }
    package.loaded["lib/bookshelf_i18n"] = { gettext = function(s) return s end }
    local src = dlg:match("^(.-)\nlocal Blitbuffer")
    local M = load(src .. "\nreturn M")()
    local o = M.options()
    eq(o.words, false)
    eq(o.words_per_page, 250)
    eq(M.anySource({ words = true }, false, nil), true, "word counts alone are a source")
end)

t.test("a remembered words-a-page survives as a number", function()
    package.loaded["lib/bookshelf_settings_store"] = {
        read = function() return { words = true, words_per_page = 500 } end, save = function() end }
    local src = dlg:match("^(.-)\nlocal Blitbuffer")
    local M = load(src .. "\nreturn M")()
    local o = M.options()
    eq(o.words, true)
    eq(o.words_per_page, 500, "the number was flattened to a boolean")
end)

t.test("Start hands the scan the Calibre words column", function()
    assert(dlg:find("opts.word_column = wordColumn()", 1, true), "the Calibre words column is not passed")
end)

t.test("the words pass runs before the render, and its counts are shown and kept", function()
    local body = main:match("function Bookshelf:scanPageCounts%(opts%)(.-)\nend\n")
    local words_at = body:find("todo = wordsPass(todo)", 1, true)
    local render_at = body:find("Phase C:", 1, true)
    assert(words_at and render_at and words_at < render_at, "word counts must come before the render")
    assert(body:find('psrc == "words"', 1, true), "a word-count book is counted again on every scan")
    assert(ss:find("SHOWN_TAGS = {[^}]*words = true"), "word-derived counts are stored but never shown")
    assert(ss:find("SCAN_TAGS  = {[^}]*words = true"), "word-derived counts are not a scan's")
end)

t.done()
