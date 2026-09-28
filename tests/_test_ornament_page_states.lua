-- tests/_test_ornament_page_states.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg = function() end, info = function() end,
                             warn = function() end, err = function() end }
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local src = io.open("lib/bookshelf_widget.lua"):read("*a")

local function method(name)
    local body = src:match("\n(function BookshelfWidget:" .. name .. "%(.-\nend)\n")
    assert(body, name .. " not found")
    local W = {}
    local env = setmetatable({ BookshelfWidget = W, require = require, logger = package.loaded["logger"] },
                             { __index = _G })
    local f
    if _G.setfenv then f = assert(loadstring(body)); setfenv(f, env)
    else f = assert(load(body, name, "t", env)) end
    f()
    return W[name]
end

local function stub(cursor, skip)
    package.loaded["lib/bookshelf_ornament_deck"] = nil
    local D = dofile("lib/bookshelf_ornament_deck.lua")
    package.loaded["lib/bookshelf_ornament_deck"] = D
    local self = { _cursor = cursor, _spine_fetch_cache = { page_orn = {} }, builds = 0 }
    self._spineSkip = function() return skip or 0 end
    self._nShelves = function() return 2 end
    self._ornSig = function() return "sig" end
    self._ornKey = method("_ornKey")
    self._spinePageFirsts = function(s, build, _dims)
        if build then
            s.builds = s.builds + 1
            s._spine_fetch_cache.page_orn["5:0"] = { n = 9, shelf = 4, bnd = 2, owed = {} }
        end
    end
    return self, D
end

t.test("the chip's first page starts from nothing, with no map build", function()
    local self = stub(1, 0)
    local st = method("_ornStartState")(self)
    eq(st.n, 0); eq(self.builds, 0)
end)

t.test("a known page's state is used without building the map", function()
    local self = stub(5, 0)
    self._spine_fetch_cache.page_orn["5:0"] = { n = 3, shelf = 2, bnd = 1, owed = {} }
    self._spine_fetch_cache.orn_sig = "sig"
    eq(method("_ornStartState")(self).n, 3); eq(self.builds, 0)
end)

t.test("an unknown page builds the map once and uses what it recorded", function()
    local self = stub(5, 0)
    self._spine_fetch_cache.orn_sig = "sig"
    eq(method("_ornStartState")(self).n, 9); eq(self.builds, 1)
end)

t.test("no map (a windowed source): the nearest earlier known page, never a crash", function()
    local self = stub(7, 0)
    self._spine_fetch_cache.orn_sig = "sig"
    self._spinePageFirsts = function() end
    self._spine_fetch_cache.page_orn["3:0"] = { n = 4, shelf = 2, bnd = 0, owed = {} }
    eq(method("_ornStartState")(self).n, 4)
end)

t.test("a changed signature drops every state but the current page's, unless it was a shuffle", function()
    local self, D = stub(5, 0)
    self._spine_fetch_cache.page_orn = { ["5:0"] = { n = 3, shelf = 2, bnd = 1, owed = {} },
                                         ["9:0"] = { n = 7, shelf = 4, bnd = 1, owed = {} } }
    self._spine_fetch_cache.orn_sig, self._spine_fetch_cache.orn_epoch = "old", D.epoch()
    eq(method("_ornStartState")(self).n, 3, "a swap lost the current page's state")
    eq(self._spine_fetch_cache.page_orn["9:0"], nil, "a later page's stale state survived")
    self._spine_fetch_cache.orn_sig = "old"
    D.shuffle({ "a", "b" })
    self._spinePageFirsts = function() end
    eq(method("_ornStartState")(self).n, 0, "a shuffle kept the old layout")
end)

t.test("the render plans from the start state and records the next page's", function()
    local b = src:match("\nfunction BookshelfWidget:_buildSpineRows%(.-%)\n(.-)\nend\n")
    assert(b:find("opts.orn_state   = self:_ornStartState({ content_w = content_w, shelf_h = shelf_h })", 1, true))
    assert(b:find("c.page_orn[self:_ornKey(self._cursor + (plan.next_item - 1), plan.next_skip or 0)] = plan.orn_end", 1, true))
end)

t.test("the page map records every page's state", function()
    local b = src:match("\nfunction BookshelfWidget:_spinePageFirsts%(build, dims%)\n(.-)\nend\n")
    assert(b:find("for k, st in pairs(plan.page_orn or {}) do", 1, true))
end)

t.test("shuffle ornaments reshuffles the saved order and forgets every page", function()
    local b = src:match("\nfunction BookshelfWidget:onBookshelfShuffleOrnaments%(.-%)\n(.-)\nend\n")
    assert(b and b:find('require("lib/bookshelf_ornament_deck").shuffle()', 1, true))
    assert(b:find("self:_dropOrnPages(false)", 1, true))
end)

t.test("a refetch of the same list keeps the page states; a changed list drops them", function()
    -- The fetch cache lives 30s. Dropping the states with it made every page
    -- turn after half a minute's reading rebuild the whole page map.
    local fetch = method("_spineCachedFetch")
    local list = { { filepath = "/a" }, { filepath = "/b" }, { filepath = "/c" } }
    local self = { chip = "all", _drilldown_path = nil }
    self._fetchChipItems = function() local o = {} for i, x in ipairs(list) do o[i] = x end return o end
    self._spineItemsSig = method("_spineItemsSig")
    fetch(self, 400)
    local c = self._spine_fetch_cache
    c.page_orn, c.orn_sig, c.orn_epoch = { ["2:0"] = { n = 5, shelf = 2, bnd = 0, owed = {} } }, "s", 0
    c.at = 0                                     -- expired
    fetch(self, 400)
    assert(self._spine_fetch_cache ~= c, "test premise: the cache was not refetched")
    eq(self._spine_fetch_cache.page_orn["2:0"].n, 5, "the same list lost its page states")
    eq(self._spine_fetch_cache.orn_sig, "s")
    self._spine_fetch_cache.at = 0
    table.remove(list, 2)
    fetch(self, 400)
    eq(self._spine_fetch_cache.page_orn, nil, "a changed list kept stale page states")
end)

t.done()
