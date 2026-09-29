-- tests/_test_shadow_assets.lua
-- The book-shadow wedge is a taper (stretched to the book, height rounded up
-- to a bucket) joined to a plank part, painted only where a neighbour leaves
-- it showing. Fake buffers record every copy and blit, so these check which
-- wedge rows land on which screen rows.
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg=function() end, info=function() end,
                             warn=function() end, err=function() end }

local function fakeBuf(name, w, h)
    local b = { name = name, w = w, h = h, copies = {} }
    function b:getWidth() return self.w end
    function b:getHeight() return self.h end
    function b:blitFrom(src, dx, dy, sx, sy, cw, ch)
        self.copies[#self.copies + 1] = { src = src, dy = dy, h = ch }
    end
    function b:free() end
    return b
end
package.loaded["ffi/blitbuffer"] = {
    TYPE_BB8A = 2,
    new = function(w, h) return fakeBuf("wedge", w, h) end,
}
package.loaded["device"] = { screen = { scaleBySize = function(_s, v) return v end } }
local scaled = {}
package.loaded["ffi/mupdf"] = { scaleBlitBuffer = function(src, w, h)
    scaled[#scaled + 1] = { src = src.name, w = w, h = h }
    return fakeBuf(src.name .. "@" .. w .. "x" .. h, w, h)
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

-- side 4 wide; plank part 5 rows (wall 3 + below 2); bucket 4
local function set()
    return { up_r = fakeBuf("UP", 4, 50), up_l = fakeBuf("UPL", 4, 50),
             low_r = fakeBuf("LOW", 4, 5), low_l = fakeBuf("LOWL", 4, 5),
             top = "TOP", foot_l = "FL", foot_r = "FR",
             side_w = 4, low = 5, wall = 3, below = 2, above = 1,
             tile = 5, cap = 2, halo = 2, foot = 2, wedges = {}, n_wedges = 0, lows = {} }
end

-- a free-standing wedge: book top 10, floor 30 -> rows 9 (one above the top)
-- to 32 (two below the floor); taper 18 rows, bucketed to 20
do
    local a, bb = set(), fakeBB()
    scaled = {}
    SA.side(bb, a, 100, "right", 10, 30, { { 0, 4, 0, 99 } })
    ok(#bb.blits == 1, "one blit for the whole wedge: " .. #bb.blits)
    local b = bb.blits[1]
    ok(b.dy == 9 and b.h == 23, "rows 9..31: " .. b.dy .. "+" .. b.h)
    ok(b.sy == 2, "the two spare bucket rows cut from the tip: sy " .. b.sy)
    ok(b.dx == 100 and b.sx == 0 and b.w == 4, "right wedge at the edge")
    local w = b.src
    ok(w.h == 25, "joined wedge: 20 taper + 5 plank rows: " .. w.h)
    ok(w.copies[1].src.name == "UP@4x20" and w.copies[1].dy == 0, "taper stretched to the bucket, on top")
    ok(w.copies[2].src.name == "LOW" and w.copies[2].dy == 20, "plank part under it, unscaled")
end

-- heights in the same bucket share one wedge
do
    local a = set()
    scaled = {}
    SA.side(fakeBB(), a, 100, "right", 10, 30, { { 0, 4, 0, 99 } })   -- taper 18
    SA.side(fakeBB(), a, 200, "right", 11, 30, { { 0, 4, 0, 99 } })   -- 17
    SA.side(fakeBB(), a, 300, "right", 12, 30, { { 0, 4, 0, 99 } })   -- 16
    ok(#scaled == 2 and scaled[1].h == 20 and scaled[2].h == 16, "18 and 17 share a stretch, 16 its own")
end

-- the plank part is stretched once for every wedge on the same wall line
do
    local a = set()
    scaled = {}
    SA.side(fakeBB(), a, 100, "right", 10, 30, { { 0, 4, 0, 99 } }, 7)
    SA.side(fakeBB(), a, 200, "right", 16, 30, { { 0, 4, 0, 99 } }, 7)
    local lows = 0
    for _i, sc in ipairs(scaled) do if sc.src == "LOW" then lows = lows + 1 end end
    ok(lows == 1, "one plank stretch for two wedges: " .. lows)
end

-- a left wedge is joined from the mirrored parts, cropped nearest the book
do
    local a, bb = set(), fakeBB()
    SA.side(bb, a, 100, "left", 10, 30, { { 0, 3, 0, 99 } })
    local b = bb.blits[1]
    ok(b.src.copies[1].src.name == "UPL@4x20" and b.dx == 97 and b.sx == 1 and b.w == 3,
       "left wedge: mirrored, near columns")
end

-- the plank part stretches to the row's real wall line
do
    local a, bb = set(), fakeBB()
    SA.side(bb, a, 100, "right", 10, 30, { { 0, 4, 0, 99 } }, 7)
    local w = bb.blits[1].src
    ok(w.copies[2].src.name == "LOW@4x9" and w.copies[1].src.name == "UP@4x16",
       "wall 7 up: plank part 9 rows, taper 14 bucketed to 16")
end

-- paintRow: a tall book, a shorter one touching it, a gap of 2, a third
do
    SA._cache["d100"] = set()
    local bb = fakeBB()
    local cols = { { x = 10, w = 5, h = 12 }, { x = 15, w = 5, h = 8 }, { x = 22, w = 5, h = 8 } }
    SA.paintRow(bb, 0, 0, cols, { stand_h = 20, width = 40, below = 2 })
    -- book 1's right wedge (edge 15) lies over book 2: only above its top
    local covered = false
    for _i, b in ipairs(bb.blits) do
        if b.dx == 15 and b.src.name == "wedge" and b.dy + b.h > 12 then covered = true end
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

-- a shelf end with less room than the wedge: squeezed to fit, not cut off
do
    SA._cache["d100"] = set()
    local bb = fakeBB()
    SA.paintRow(bb, 0, 0, { { x = 10, w = 5, h = 8 } }, { stand_h = 20, width = 17, below = 2 })
    local squeezed, cut = false, false
    for _i, b in ipairs(bb.blits) do
        if b.dx == 15 and b.src.name == "wedge" then
            if b.src.w == 2 and b.w == 2 and b.sx == 0 then squeezed = true else cut = true end
        end
    end
    ok(squeezed and not cut, "row end: the wedge squeezed into 2px")
end

-- a face-out (foot = its push back) gets the same contact line at its own
-- foot, over the strip up to where the spines stand; the spines keep theirs
do
    SA._cache["d100"] = set()
    local bb = fakeBB()
    local cols = { { x = 10, w = 5, h = 8 }, { x = 15, w = 9, h = 6, foot = 2 }, { x = 24, w = 5, h = 8 } }
    SA.paintRow(bb, 0, 0, cols, { stand_h = 20, width = 40, below = 2 })
    local fo_w, spines = 0, 0
    for _i, b in ipairs(bb.blits) do
        if b.src == "FL" and b.dy == 18 and b.h == 2 and b.dx >= 15 and b.dx < 24 then fo_w = fo_w + b.w end
        if b.src == "FL" and b.dy == 20 then spines = spines + 1 end
    end
    ok(fo_w == 9, "contact line across the face-out at its foot (row 18, 2 rows): " .. fo_w)
    ok(spines >= 2, "the spines either side keep theirs: " .. spines)
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
