-- lib/bookshelf_ornament_deck.lua
-- WHERE ornaments stand and WHICH piece: fixed, not rolled.
--
-- A frequency level names a pattern (which shelf ends and which group gaps
-- hold a piece), and the pieces are dealt in a SAVED order, cycled: the nth
-- slot on a chip holds the nth card. So the first ornament on a shelf is the
-- same piece after any shelf change and every restart, until the reader
-- swaps two pieces or shuffles (maintainer, 2026-09-28; spec
-- notes/specs/2026-09-28-stable-ornament-placement-design.md).
--
-- Pure apart from the settings store, so the planning passes' agreement can
-- be tested by driving SpineLayout.fillRows with the hooks below.
local M = {}

M.ORDER_KEY = "ornament_deck"
M._store = nil   -- seam: { read = fn(k), save = fn(k, v) }
M._rand  = nil   -- seam: fn(n) -> 1..n

local function store()
    if M._store then return M._store end
    local ok, Store = pcall(require, "lib/bookshelf_settings_store")
    return ok and Store or nil
end

local _state = nil
local function rand(n)
    if M._rand then return M._rand(n) end
    local s = _state or (os.time() % 2147483647)
    s = (s * 48271) % 2147483647
    _state = s
    return (s % n) + 1
end

local _epoch, _gen = 0, 0
function M.epoch() return _epoch end
function M.generation() return _gen end

local function readOrder()
    local st = store()
    local ok, v = pcall(function() return st and st.read(M.ORDER_KEY) end)
    return (ok and type(v) == "table") and v or nil
end
local function saveOrder(list)
    local st = store()
    if st then pcall(function() st.save(M.ORDER_KEY, list) end) end
    _gen = _gen + 1
end

function M.names()
    local out = {}
    for i, n in ipairs(readOrder() or {}) do out[i] = n end
    return out
end

local function shuffled(list)
    local o = {}
    for i = 1, #list do o[i] = list[i] end
    for i = #o, 2, -1 do
        local j = rand(i)
        o[i], o[j] = o[j], o[i]
    end
    return o
end

