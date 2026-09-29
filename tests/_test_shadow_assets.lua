-- tests/_test_shadow_assets.lua
-- The book-shadow wedge is a taper (stretched to the book) over a fixed
-- plank part, painted only where a neighbour leaves it showing. A fake bb
-- records every blit, so these check which mask rows land on which rows.
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg=function() end, info=function() end,
                             warn=function() end, err=function() end }
package.loaded["ffi/blitbuffer"] = {}
package.loaded["device"] = { screen = { scaleBySize = function(_s, v) return v end } }
local scaled = {}
package.loaded["ffi/mupdf"] = { scaleBlitBuffer = function(src, w, h)
    scaled[#scaled + 1] = h
    return { name = "taper" .. h, src = src, w = w, getHeight = function() return h end }
end }

local SA = dofile("lib/bookshelf_shadow_assets.lua")

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL " .. msg) end
end

local function fakeBB()
    local bb = { blits = {} }
    function bb:alphablitFrom(src, dx, dy, sx, sy, w, h)
        self.blits[#self.blits + 1] = { src = src, dx = dx, dy = dy, sx = sx, sy = sy, w = w, h = h }
    end
    return bb
end

local function set()
    local up = { name = "UP", getHeight = function() return 50 end }
    return { up_r = up, up_l = { name = "UPL", getHeight = function() return 50 end },
             low_r = { name = "LOW", getHeight = function() return 5 end },
             low_l = { name = "LOWL", getHeight = function() return 5 end }, top = "TOP", foot_l = "FL", foot_r = "FR",
             side_w = 4, low = 5, wall = 3, below = 2, above = 1,
             tile = 5, cap = 2, halo = 2, foot = 2, tapers = {}, n_tapers = 0 }
end

-- rowsOf(bb) -> row -> { src, sy }; fails on a row painted twice
local function rowsOf(bb, msg)
    local map = {}
    for _i, b in ipairs(bb.blits) do
        for k = 0, b.h - 1 do
            local y = b.dy + k
            ok(map[y] == nil, msg .. ": row " .. y .. " painted once")
            map[y] = { src = b.src, sy = b.sy + k }
        end
    end
    return map
end

-- a free-standing wedge: taper from one above the top to the wall line,
-- then the plank part to two below the floor
do
    local a, bb = set(), fakeBB()
    SA.side(bb, a, 100, "right", 10, 30, { { 0, 4, 0, 99 } })
    local m = rowsOf(bb, "free")
    ok(m[8] == nil and m[9] and m[9].src.name == "taper18" and m[9].sy == 0, "taper starts one above the top")
    ok(m[26] and m[26].sy == 17, "taper ends at the wall line")
    ok(m[27] and m[27].src.name == "LOW" and m[27].sy == 0, "plank part from the wall line")
    ok(m[31] and m[31].sy == 4 and m[32] == nil, "plank part ends two below the floor")
    ok(bb.blits[1].dx == 100 and bb.blits[1].sx == 0 and bb.blits[1].w == 4, "right wedge at the edge")
end

-- the taper is stretched once per height and reused
do
    local a = set()
    scaled = {}
    SA.side(fakeBB(), a, 100, "right", 10, 30, { { 0, 4, 0, 99 } })
    SA.side(fakeBB(), a, 200, "right", 10, 30, { { 0, 4, 0, 99 } })
    SA.side(fakeBB(), a, 300, "right", 12, 30, { { 0, 4, 0, 99 } })
    ok(#scaled == 2 and scaled[1] == 18 and scaled[2] == 16, "one stretch per height")
end

-- a left wedge is mirrored and cropped to the columns nearest the book
do
    local a, bb = set(), fakeBB()
    SA.side(bb, a, 100, "left", 10, 30, { { 0, 3, 0, 99 } })
    local b = bb.blits[1]
    ok(b.src.name == "taper18" and b.src.src.name == "UPL" and b.dx == 97 and b.sx == 1 and b.w == 3,
       "left wedge: mirrored, near columns")
end

-- paintRow: a tall book, a shorter one touching it, a gap of 2, a third
do
    SA._cache["d100"] = set()
    local bb = fakeBB()
    local cols = { { x = 10, w = 5, h = 12 }, { x = 15, w = 5, h = 8 }, { x = 22, w = 5, h = 8 } }
    SA.paintRow(bb, 0, 0, cols, { stand_h = 20, width = 40, below = 2 })
    -- book 1's right wedge (edge 15) lies over book 2: only above book 2's
    -- top (row 12); under it the contact line is the shadow
    local covered = false
    for _i, b in ipairs(bb.blits) do
        if b.dx == 15 and type(b.src) == "table" and b.src.src and b.src.src.name == "UP" then
            if b.dy + b.h > 12 then covered = true end
        end
        if b.dx == 15 and b.src.name == "LOW" then covered = true end
    end
    ok(not covered, "nothing painted where the shorter neighbour stands")
    -- both sides of the 2px gap paint into it: the wedges overlap
    local from_left, from_right = false, false
    for _i, b in ipairs(bb.blits) do
        if b.dx == 20 and b.w >= 2 then from_left = true end
        if b.dx + b.w == 22 and b.dx <= 20 then from_right = true end
    end
    ok(from_left and from_right, "a narrow gap takes a wedge from each side")
    local tops = 0
    for _i, b in ipairs(bb.blits) do if b.src == "TOP" then tops = tops + 1 end end
    ok(tops == 3, "one halo per book: " .. tops)
end

-- the LAST book still gets its right wedge (no neighbour must not mean
-- "the book to the left")
do
    SA._cache["d100"] = set()
    local bb = fakeBB()
    local cols = { { x = 10, w = 5, h = 8 }, { x = 15, w = 5, h = 8 } }
    SA.paintRow(bb, 0, 0, cols, { stand_h = 20, width = 40, below = 2 })
    local right_end = false
    for _i, b in ipairs(bb.blits) do
        if b.dx == 20 and b.w == 4 and b.dy < 20 then right_end = true end
    end
    ok(right_end, "the last book's right wedge is painted")
end

-- the plank part stretches to the row's real wall line
do
    local a, bb = set(), fakeBB()
    scaled = {}
    SA.side(bb, a, 100, "right", 10, 30, { { 0, 4, 0, 99 } }, 7)
    local m = rowsOf(bb, "wall")
    ok(m[22] and m[22].src.name == "taper14" and m[23] and m[23].src.name == "taper9", "taper to the wall line 7 up")
    ok(m[31] and m[31].sy == 8 and m[32] == nil, "plank part stretched to 9 rows")
end

-- a shelf end with less room than the wedge: squeezed to fit, not cut off
do
    SA._cache["d100"] = set()
    local bb = fakeBB()
    SA.paintRow(bb, 0, 0, { { x = 10, w = 5, h = 8 } }, { stand_h = 20, width = 17, below = 2 })
    local squeezed, cut = false, false
    for _i, b in ipairs(bb.blits) do
        if b.dx == 15 and type(b.src) == "table" and b.src.w then
            if b.src.w == 2 and b.w == 2 and b.sx == 0 then squeezed = true else cut = true end
        end
    end
    ok(squeezed and not cut, "row end: the wedge squeezed into 2px")
end

-- no C blitter: nothing painted, and reported done
do
    local bb = fakeBB()
    function bb:canUseCbb() return false end
    ok(SA.paintRow(bb, 0, 0, { { x = 0, w = 5, h = 8 } }, { stand_h = 20, width = 40 }) == true
       and #bb.blits == 0, "no C blitter: no blits, done")
end

print(string.format("shadow assets: %d pass, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
