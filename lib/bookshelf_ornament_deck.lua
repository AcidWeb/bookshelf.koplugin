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
-- Where pieces new to the order go: "start" (the default: a reader who adds
-- ornaments sees them first) or "end" (nothing already in the order moves, so
-- the shelf stays as it was). Maintainer, 2026-10-01.
M.NEW_AT_KEY = "ornament_new_at"
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

-- newAtStart() -> whether new pieces join the order at the front.
function M.newAtStart()
    local st = store()
    local ok, v = pcall(function() return st and st.read(M.NEW_AT_KEY) end)
    return not (ok and v == "end")
end

-- join(kept, new) -> kept with new added where the setting says.
local function join(kept, new)
    if #new == 0 then return kept end
    local out = {}
    if M.newAtStart() then
        for _i, n in ipairs(new) do out[#out + 1] = n end
        for _i, n in ipairs(kept) do out[#out + 1] = n end
    else
        for _i, n in ipairs(kept) do out[#out + 1] = n end
        for _i, n in ipairs(new) do out[#out + 1] = n end
    end
    return out
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
-- any new ones joined first or last (see NEW_AT_KEY; last keeps every other
-- position). No saved order yet: a shuffle of all_names. Saved only when it
-- changed.
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
    local new = {}
    for _i, n in ipairs(all_names) do
        if not seen[n] then new[#new + 1] = n; seen[n] = true; changed = true end
    end
    if changed then saveOrder(join(out, new)) end
end

-- sync(all): reconcile the saved order with every piece on disk (switched
-- off or not), once per scan: `all` is the scan's own table (Orn.listAll),
-- which stays the same table while nothing on disk changed.
M._synced_for = nil
function M.sync(all)
    if all == nil or all == M._synced_for then return end
    M._synced_for = all
    local names = {}
    for i, e in ipairs(all) do names[i] = e.name end
    M.reconcile(names)
end

-- order(pool) -> the pool's entries in saved order. pool is the ENABLED
-- pieces; switched-off ones stay in the saved order (not in the result), so
-- switching one back on returns it to its place. Pieces in the pool that the
-- order has not met yet are joined in first, by the same rule as reconcile.
function M.order(pool)
    local saved = readOrder()
    local known = {}
    for _i, n in ipairs(saved or {}) do known[n] = true end
    local missing = (saved == nil)
    for _i, e in ipairs(pool) do if not known[e.name] then missing = true end end
    if missing then
        local kept, new, seen = {}, {}, {}
        for _i, n in ipairs(saved or {}) do kept[#kept + 1] = n; seen[n] = true end
        for _i, e in ipairs(pool) do
            if not seen[e.name] then new[#new + 1] = e.name; seen[e.name] = true end
        end
        local list
        if saved then list = join(kept, new) else list = shuffled(new) end
        saveOrder(list)
        saved = readOrder() or list
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

-- position(name, on) -> its place (1-based) among the pieces that are on,
-- and how many there are; nil for a piece not among them (switched off).
-- `on` is those pieces' names in saved order (Deck.order's names).
function M.position(name, on)
    for i, n in ipairs(on or {}) do
        if n == name then return i, #on end
    end
    return nil
end

-- move(name, delta, on) -> true when the piece traded places with the piece
-- `delta` (-1 earlier, +1 later) away among the ones that are on: the long-
-- press menu's Earlier and Later, a gentler Swap. Wraps past either end: the
-- deck deals round in a loop, so the first and last are neighbours
-- (maintainer).
function M.move(name, delta, on)
    local i = M.position(name, on)
    if not i or #on < 2 then return false end
    local j = ((i - 1 + delta) % #on) + 1
    return M.swap(name, on[j])
end

-- ── Patterns ────────────────────────────────────────────────────────────
-- Which slots hold a piece, per level (maintainer's table):
--   Rarely  shelf ends 1 in 4   group gaps never
--   Often   every other shelf   1 in 4 group gaps
--   Always  every shelf         1 in 2 group gaps
-- Counted across the whole chip, from the END of each cycle ("bottom rows
-- first"): Often = shelf 2, 4, 6, so on a two-shelf page every page's lower
-- shelf, and a piece raised to meet the shelf above has one.
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
-- counted; bnd = group boundaries counted. Every slot takes the next card:
-- a hanging piece on a page's top shelf hangs from the bottom of the top
-- panel (BookshelfWidget:_hangUnder), so no card is ever passed over. (It
-- was, once: a pack whose pieces all hang then gave a lone standing piece
-- every top shelf, PW5.)
function M.newState() return { n = 0, shelf = 0, bnd = 0 } end
function M.copyState(st)
    st = st or M.newState()
    return { n = st.n or 0, shelf = st.shelf or 0, bnd = st.bnd or 0 }
end

local Dealer = {}
Dealer.__index = Dealer

function M.dealer(st, cards)
    return setmetatable({ st = st or M.newState(), cards = cards or {} }, Dealer)
end

function Dealer:_card(c) return self.cards[(c % #self.cards) + 1] end

-- peek() / take() -> the next card and its deal number (how many times this
-- card has been dealt on the chip, counting this one), or nil with no cards.
function Dealer:peek()
    local count = #self.cards
    if count == 0 then return nil end
    local c = self.st.n
    return self:_card(c), math.floor(c / count) + 1
end

function Dealer:take()
    local e, no = self:peek()
    if e then self.st.n = self.st.n + 1 end
    return e, no
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
    local h = { row_orn = {}, row_deal = {}, page_orn = {}, dealer = d }
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
            local e, no = d:take()
            if e then
                local pl = env.size("rowend", e, no)
                if pl then
                    pl.side = M.side(level, d.st.shelf); h.row_orn[r] = pl
                    h.row_deal[r] = { e, no }
                end
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
    -- squeeze(r, need) -> the row's new width, or nil: a row that has to take
    -- a book `need` wide (it may not stand empty) gets its end piece sized
    -- down to the room that leaves, or loses the piece when not even a small
    -- one fits. On a one-row shelf a wide piece otherwise put a face-out past
    -- the plank's end (maintainer). The card stays dealt either way, so
    -- both passes still agree on every later slot.
    function h.squeeze(r, need)
        local pl, deal = h.row_orn[r], h.row_deal[r]
        if not pl or not deal then return nil end
        local room = env.content_w - need
        local pads = env.space("rowend", pl) - pl.w
        if pl.w + pads <= room then return nil end
        local cap = room - pads
        local small = cap > 0 and env.size("rowend", deal[1], deal[2], cap) or nil
        -- Not a scrap: under a quarter of its own width it is not the piece
        -- any more (sizeFor never refuses a size), so it comes off the row.
        if small and small.w * 4 >= pl.w and env.space("rowend", small) <= room then
            small.side = pl.side
            h.row_orn[r] = small
            return env.content_w - env.space("rowend", small)
        end
        h.row_orn[r] = nil
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
        local e, no = d:peek()
        return e and env.size(kind, e, no) or nil
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
        local e, no = d:take()
        if not e then return end
        local ent = es[i]
        if starts_row then
            ent.lead_ornament = env.size("lead", e, no)
        else
            local pl = env.size("gap", e, no)
            ent.ornament = pl
            if pl then ent.gap_before = (ent.gap_base or 0) + env.space("gap", pl) end
        end
    end
    -- A row may stand as its piece alone, but a page's LAST row may not when
    -- the page has no book yet: a page of nothing but pieces has no first
    -- book to name it, and the plan has no book to end it on (review: a
    -- whole-row piece on every shelf crashed plan). Page-relative, so both
    -- passes agree.
    function h.empty_ok(r)
        if h.row_orn[r] == nil then return false end
        local page, within = pageOf(r)
        local last = env.paginating and per_page or (env.n_rows or per_page)
        if within >= last and not page_has_book[page] then return false end
        return true
    end
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
                local e, no = d:take()
                if e then
                    local pl = env.size("bare", e, no)
                    if pl then pl.side = M.side(level, d.st.shelf); out[r] = pl end
                end
            end
        end
        return out
    end
    return h
end

return M