-- reconcile(all_names): the saved order, kept to the pieces that exist, with
-- any new ones appended at the end (appending keeps every other position).
-- No saved order yet: a shuffle of all_names. Saved only when it changed.
function M.reconcile(all_names)
    local saved = readOrder()
    if not saved then
        saveOrder(shuffled(all_names))
        return
    end
    local exists, out, seen, changed = {}, {}, {}, false
    for _i, n in ipairs(all_names) do exists[n] = true end
    for _i, n in ipairs(saved) do
        if exists[n] and not seen[n] then out[#out + 1] = n; seen[n] = true
        else changed = true end
    end
    for _i, n in ipairs(all_names) do
        if not seen[n] then out[#out + 1] = n; seen[n] = true; changed = true end
    end
    if changed then saveOrder(out) end
end

-- order(pool) -> the pool's entries in saved order. pool is the ENABLED
-- pieces; switched-off ones stay in the saved order (not in the result), so
-- switching one back on returns it to its place. Pieces in the pool that the
-- order has not met yet are reconciled in (appended) first.
function M.order(pool)
    local saved = readOrder()
    local known = {}
    for _i, n in ipairs(saved or {}) do known[n] = true end
    local missing = (saved == nil)
    for _i, e in ipairs(pool) do if not known[e.name] then missing = true end end
    if missing then
        local all, seen = {}, {}
        for _i, n in ipairs(saved or {}) do all[#all + 1] = n; seen[n] = true end
        for _i, e in ipairs(pool) do
            if not seen[e.name] then all[#all + 1] = e.name; seen[e.name] = true end
        end
        if saved then saveOrder(all) else saveOrder(shuffled(all)) end
        saved = readOrder() or all
    end
    local by = {}
    for _i, e in ipairs(pool) do by[e.name] = e end
    local out = {}
    for _i, n in ipairs(saved) do if by[n] then out[#out + 1] = by[n] end end
    return out
end

-- shuffle(names): a new saved order (all known names when nil). Also what
-- clears every swap.
function M.shuffle(names)
    saveOrder(shuffled(names or M.names()))
    _epoch = _epoch + 1
end

-- swap(a, b) -> true when the two exchanged places in the saved order.
function M.swap(a, b)
    if a == b then return false end
    local list = M.names()
    local ia, ib
    for i, n in ipairs(list) do
        if n == a then ia = i elseif n == b then ib = i end
    end
    if not (ia and ib) then return false end
    list[ia], list[ib] = list[ib], list[ia]
    saveOrder(list)
    return true
end

-- ── Patterns ────────────────────────────────────────────────────────────
-- Which slots hold a piece, per level (maintainer's table):
--   Rarely  shelf ends 1 in 4   group gaps never
--   Often   every other shelf   1 in 4 group gaps
--   Always  every shelf         1 in 2 group gaps
-- Counted across the whole chip, from the END of each cycle ("bottom rows
-- first"): Often = shelf 2, 4, 6, so on a two-shelf page every page's lower
-- shelf, and a hanging piece has a shelf above it.
local SHELF_EVERY = { rarely = 4, often = 2, always = 1 }
local GAP_EVERY   = { often = 4, always = 2 }

function M.levelOf(freq)
    freq = tonumber(freq) or 0
    if freq <= 0 then return "off" end
    if freq <= 0.75 then return "rarely" end
    if freq <= 1.5 then return "often" end
    return "always"
end

function M.shelfSlot(level, s)
    local k = SHELF_EVERY[level]
    return k ~= nil and s >= 1 and s % k == 0
end

function M.gapSlot(level, b)
    local k = GAP_EVERY[level]
    return k ~= nil and b >= 1 and b % k == 0
end

-- side(level, s): the shelf-end pieces alternate ends, counted by piece.
function M.side(level, s)
    local k = SHELF_EVERY[level] or 1
    local nth = math.floor(s / k)
    return (nth % 2 == 1) and "right" or "left"
end

-- ── The dealer ──────────────────────────────────────────────────────────
-- State: n = cards dealt from the order so far on this chip; shelf = shelves
-- counted; bnd = group boundaries counted; owed = hanging cards (card
-- numbers) passed over on a top shelf, waiting for a slot with a shelf above.
function M.newState() return { n = 0, shelf = 0, bnd = 0, owed = {} } end
function M.copyState(st)
    st = st or M.newState()
    local o = {}
    for i, c in ipairs(st.owed or {}) do o[i] = c end
    return { n = st.n or 0, shelf = st.shelf or 0, bnd = st.bnd or 0, owed = o }
end

local Dealer = {}
Dealer.__index = Dealer

function M.dealer(st, cards)
    return setmetatable({ st = st or M.newState(), cards = cards or {} }, Dealer)
end

function Dealer:_card(c) return self.cards[(c % #self.cards) + 1] end

-- _choose(top) -> card number, from_owed, skipped (hanging cards passed
-- over), stand. Pure: peek and take share it, so they cannot disagree.
function Dealer:_choose(top)
    local count = #self.cards
    if count == 0 then return nil end
    local st = self.st
    if not top and #st.owed > 0 then return st.owed[1], true, nil, false end
    if not top then return st.n, false, nil, false end
    local c, skipped = st.n, {}
    for _i = 1, count do
        if not self:_card(c).hang then return c, false, skipped, false end
        skipped[#skipped + 1] = c
        c = c + 1
    end
    -- Every card hangs: the first stands on the plank this once.
    return st.n, false, nil, true
end

function Dealer:peek(top)
    local c, _o, _s, stand = self:_choose(top)
    if not c then return nil end
    return self:_card(c), math.floor(c / #self.cards) + 1, stand
end

function Dealer:take(top)
    local c, from_owed, skipped, stand = self:_choose(top)
    if not c then return nil end
    local st = self.st
    if from_owed then
        table.remove(st.owed, 1)
    else
        for _i, s in ipairs(skipped or {}) do st.owed[#st.owed + 1] = s end
        st.n = c + 1
    end
    return self:_card(c), math.floor(c / #self.cards) + 1, stand
end

-- ── Fill hooks ──────────────────────────────────────────────────────────
-- fillHooks(env) -> the callbacks SpineShelf.plan hands SpineLayout.fillRows.
-- ONE implementation for both of plan()'s passes (the render plans a page,
-- pagination plans the whole chip), so they cannot decide differently: that
-- disagreement is what moved page boundaries before. The slot order is the
-- fill's own: a shelf's end piece when the fill starts the shelf, then its
-- books' group gaps as they are placed.
function M.fillHooks(env)
    local d, level, es = env.dealer, env.level, env.entries
    local per_page = math.max(1, tonumber(env.per_page) or 1)
    local h = { row_orn = {}, page_orn = {}, dealer = d }
    local started, dealing = 0, true
    local page_has_book = {}
    for _i, e in ipairs(es) do
        e.ornament, e.lead_ornament, e.gap_before = nil, nil, e.gap_base or e.gap_before or 0
    end
    local function pageOf(r)
        if env.paginating then return math.floor((r - 1) / per_page) + 1, ((r - 1) % per_page) + 1 end
        return 1, r
    end
    local function allowed(r)
        return dealing and (env.paginating or r <= (env.n_rows or 1))
    end
    local function startRow(r, i)
        local _page, within = pageOf(r)
        if env.paginating and within == 1 and i and es[i] and env.pageKey then
            local key = env.pageKey(i)
            if h.page_orn[key] == nil then h.page_orn[key] = M.copyState(d.st) end
        end
        if not allowed(r) then return end
        d.st.shelf = d.st.shelf + 1
        if M.shelfSlot(level, d.st.shelf) then
            local e, no, stand = d:take(within == 1)
            if e then
                local pl = env.size("rowend", e, no, stand)
                if pl then pl.side = M.side(level, d.st.shelf); h.row_orn[r] = pl end
            end
        end
    end
    function h.avail(r, i)
        if r and r > started then
            for k = started + 1, r do startRow(k, i) end
            started = r
        end
        local pl = r and h.row_orn[r]
        if pl then return env.content_w - env.space("rowend", pl) end
        return env.content_w
    end
    -- isBoundary(i, r): a group boundary that counts. Not on the first book a
    -- page places: the render's page starts there and has none.
    local function isBoundary(i, r)
        local e = es[i]
        if not (e and e.orn_seed) then return false end
        return page_has_book[(pageOf(r))] == true
    end
    local function peekPiece(kind, r)
        if not allowed(r) then return nil end
        if not M.gapSlot(level, d.st.bnd + 1) then return nil end
        local _p, within = pageOf(r)
        local e, no, stand = d:peek(within == 1)
        return e and env.size(kind, e, no, stand) or nil
    end
    h.gaps = setmetatable({}, { __index = function(_t, i)
        local e = es[i]
        if not e then return nil end
        local g = e.gap_base or 0
        if isBoundary(i, started) then
            local pl = peekPiece("gap", started)
            if pl then g = g + env.space("gap", pl) end
        end
        return g
    end })
    function h.lead(i)
        if not isBoundary(i, started) then return 0 end
        local pl = peekPiece("lead", started)
        return pl and env.space("lead", pl) or 0
    end
    function h.placed(i, r, starts_row)
        if not allowed(r) then return end
        local counts = isBoundary(i, r)
        page_has_book[(pageOf(r))] = true
        if not counts then return end
        d.st.bnd = d.st.bnd + 1
        if not M.gapSlot(level, d.st.bnd) then return end
        local _p, within = pageOf(r)
        local e, no, stand = d:take(within == 1)
        if not e then return end
        local ent = es[i]
        if starts_row then
            ent.lead_ornament = env.size("lead", e, no, stand)
        else
            local pl = env.size("gap", e, no, stand)
            ent.ornament = pl
            if pl then ent.gap_before = (ent.gap_base or 0) + env.space("gap", pl) end
        end
    end
    function h.empty_ok(r) return h.row_orn[r] ~= nil end
    function h.stop() dealing = false end
    function h.state() return d.st end
    function h.final()
        local gaps, lead, no_break, fixed = {}, {}, {}, {}
        for i, e in ipairs(es) do
            gaps[i] = e.gap_before or 0
            if e.ornament then no_break[i] = true end
            if e.lead_ornament then
                fixed[i] = true
                lead[i] = env.space("lead", e.lead_ornament)
            end
        end
        return gaps, lead, no_break, fixed
    end
    -- bare(from, to): the render's empty planks under the last books. They
    -- come after every other slot on the chip, so they only continue the count.
    function h.bare(from, to)
        local out = {}
        for r = from, to do
            d.st.shelf = d.st.shelf + 1
            if M.shelfSlot(level, d.st.shelf) then
                local e, no, stand = d:take(r == 1)
                if e then
                    local pl = env.size("bare", e, no, stand)
                    if pl then pl.side = M.side(level, d.st.shelf); out[r] = pl end
                end
            end
        end
        return out
    end
    return h
end

return M
