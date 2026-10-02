-- tests/_test_shadow_colour.lua
-- Book shadows over a colour wallpaper (maintainer, 2026-10-02: "the shadows
-- must be pure black with alpha"). KOReader's C alpha blit of a grey + alpha
-- (BB8A) mask onto a colour (RGB32) buffer flattens what is under it to grey:
-- measured, beige (245,224,193) under black at 25% came out (169,169,169).
-- The same black as an RGB32 source darkens it and keeps its hue
-- (184,168,145). So on a colour buffer the masks are blitted as RGB32 copies:
-- black (white in a night frame) with the same alpha.
-- Usage (from plugin root): lua tests/_test_shadow_colour.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg = function() end, info = function() end,
                             warn = function() end, err = function() end }
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq

local TYPE_BB8, TYPE_BB8A, TYPE_RGB32 = 1, 2, 9
-- A buffer that keeps its pixels: { v, alpha } for grey, { r, g, b, alpha } for RGB32.
local function buf(w, h, ty)
    local b = { w = w, h = h, ty = ty, px = {}, freed = false }
    function b:getWidth() return self.w end
    function b:getHeight() return self.h end
    function b:getType() return self.ty end
    function b:getPixel(x, y) return self.px[y * self.w + x] or { a = 0, alpha = 0 } end
    function b:setPixel(x, y, c) self.px[y * self.w + x] = c end
    function b:free() self.freed = true end
    return b
end
package.loaded["ffi/blitbuffer"] = {
    TYPE_BB8 = TYPE_BB8, TYPE_BB8A = TYPE_BB8A, TYPE_BBRGB32 = TYPE_RGB32,
    new = function(w, h, ty) return buf(w, h, ty) end,
    ColorRGB32 = function(r, g, b, a) return { r = r, g = g, b = b, alpha = a } end,
}
package.loaded["device"] = { screen = { scaleBySize = function(_s, v) return v end } }
package.loaded["lib/bookshelf_shadow_assets"] = nil
local SA = dofile("lib/bookshelf_shadow_assets.lua")

t.test("a mask's colour copy is the same shade with the same alpha", function()
    local g = buf(3, 1, TYPE_BB8A)
    g:setPixel(0, 0, { a = 0, alpha = 64 })        -- black, a quarter
    g:setPixel(1, 0, { a = 0, alpha = 255 })
    g:setPixel(2, 0, { a = 255, alpha = 128 })     -- white (a night frame's)
    local c = SA._colourMask(g)
    eq(c:getType(), TYPE_RGB32)
    local p = c:getPixel(0, 0); eq(p.r, 0); eq(p.g, 0); eq(p.b, 0); eq(p.alpha, 64)
    p = c:getPixel(1, 0); eq(p.r + p.g + p.b, 0); eq(p.alpha, 255)
    p = c:getPixel(2, 0); eq(p.r, 255); eq(p.g, 255); eq(p.b, 255); eq(p.alpha, 128)
    eq(g.freed, true, "the grey mask was kept as well")
end)

t.test("a row on a colour buffer asks for the colour set, on a grey one the grey set", function()
    local asked = {}
    local real = SA.get
    SA.get = function(night, colour) asked[#asked + 1] = { night, colour }; return nil end
    local function bb(ty) local b = buf(10, 10, ty); function b:canUseCbb() return true end; return b end
    SA.paintRow(bb(TYPE_RGB32), 0, 0, {}, { stand_h = 5, width = 10, night = false })
    SA.paintRow(bb(TYPE_BB8), 0, 0, {}, { stand_h = 5, width = 10, night = true })
    SA.get = real
    eq(asked[1][2], true, "a colour buffer got the grey masks")
    eq(asked[2][2], false, "a grey buffer got the colour masks"); eq(asked[2][1], true)
end)

t.test("the colour and grey sets are cached apart, and built buffers keep their source's type", function()
    local src = io.open("lib/bookshelf_shadow_assets.lua"):read("*a")
    local get = src:match("\nfunction M%.get%(night, colour%)\n(.-)\nend\n")
    assert(get, "get does not take the colour")
    assert(get:find('(colour and "c" or "g")', 1, true), "one cache entry for both")
    assert(get:find("M._colourMask(", 1, true), "the colour set is not converted")
    for _i, fn in ipairs({ "rows", "mirrored" }) do
        local body = src:match("\nlocal function " .. fn .. "%(.-\nend\n")
        assert(body and body:find("typeOf(bb)", 1, true), fn .. " makes a grey buffer whatever its source")
    end
    local wedge = src:match("\nlocal function wedge%(.-\nend\n")
    assert(wedge and wedge:find("typeOf(", 1, true), "the joined wedge is always grey")
end)

t.done()
