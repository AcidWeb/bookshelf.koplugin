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

t.done()
