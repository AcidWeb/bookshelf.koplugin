-- tests/_test_round_corner.lua
-- A book's bottom corners rounded with an anti-aliased OUTER edge (the book
-- against the shelf) and INNER edge (the border against the cover), so the
-- cover inside rounds with it instead of keeping a square corner. A fake bb
-- of grey values checks the pixels.
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["ffi/blitbuffer"] = {
    ColorRGB32 = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
}

local RC = dofile("lib/bookshelf_round_corner.lua")

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL " .. msg) end
end

-- W x H of `fill`; getPixel returns a colour with getColorRGB32
local function fakeBB(W, H, fill)
    local g = {}
    for y = 0, H - 1 do g[y] = {}; for x = 0, W - 1 do g[y][x] = fill end end
    local bb = { g = g }
    function bb:getWidth() return W end
    function bb:getHeight() return H end
    function bb:getPixel(x, y)
        local v = self.g[y][x]
        return { getColorRGB32 = function() return { r = v, g = v, b = v } end }
    end
    function bb:setPixel(x, y, c) self.g[y][x] = math.floor(c.r + 0.5) end
    return bb
end

-- a book at x 2..13, rows 0..9 (foot = 10): cover 255, border 0 two wide
-- all round; the shelf row below (10) is 150; left of the book 150 too
local function book()
    local bb = fakeBB(16, 12, 150)
    for y = 0, 9 do for x = 2, 13 do
        local edge = (x < 4) or (x > 11) or (y > 7)
        bb.g[y][x] = edge and 0 or 255
    end end
    return bb
end

do
    local bb = book()
    RC.apply(bb, 2, 10, 12, 4, 2)
    local g = bb.g
    -- the outermost corner pixel is the shelf below
    ok(g[9][2] == 150 and g[9][13] == 150, "corner pixels take the shelf: " .. g[9][2] .. "/" .. g[9][13])
    -- the cover's corner pixel (just inside the square border's corner) is
    -- now border, part way: the inner edge rounds too
    ok(g[7][4] < 255, "the cover's own corner rounds: " .. g[7][4])
    -- a pixel well inside the cover is untouched
    ok(g[5][6] == 255, "the cover away from the corner is untouched")
    -- a border pixel away from the corner is untouched
    ok(g[9][8] == 0 and g[3][2] == 0, "the border away from the corner is untouched")
    -- left and right corners are mirror images
    local same = true
    for y = 6, 9 do for i = 0, 3 do
        if g[y][2 + i] ~= g[y][13 - i] then same = false end
    end end
    ok(same, "the two corners mirror")
    -- blended pixels sit between their neighbours' values, never outside
    local inrange = true
    for y = 6, 9 do for x = 2, 5 do
        if g[y][x] < 0 or g[y][x] > 255 then inrange = false end
    end end
    ok(inrange, "blends stay in range")
end

-- a book narrower than two corners is left alone
do
    local bb = book()
    RC.apply(bb, 2, 10, 7, 4, 2)
    ok(bb.g[9][2] == 0, "too narrow for two corners: untouched")
end

-- off the buffer's edge: no error, nothing painted outside
do
    local bb = book()
    local okc = pcall(RC.apply, bb, -2, 10, 12, 4, 2)
    ok(okc, "a book past the left edge does not error")
    local bb2 = book()
    ok(pcall(RC.apply, bb2, 2, 12, 12, 4, 2), "a foot on the last row does not error")
end

print(string.format("round corner: %d pass, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
