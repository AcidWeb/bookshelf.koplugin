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

return M
