-- tests/_test_ornament_deck.lua
-- The ornament deck: a saved order, fixed patterns per level, a dealer.
-- Run from the plugin root: lua tests/_test_ornament_deck.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg = function() end, info = function() end,
                             warn = function() end, err = function() end }
local H  = dofile("tests/_helpers.lua")
local t  = H.runner()
local eq = H.eq

local function fresh()
    package.loaded["lib/bookshelf_ornament_deck"] = nil
    local D = dofile("lib/bookshelf_ornament_deck.lua")
    local mem = {}
    D._store = { read = function(k) return mem[k] end,
                 save = function(k, v) mem[k] = v end }
    local s = 7
    D._rand = function(n) s = (s * 48271) % 2147483647; return (s % n) + 1 end
    return D, mem
end
local function pool(names)
    local out = {}
    for i, n in ipairs(names) do out[i] = { name = n, aspect = 1 } end
    return out
end
local function namesOf(list) local o = {} for i, e in ipairs(list) do o[i] = e.name end return o end

t.test("first use shuffles once and saves the order", function()
    local D, mem = fresh()
    local got = namesOf(D.order(pool({ "a", "b", "c", "d" })))
    eq(#got, 4)
    eq(table.concat(mem[D.ORDER_KEY], ","), table.concat(got, ","), "the order was not saved")
    eq(table.concat(namesOf(D.order(pool({ "a", "b", "c", "d" }))), ","), table.concat(got, ","),
       "a second call reordered")
end)

t.test("the saved order survives a reload", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "c", "a", "b" }
    eq(table.concat(namesOf(D.order(pool({ "a", "b", "c" }))), ","), "c,a,b")
end)

t.test("new pieces go at the end; removed files are dropped", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "c", "gone", "a" }
    D.reconcile({ "a", "c", "new" })
    eq(table.concat(mem["ornament_deck"], ","), "c,a,new")
end)

t.test("a deleted file that comes back is appended, not restored", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "a", "b", "c" }
    D.reconcile({ "b", "c" })
    D.reconcile({ "a", "b", "c" })
    eq(table.concat(mem["ornament_deck"], ","), "b,c,a")
end)

t.test("a switched-off piece keeps its place in the saved order", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "a", "b", "c" }
    -- b is off: the pool handed in lacks it, but the saved order keeps it.
    eq(table.concat(namesOf(D.order(pool({ "a", "c" }))), ","), "a,c")
    D.reconcile({ "a", "b", "c" })
    eq(table.concat(mem["ornament_deck"], ","), "a,b,c")
end)

t.test("shuffle makes and saves a new order and bumps the epoch", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "a", "b", "c", "d", "e", "f" }
    local e0, g0 = D.epoch(), D.generation()
    D.shuffle()
    assert(table.concat(mem["ornament_deck"], ",") ~= "a,b,c,d,e,f", "shuffle kept the order")
    eq(#mem["ornament_deck"], 6)
    assert(D.epoch() > e0 and D.generation() > g0)
end)

t.test("swap exchanges two places and bumps the generation, not the epoch", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "a", "b", "c" }
    local e0, g0 = D.epoch(), D.generation()
    eq(D.swap("a", "c"), true)
    eq(table.concat(mem["ornament_deck"], ","), "c,b,a")
    eq(D.epoch(), e0); assert(D.generation() > g0)
    eq(D.swap("a", "a"), false, "same piece swaps nothing")
    eq(D.swap("a", "zzz"), false, "an unknown piece swaps nothing")
end)

