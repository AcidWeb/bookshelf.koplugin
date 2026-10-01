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

t.test("new pieces go first by default, so they are seen; removed files are dropped", function()
    -- Maintainer: a reader who adds ornaments should see them; one who wants
    -- the shelf to stay put can have them go last instead.
    local D, mem = fresh()
    mem["ornament_deck"] = { "c", "gone", "a" }
    D.reconcile({ "a", "c", "new", "new2" })
    eq(table.concat(mem["ornament_deck"], ","), "new,new2,c,a")
end)

t.test("set to last, new pieces go at the end and nothing else moves", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "c", "gone", "a" }
    mem[D.NEW_AT_KEY] = "end"
    D.reconcile({ "a", "c", "new" })
    eq(table.concat(mem["ornament_deck"], ","), "c,a,new")
end)

t.test("a piece the order has not met joins it by the same rule", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "a", "b" }
    eq(table.concat(namesOf(D.order(pool({ "a", "b", "n" }))), ","), "n,a,b")
    mem["ornament_deck"] = { "a", "b" }
    mem[D.NEW_AT_KEY] = "end"
    eq(table.concat(namesOf(D.order(pool({ "a", "b", "n" }))), ","), "a,b,n")
end)

t.test("a deleted file that comes back is appended, not restored", function()
    local D, mem = fresh()
    mem[D.NEW_AT_KEY] = "end"
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

local function cards(spec)   -- "a,Hb,c": H = reaches the shelf above (height 100%+)
    local out = {}
    for tok in spec:gmatch("[^,]+") do
        local up = tok:sub(1, 1) == "H"
        out[#out + 1] = { name = up and tok:sub(2) or tok, reaches_above = up or nil }
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

-- A synthetic shelf: n books of width w, a group boundary before every
-- `every`-th book, driven through the REAL fillRows.
local SpineLayout = dofile("lib/bookshelf_spine_layout.lua")
local function shelf(n, w, every)
    local es = {}
    for i = 1, n do
        es[i] = { w = w, gap_base = (i > 1) and ((every and (i - 1) % every == 0) and 20 or 4) or 0,
                  orn_seed = (i > 1 and every and (i - 1) % every == 0) and ("b" .. i) or nil,
                  item_idx = i }
    end
    return es
end
local function sub(es, from)
    local o = {}
    for i = from, #es do
        local c = {}
        for k, v in pairs(es[i]) do c[k] = v end
        o[#o + 1] = c
    end
    o[1].orn_seed, o[1].gap_base = nil, 0      -- a render's first book has no boundary
    return o
end
local function env(D, st, level, es, paginating, per_page, n_rows, pool)
    return {
        dealer = D.dealer(st, pool), level = level, entries = es,
        paginating = paginating, per_page = per_page, n_rows = n_rows, content_w = 300,
        size = function(kind, e, no, stand) return { entry = e, w = 40, kind = kind, no = no, stand = stand } end,
        space = function(kind, pl) return pl.w + 8 end,
        pageKey = function(i) return tostring(es[i].item_idx) end,
    }
end
local function run(D, e)
    local h = D.fillHooks(e)
    local ws = {}
    for i, x in ipairs(e.entries) do ws[i] = x.w end
    local rows = SpineLayout.fillRows(ws, h.avail, h.gaps, h.empty_ok, h)
    h.stop()
    return rows, h
end
local function pieces(rows, es, h, from_row, to_row)
    local out = {}
    for r = from_row, to_row do
        local row = rows[r]
        if h.row_orn[r] then out[#out + 1] = "R" .. h.row_orn[r].entry.name end
        if row then
            for i = row.first, row.last do
                local e = es[i]
                if e.lead_ornament then out[#out + 1] = "L" .. e.lead_ornament.entry.name end
                if e.ornament then out[#out + 1] = "G" .. e.ornament.entry.name end
            end
        end
    end
    return table.concat(out, " ")
end

t.test("agreement: every page the render plans matches the pagination pass", function()
    local D = fresh()
    local pool = cards("a,b,Hc,d,e")
    for _k, level in ipairs({ "rarely", "often", "always" }) do
        local all = shelf(60, 45, 3)
        local prow, ph = run(D, env(D, D.newState(), level, all, true, 2, math.huge, pool))
        local pages = SpineLayout.paginate(prow, 2)
        for p = 1, #pages - 1 do
            local first = pages[p].first
            local key = tostring(all[first].item_idx)
            local st = ph.page_orn[key]
            assert(st, level .. ": no state recorded for page " .. p)
            local es = sub(all, first)
            local rrow, rh = run(D, env(D, D.copyState(st), level, es, false, 2, 2, pool))
            eq(rrow[1].first, 1)
            eq(rrow[2] and rrow[2].last, pages[p].last - first + 1,
               level .. ": page " .. p .. " breaks differently")
            eq(pieces(rrow, es, rh, 1, 2),
               pieces(prow, all, ph, (p - 1) * 2 + 1, p * 2),
               level .. ": page " .. p .. " got different pieces")
            local nxt = ph.page_orn[tostring(all[pages[p + 1].first].item_idx)]
            local mine = rh.dealer and rh.dealer.st or rh.state()
            eq(mine.n, nxt.n, level .. ": page " .. p .. " end state n")
            eq(mine.shelf, nxt.shelf); eq(mine.bnd, nxt.bnd)
            eq(table.concat(mine.owed, ","), table.concat(nxt.owed, ","))
        end
    end
end)

t.test("the nth slot holds card n, and shelf ends follow the level", function()
    local D = fresh()
    local rows, h = run(D, env(D, D.newState(), "often", shelf(40, 45, nil), true, 2, math.huge, cards("a,b,c")))
    local got = {}
    for r = 1, 8 do got[#got + 1] = h.row_orn[r] and h.row_orn[r].entry.name or "-" end
    eq(table.concat(got, ""), "-a-b-c-a")
end)

t.test("a boundary piece at a row start stands as a lead piece", function()
    local D = fresh()
    -- 6 books of 45 + gaps fill a 300 row; boundary before book 7.
    local all = shelf(20, 45, 6)
    local rows, h = run(D, env(D, D.newState(), "always", all, true, 99, math.huge, cards("a,b,c,d")))
    local lead = false
    for _i, e in ipairs(all) do if e.lead_ornament then lead = true end end
    assert(lead, "no boundary landed at a row start in this shelf; adjust widths")
end)

t.test("a page starting with an empty row: the first book's boundary is absent in both passes", function()
    local D = fresh()
    -- A full-row piece: size returns w = 300, so a row-end slot row stands empty.
    local all = shelf(30, 45, 2)
    local e1 = env(D, D.newState(), "always", all, true, 2, math.huge, cards("a,b,c"))
    e1.size = function(kind, e, no) return { entry = e, w = (kind == "rowend") and 300 or 40, no = no } end
    local prow, ph = run(D, e1)
    local pages = SpineLayout.paginate(prow, 2)
    for p = 1, #pages - 1 do
        local first = pages[p].first
        local st = ph.page_orn[tostring(all[first].item_idx)]
        local es = sub(all, first)
        local e2 = env(D, D.copyState(st), "always", es, false, 2, 2, cards("a,b,c"))
        e2.size = e1.size
        local rrow, rh = run(D, e2)
        eq(pieces(rrow, es, rh, 1, 2), pieces(prow, all, ph, (p - 1) * 2 + 1, p * 2), "page " .. p)
    end
end)

t.test("bare planks continue the count on the last page", function()
    local D = fresh()
    local es = shelf(3, 45, nil)
    local rows, h = run(D, env(D, D.newState(), "always", es, false, 4, 4, cards("a,b,c,d,e")))
    eq(#rows, 1)
    local bare = h.bare(2, 4)
    eq(bare[2].entry.name, "b"); eq(bare[3].entry.name, "c"); eq(bare[4].entry.name, "d")
end)

t.test("the render deals nothing past its own rows", function()
    local D = fresh()
    local es = shelf(40, 45, 3)
    local rows, h = run(D, env(D, D.newState(), "always", es, false, 2, 2, cards("a,b,c")))
    local st = h.state()
    eq(st.shelf, 2, "the render counted shelves past its page")
end)

t.test("no hanging piece is dealt to a page's top shelf", function()
    local D = fresh()
    local pool = cards("Ha,b,Hc,d")
    for _k, level in ipairs({ "often", "always" }) do
        local all = shelf(80, 45, 2)
        local prow, ph = run(D, env(D, D.newState(), level, all, true, 2, math.huge, pool))
        local hung_on_top, hung = 0, 0
        for r = 1, #prow do
            local top = ((r - 1) % 2) == 0
            local function check(pl)
                if pl and pl.entry.reaches_above and not pl.stand then
                    hung = hung + 1
                    if top then hung_on_top = hung_on_top + 1 end
                end
            end
            check(ph.row_orn[r])
            for i = prow[r].first, prow[r].last do
                check(all[i].ornament); check(all[i].lead_ornament)
            end
        end
        assert(hung > 0, level .. ": test premise, no hanging piece was dealt at all")
        eq(hung_on_top, 0, level .. ": a hanging piece was dealt to a top shelf")
    end
end)

t.test("a full-row piece on every shelf still leaves every page a book", function()
    -- Review: Always, one piece nudged to the whole row: every row stood
    -- empty, the page placed no book, and plan's next-page block indexed
    -- entry 0 (a crash on the home screen).
    local D = fresh()
    local function big(e)
        e.size = function(kind, en, no) return { entry = en, w = (kind == "rowend") and 300 or 40, no = no } end
        return e
    end
    local es = shelf(20, 45, nil)
    local rows = run(D, big(env(D, D.newState(), "always", es, false, 2, 2, cards("a"))))
    assert(#rows >= 1 and rows[#rows].last >= 1, "the render's page holds no book")
    local all = shelf(20, 45, nil)
    local prow = run(D, big(env(D, D.newState(), "always", all, true, 2, math.huge, cards("a"))))
    for p, pg in ipairs(SpineLayout.paginate(prow, 2)) do
        assert(pg.last >= pg.first, "page " .. p .. " holds no book")
    end
end)

t.test("a one-row page squeezes its end piece so the page's book fits", function()
    -- Device (1 row, a wide framed print as the row's end piece): the page
    -- may not stand empty, so its first book was forced in beside the piece
    -- at full size and a face-out ran past the end of the plank. The piece
    -- shrinks instead -- only as far as the book needs.
    local D = fresh()
    local function wide(e)
        e.size = function(kind, en, no, stand, cap)
            local w = (kind == "rowend") and 250 or 40
            if cap then w = math.min(w, cap) end
            return { entry = en, w = w, kind = kind, no = no }
        end
        return e
    end
    for _i, paginating in ipairs({ false, true }) do
        local es = shelf(6, 120, nil)
        local rows, h = run(D, wide(env(D, D.newState(), "always", es, paginating, 1,
                                         paginating and math.huge or 1, cards("a"))))
        for r, row in ipairs(rows) do
            assert(row.last >= row.first, "row " .. r .. " holds no book")
            local used = 0
            for i = row.first, row.last do used = used + es[i].w end
            local pl = h.row_orn[r]
            if pl then used = used + pl.w + 8 end
            assert(used <= 300, (paginating and "pagination" or "render")
                .. ": row " .. r .. " overflows: " .. used)
        end
        local pl = h.row_orn[1]
        assert(pl and pl.w == 172, "the piece shrank only to the room left: " .. tostring(pl and pl.w))
    end
end)

t.test("a book that leaves no room for any piece: the piece is left off that row", function()
    local D = fresh()
    local e = env(D, D.newState(), "always", shelf(3, 295, nil), false, 1, 1, cards("a"))
    e.size = function(kind, en, no, stand, cap)
        local w = (kind == "rowend") and 250 or 40
        if cap then if cap < 10 then return nil end; w = math.min(w, cap) end
        return { entry = en, w = w, kind = kind, no = no }
    end
    local rows, h = run(D, e)
    assert(rows[1].last >= rows[1].first, "the page holds no book")
    assert(h.row_orn[1] == nil, "a piece that cannot fit is still on the row")
end)

t.test("a piece squeezed below a quarter of its width is left off instead", function()
    -- sizeFor never refuses, so a tight squeeze would stand a speck.
    local D = fresh()
    local e = env(D, D.newState(), "always", shelf(3, 250, nil), false, 1, 1, cards("a"))
    e.size = function(kind, en, no, stand, cap)
        local w = (kind == "rowend") and 200 or 40
        if cap then w = math.max(1, math.min(w, cap)) end
        return { entry = en, w = w, kind = kind, no = no }
    end
    local rows, h = run(D, e)                 -- room 50 - pads 8: a 42px piece
    assert(rows[1].last >= rows[1].first, "the page holds no book")
    assert(h.row_orn[1] == nil, "a 42px scrap of a 200px piece still stands")
end)

t.test("sync reconciles the order with every piece on disk, once per scan", function()
    -- Review: reconcile had no production caller, so deleted files were never
    -- dropped, a re-added one came back to its old place, and a piece that
    -- was off when the order was made never entered it (Swap to it did nothing).
    local D, mem = fresh()
    mem["ornament_deck"] = { "a", "gone", "b" }
    local all = pool({ "a", "b", "off1" })
    local saves = 0
    local save = D._store.save
    D._store.save = function(k, v) saves = saves + 1; save(k, v) end
    D.sync(all)
    eq(table.concat(mem["ornament_deck"], ","), "off1,a,b", "new pieces join first by default")
    D.sync(all)
    eq(saves, 1, "the same scan reconciled twice")
    eq(D.swap("a", "off1"), true, "a piece that was off cannot be swapped to")
end)

t.test("place and move: a piece's place among the pieces that are on, and one step either way", function()
    local D, mem = fresh()
    mem["ornament_deck"] = { "a", "off1", "b", "c" }
    local on = { "a", "b", "c" }                      -- off1 is switched off
    local i, n = D.position("b", on)
    eq(i, 2); eq(n, 3)
    eq(D.position("off1", on), nil, "a switched-off piece has no place")
    eq(D.move("b", -1, on), true)
    eq(table.concat(mem["ornament_deck"], ","), "b,off1,a,c", "Earlier did not swap with the piece before it that is on")
    eq(D.move("a", 1, { "b", "a", "c" }), true)
    eq(table.concat(mem["ornament_deck"], ","), "b,off1,c,a")
    -- The deck deals round in a loop, so the first and last are neighbours:
    -- a step past either end wraps (maintainer).
    eq(D.move("b", -1, { "b", "c", "a" }), true, "the first piece cannot move earlier")
    eq(table.concat(mem["ornament_deck"], ","), "a,off1,c,b", "earlier from the first did not trade with the last")
    eq(D.move("b", 1, { "a", "c", "b" }), true, "the last piece cannot move later")
    eq(table.concat(mem["ornament_deck"], ","), "b,off1,c,a", "later from the last did not trade with the first")
    eq(D.move("x", 1, { "x" }), false, "a piece alone has nowhere to go")
end)

t.test("the menu has the new-ornaments choice beside the collection", function()
    local st = io.open("lib/bookshelf_settings.lua"):read("*a")
    local bg = st:match("function Settings:_backgroundSubItems%(%)(.-)\nend\n")
    assert(bg and bg:find("self:_ornamentsRow()", 1, true) and bg:find("self:_newOrnamentsRow()", 1, true),
        "the choice is not in Wallpaper, ornaments and colors")
    local row = st:match("function Settings:_newOrnamentsRow%(%)(.-)\nend\n")
    assert(row and row:find("BookshelfSettings.save(Deck.NEW_AT_KEY, value)", 1, true), "the row does not save the choice")
    assert(row:find('"start"),', 1, true) and row:find('"end"),', 1, true), "the row does not offer both choices")
end)

t.done()
