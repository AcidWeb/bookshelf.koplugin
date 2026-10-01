-- tests/_test_quotes_index.lua
-- The quote of the day draws from every book's highlights, through a count
-- per book kept in the facts store (lib/bookshelf_book_facts_db), instead of
-- opening the 25 most recently opened books' sidecars on every pick. Device
-- report: after opening many books for testing, the module said "No
-- highlights yet" -- the one recent book with highlights was left out, and
-- older ones were never looked at.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq

package.loaded["logger"] = { dbg = function() end, info = function() end, warn = function() end, err = function() end }
package.loaded["lib/bookshelf_i18n"] = { gettext = function(s) return s end }
package.loaded["ffi/util"] = { template = function(s) return s end }
package.loaded["lib/bookshelf_safe_text"] = { safe = function(s) return s end }

-- A library: fp -> { mtime, highlights = { text, ... } } (nil: no sidecar).
local LIB, OPENS, HIST
local function book(n, mtime) local hl = {} for i = 1, n do hl[i] = "q" .. i end return { mtime = mtime or 1, highlights = hl } end
package.loaded["docsettings"] = {
    findSidecarFile = function(_self, fp) return LIB[fp] and (fp .. ".sdr/metadata.lua") or nil end,
    hasSidecarFile = function(_self, fp) return LIB[fp] ~= nil end,
    open = function(_self, fp)
        OPENS[#OPENS + 1] = fp
        local b = LIB[fp]
        return { readSetting = function(_s, key)
            if key == "annotations" then
                local ann = {}
                for i, text in ipairs(b and b.highlights or {}) do
                    ann[i] = { drawer = "lighten", text = text, page = i, color = b.colour }
                end
                return ann
            end
            if key == "doc_props" then return { title = fp } end
        end }
    end,
}
package.loaded["libs/libkoreader-lfs"] = {
    attributes = function(path, what)
        local fp = path:match("^(.*)%.sdr/metadata%.lua$")
        local b = fp and LIB[fp]
        if not b then return nil end
        if what == "modification" then return b.mtime end
        return { mode = "file", modification = b.mtime }
    end,
}
package.loaded["readhistory"] = setmetatable({}, { __index = function(_t, k) if k == "hist" then return HIST end end })
local STORE = {}
package.loaded["lib/bookshelf_settings_store"] = {
    read = function(k, d) if STORE[k] == nil then return d end return STORE[k] end,
    save = function(k, v) STORE[k] = v end, delete = function(k) STORE[k] = nil end, flush = function() end,
}
local FACTS
package.loaded["lib/bookshelf_book_facts_db"] = {
    get = function(fp) return FACTS[fp] end,
    put = function(fp, f) FACTS[fp] = FACTS[fp] or {}; for k, v in pairs(f) do FACTS[fp][k] = v end end,
    prefetch = function() end, flush = function() end,
    highlightBooks = function()
        local out = {}
        for fp, f in pairs(FACTS) do if (f.hl or 0) > 0 then out[fp] = f.hl end end
        return out
    end,
}

local function fresh(history, library)
    LIB, OPENS, FACTS, STORE = library, {}, {}, { micromodule_quote_of_day_refresh = "daily" }
    HIST = {}
    for i, fp in ipairs(history) do HIST[i] = { file = fp, time = 1000 - i } end
    package.loaded["lib/bookshelf_quotes"] = nil
    return dofile("lib/bookshelf_quotes.lua")
end

t.test("a book far down the history is found, once the index has reached it", function()
    local hist, lib = {}, {}
    for i = 1, 40 do hist[i] = "/b/" .. i; lib[hist[i]] = book(0) end
    lib["/b/35"] = book(3)
    local Q = fresh(hist, lib)
    -- A pick that finds nothing counts on, a budget at a time, rather than
    -- say "No highlights yet" with books never looked at.
    local q = Q.ofTheDay()
    assert(q and q.filepath == "/b/35", "the only book with highlights was never reached")
end)

t.test("an unchanged sidecar is not opened again", function()
    local Q = fresh({ "/b/a", "/b/b" }, { ["/b/a"] = book(2), ["/b/b"] = book(0) })
    Q.ofTheDay()
    OPENS = {}
    Q.reroll(); Q.ofTheDay()
    for _i, fp in ipairs(OPENS) do assert(fp ~= "/b/b", "a book counted at 0 was opened again") end
    eq(#OPENS, 1, "a pick opens more than the one book it draws from")
end)

t.test("a sidecar that changed is counted again", function()
    local lib = { ["/b/a"] = book(0, 1) }
    local Q = fresh({ "/b/a" }, lib)
    eq(Q.ofTheDay(), nil)
    lib["/b/a"] = book(2, 2)                      -- a highlight made since
    Q.reroll()
    local q = Q.ofTheDay()
    assert(q and q.filepath == "/b/a", "the new highlights were not seen")
end)

t.test("a left-out book is neither counted nor drawn from", function()
    local Q = fresh({ "/b/a", "/b/b" }, { ["/b/a"] = book(5), ["/b/b"] = book(1) })
    STORE[Q.SKIP_BOOKS_KEY] = { ["/b/a"] = "A" }
    for _i = 1, 6 do Q.reroll(); local q = Q.ofTheDay(); assert(q and q.filepath == "/b/b") end
    for _i, fp in ipairs(OPENS) do assert(fp ~= "/b/a", "a left-out book was opened") end
end)

t.test("every highlight can be drawn, each book by its share", function()
    local Q = fresh({ "/b/a", "/b/b" }, { ["/b/a"] = book(1), ["/b/b"] = book(3) })
    Q.ofTheDay()                                  -- builds the index
    local pool, total = Q._pool()
    eq(total, 4)
    local seen = {}
    for k = 1, total do
        local q = Q._pickAt(pool, total, {}, k)
        seen[q.filepath .. ":" .. q.text] = true
    end
    for _i, key in ipairs({ "/b/a:q1", "/b/b:q1", "/b/b:q2", "/b/b:q3" }) do
        assert(seen[key], "never drawn: " .. key)
    end
end)

t.test("a book whose highlights are all in a left-out colour gives way to another", function()
    local lib = { ["/b/a"] = book(4), ["/b/b"] = book(1) }
    lib["/b/a"].colour = "red"
    local Q = fresh({ "/b/a", "/b/b" }, lib)
    STORE[Q.SKIP_COLORS_KEY] = { red = true }
    for _i = 1, 5 do Q.reroll(); local q = Q.ofTheDay(); assert(q and q.filepath == "/b/b", "no quote, or a left-out colour") end
end)

t.test("a library scan counts every book, past the per-pick budget", function()
    local lib = {}
    for i = 1, 60 do lib["/l/" .. i] = book(0) end
    lib["/l/59"] = book(2)
    local Q = fresh({}, lib)
    local fps = {}
    for i = 1, 60 do fps[i] = "/l/" .. i end
    local books, quotes = Q.scanLibrary(fps)
    eq(books, 1); eq(quotes, 2)
    local q = Q.ofTheDay()
    assert(q and q.filepath == "/l/59", "a book the scan found, but not in history, is not drawn from")
end)

t.test("the module's settings offer the library scan", function()
    local src = io.open("micromodules/quote_of_day.lua"):read("*a")
    assert(src:find('_("Scan library for highlights")', 1, true), "no Scan library row")
    assert(src:find("Quotes.scanLibrary(fps", 1, true), "the row does not scan the library")
    local q = io.open("lib/bookshelf_quotes.lua"):read("*a")
    assert(not q:find("MAX_BOOKS", 1, true), "the 25-book walk is still there")
end)

t.done()