local function slots(D, fn, level, n)
    local o = {}
    for i = 1, n do if D[fn](level, i) then o[#o + 1] = i end end
    return table.concat(o, ",")
end

t.test("patterns: bottom rows first, per level", function()
    local D = fresh()
    eq(slots(D, "shelfSlot", "rarely", 12), "4,8,12")
    eq(slots(D, "shelfSlot", "often", 6), "2,4,6")
    eq(slots(D, "shelfSlot", "always", 3), "1,2,3")
    eq(slots(D, "shelfSlot", "off", 6), "")
    eq(slots(D, "gapSlot", "rarely", 8), "")
    eq(slots(D, "gapSlot", "often", 8), "4,8")
    eq(slots(D, "gapSlot", "always", 4), "2,4")
end)

t.test("levels from the frequency number", function()
    local D = fresh()
    eq(D.levelOf(0), "off"); eq(D.levelOf(0.5), "rarely"); eq(D.levelOf(1), "often")
    eq(D.levelOf(2), "always"); eq(D.levelOf(4), "always"); eq(D.levelOf(nil), "off")
end)

t.test("sides alternate with each shelf-end piece", function()
    local D = fresh()
    eq(D.side("often", 2), "right"); eq(D.side("often", 4), "left"); eq(D.side("often", 6), "right")
    eq(D.side("always", 1), "right"); eq(D.side("always", 2), "left")
    eq(D.side("rarely", 4), "right"); eq(D.side("rarely", 8), "left")
end)

local function cards(spec)   -- "a,Hb,c": H = hangs
    local out = {}
    for tok in spec:gmatch("[^,]+") do
        local hang = tok:sub(1, 1) == "H"
        out[#out + 1] = { name = hang and tok:sub(2) or tok, hang = hang or nil }
    end
    return out
end

t.test("the dealer: card n to slot n, cycling, with the deal number", function()
    local D = fresh()
    local d = D.dealer(D.newState(), cards("a,b,c"))
    local got = {}
    for i = 1, 7 do local e, no = d:take(false); got[i] = e.name .. no end
    eq(table.concat(got, " "), "a1 b1 c1 a2 b2 c2 a3")
end)

t.test("peek does not deal; take does", function()
    local D = fresh()
    local d = D.dealer(D.newState(), cards("a,b"))
    eq(d:peek(false).name, "a"); eq(d:peek(false).name, "a")
    eq(d:take(false).name, "a"); eq(d:peek(false).name, "b")
end)

t.test("a hanging card on a top shelf swaps with the next card", function()
    local D = fresh()
    local d = D.dealer(D.newState(), cards("Hbat,vase,cup"))
    eq(d:peek(true).name, "vase", "peek must agree with take")
    eq(d:take(true).name, "vase", "the top shelf took the bat")
    eq(d:take(false).name, "bat", "the bat did not go to the next slot with a shelf above")
    eq(d:take(false).name, "cup", "the order after the swap is broken")
end)

t.test("an owed hanging card waits past further top shelves", function()
    local D = fresh()
    local d = D.dealer(D.newState(), cards("Hbat,vase,cup,jar"))
    eq(d:take(true).name, "vase")
    eq(d:take(true).name, "cup", "a second top shelf must not take the owed bat")
    eq(d:take(false).name, "bat")
    eq(d:take(false).name, "jar")
end)

t.test("every card hangs: a top shelf stands the next one on the plank", function()
    local D = fresh()
    local d = D.dealer(D.newState(), cards("Ha,Hb"))
    local e, _no, stand = d:take(true)
    eq(e.name, "a"); eq(stand, true)
    eq(d:take(false).name, "b")
end)

t.test("no cards: nothing is dealt and nothing loops", function()
    local D = fresh()
    local d = D.dealer(D.newState(), {})
    eq(d:take(true), nil); eq(d:take(false), nil); eq(d.st.n, 0)
end)

t.test("a copied state deals the same pieces", function()
    local D = fresh()
    local c = cards("Ha,b,c,d")
    local d1 = D.dealer(D.newState(), c)
    d1:take(true)                                   -- b, a owed
    local snap = D.copyState(d1.st)
    local x = { d1:take(false).name, d1:take(false).name }
    local d2 = D.dealer(D.copyState(snap), c)
    eq(table.concat({ d2:take(false).name, d2:take(false).name }, ","), table.concat(x, ","))
    assert(snap.owed ~= d1.st.owed, "copyState shares the owed list")
end)

t.done()
