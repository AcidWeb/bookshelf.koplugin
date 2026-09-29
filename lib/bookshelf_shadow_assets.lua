--[[
Book shadows from three image masks (assets/shadows), in place of the banded
ramps the recess painter computes. Each mask is a plain greyscale PNG whose
value is the shadow's opacity; loaded once per screen scale and night state
into a BB8A of the shadow colour (black by day, white in a night frame, as
Wallpaper.shadeRect darkens or lightens) and alpha-blitted, so where two
shadows overlap they multiply: a narrow gap is darker than either side.

  side  the wedge beside a book, drawn for its RIGHT side and mirrored for
        the left. Its outline runs from just above the book's top corner,
        out and down to the wall line, then back across the plank to just
        below the bottom corner. The taper (top corner to wall line) is
        stretched to each book's height, cached per height; the plank part
        is fixed.
  top   the halo above a spine: uniform across, tiled to the spine's width.
  foot  the contact line on the plank surface under a run of books, with a
        fade-in cap at each end.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local logger     = require("logger")
local Screen     = Device.screen

local M = {}

-- dp layout of the files; keep in step with shadowgen.py
M.DP = { side = 10, up = 96, wall = 10, below = 3, above = 2,
         halo = 6, tile = 48, cap = 5, foot = 5 }
-- stretched tapers kept per set (a page holds a few dozen book heights)
M.TAPER_CACHE = 96

M._cache = {}

local function pluginRoot()
    local src = debug.getinfo(1, "S").source or ""
    local dir = src:match("^@(.*)/lib/[^/]+$")
    return dir or "."
end

-- mask(path, w, h) -> BB8 of the mask at w x h, or nil
local function loadMask(path, w, h)
    local ok_r, RenderImage = pcall(require, "ui/renderimage")
    if not ok_r then return nil end
    local ok, bb = pcall(function()
        return RenderImage:renderImageFile(path, false, w, h)
    end)
    if not ok or not bb then return nil end
    if bb:getWidth() ~= w or bb:getHeight() ~= h then
        local ok_s, sc = pcall(function()
            return RenderImage:scaleBlitBuffer(bb, w, h)
        end)
        if ok_s and sc then bb = sc end
    end
    return bb
end

-- tint(mask, grey, mirror, y0, h) -> BB8A of rows [y0, y0+h): every pixel
-- `grey`, alpha = mask value
local function tint(mask, grey, mirror, y0, h)
    local w = mask:getWidth()
    y0 = y0 or 0
    h = h or (mask:getHeight() - y0)
    local out = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8A)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local a = mask:getPixel(x, y0 + y):getColor8().a
            out:setPixel(mirror and (w - 1 - x) or x, y, Blitbuffer.Color8A(grey, a))
        end
    end
    return out
end

-- stretched(a, part, h, dir, w) -> part ("up": the taper, "low": the plank
-- piece) scaled to w x h (MuPDF's scaler, in C), cached per size
local function stretched(a, part, h, dir, w)
    w = w or a.side_w
    local key = part .. dir .. h .. "x" .. w
    local t = a.tapers[key]
    if t then return t end
    local src = a[part .. ((dir == "left") and "_l" or "_r")]
    local ok, sc = pcall(function()
        if src:getHeight() == h and w == a.side_w then return src end
        return require("ffi/mupdf").scaleBlitBuffer(src, w, h)
    end)
    if not ok or not sc then return nil end
    a.n_tapers = a.n_tapers + 1
    if a.n_tapers > M.TAPER_CACHE then
        local keep = { [a.up_l] = true, [a.up_r] = true, [a.low_l] = true, [a.low_r] = true }
        for k, bb in pairs(a.tapers) do
            if not keep[bb] then pcall(function() bb:free() end) end
            a.tapers[k] = nil
        end
        a.n_tapers = 1
    end
    a.tapers[key] = sc
    return sc
end

-- get(night) -> the tinted set for this screen, or nil (files missing)
function M.get(night)
    local key = (night and "n" or "d") .. Screen:scaleBySize(100)
    local c = M._cache[key]
    if c ~= nil then return c or nil end
    local D = M.DP
    local s = function(dp) return math.max(1, Screen:scaleBySize(dp)) end
    local side_w, up = s(D.side), s(D.up)
    local low = s(D.wall) + s(D.below)
    local tile, cap, halo, foot = s(D.tile), s(D.cap), s(D.halo), s(D.foot)
    local dir = pluginRoot() .. "/assets/shadows/"
    local side = loadMask(dir .. "shadow.side.png", side_w, up + low)
    local top  = loadMask(dir .. "shadow.top.png", tile, halo)
    local ft   = loadMask(dir .. "shadow.foot.png", cap + tile, foot)
    if not (side and top and ft) then
        logger.warn("[bookshelf] shadow assets missing in", dir)
        M._cache[key] = false
        return nil
    end
    local grey = night and 0xFF or 0x00
    c = {
        up_r = tint(side, grey, false, 0, up), up_l = tint(side, grey, true, 0, up),
        low_r = tint(side, grey, false, up, low), low_l = tint(side, grey, true, up, low),
        top = tint(top, grey),
        foot_l = tint(ft, grey), foot_r = tint(ft, grey, true),
        side_w = side_w, low = low, wall = s(D.wall), below = s(D.below),
        above = s(D.above), tile = tile, cap = cap, halo = halo, foot = foot,
        tapers = {}, n_tapers = 0,
    }
    for _k, bb in pairs({ side, top, ft }) do pcall(function() bb:free() end) end
    M._cache[key] = c
    return c
end

local function blit(bb, src, dx, dy, sx, sy, w, h)
    if w > 0 and h > 0 then bb:alphablitFrom(src, dx, dy, sx, sy, w, h) end
end

-- side(bb, a, edge_x, dir, book_top, floor, parts, wall_h, fit): the wedge
-- beside a book whose edge is at edge_x, toward dir ("right" or "left"). It
-- runs from a.above over book_top, out to the wall line wall_h above the
-- floor (where the plank's top surface meets the wall; default a.wall), and
-- back across the plank to a.below under the floor. parts: a list of
-- { x0, x1, y0, y1 } (x measured from the edge, y absolute) where the
-- wedge shows; the rest is under a neighbour. fit: squeeze the wedge to
-- that width (the room left at a shelf's end) instead of cutting it off.
-- Absolute bb coordinates.
function M.side(bb, a, edge_x, dir, book_top, floor, parts, wall_h, fit)
    local W = a.side_w
    if fit and fit < W then W = math.max(1, math.floor(fit)) else fit = nil end
    wall_h = math.max(1, math.floor(tonumber(wall_h) or a.wall))
    local top  = book_top - a.above
    local wall = floor - wall_h                -- taper / plank boundary
    local bot  = floor + a.below
    local up_h = wall - top
    local up   = up_h > 0 and stretched(a, "up", up_h, dir, W) or nil
    local low  = stretched(a, "low", bot - wall, dir, W)
    for _i, p in ipairs(parts) do
        local x0, x1 = math.max(0, p[1]), math.min(W, p[2])
        if x1 > x0 then
            local sx, dx
            if dir == "left" then sx, dx = W - x1, edge_x - x1
            else sx, dx = x0, edge_x + x0 end
            local w = x1 - x0
            -- the taper rows [top, wall), then the plank rows [wall, bot)
            if up then
                local r0, r1 = math.max(p[3], top), math.min(p[4], wall)
                if r1 > r0 then blit(bb, up, dx, r0, sx, r0 - top, w, r1 - r0) end
            end
            local r0, r1 = math.max(p[3], wall, top), math.min(p[4], bot)
            if low and r1 > r0 then
                blit(bb, low, dx, r0, sx, r0 - wall, w, r1 - r0)
            end
        end
    end
end

-- across(bb, src, tile, sx, x0, x1, y, sy, h): src columns [sx, sx+tile)
-- tiled over [x0, x1).
local function across(bb, src, tile, sx, x0, x1, y, sy, h)
    local x = x0
    while x < x1 do
        local n = math.min(tile, x1 - x)
        blit(bb, src, x, y, sx, sy, n, h)
        x = x + n
    end
end

-- top(bb, a, x, w, book_top): the halo above a spine at [x, x+w).
function M.top(bb, a, x, w, book_top)
    local y = book_top - a.halo
    local sy, h = 0, a.halo
    if y < 0 then sy = -y; h = h + y; y = 0 end
    if h <= 0 or w <= 0 then return end
    across(bb, a.top, a.tile, 0, x, x + w, y, sy, h)
end

-- foot(bb, a, x0, x1, y, h, lcap, rcap): the contact line under a run
-- [x0, x1), rows [y, y+h), with end caps lcap / rcap px wide (0: none).
function M.foot(bb, a, x0, x1, y, h, lcap, rcap)
    h = math.min(h, a.foot)
    if h <= 0 or x1 <= x0 then return end
    lcap = math.min(lcap or a.cap, a.cap); rcap = math.min(rcap or a.cap, a.cap)
    if lcap > 0 then blit(bb, a.foot_l, x0 - lcap, y, a.cap - lcap, 0, lcap, h) end
    across(bb, a.foot_l, a.tile, a.cap, x0, x1, y, 0, h)
    if rcap > 0 then blit(bb, a.foot_r, x1, y, a.tile, 0, rcap, h) end
end

-- paintRow(bb, ox, oy, cols, opts): the whole recess of one row.
--   cols      recess_cols: { x, w, h, foot } left to right, row-local
--   opts      { stand_h, width, below, wall, night }: the floor row, the
--             row's width, the plank surface rows under the floor (inset),
--             how far above the floor the surface meets the wall
function M.paintRow(bb, ox, oy, cols, opts)
    -- Without the C blitter an alpha blit is per-pixel Lua: no shadow beats a
    -- paint measured in seconds (Wallpaper.shadeRect's rule). Done, not
    -- failed, so the banded painter does not try either.
    if type(bb.canUseCbb) == "function" and not bb:canUseCbb() then return true end
    local a = M.get(opts.night)
    if not a then return false end
    local stand_h, width = opts.stand_h, opts.width
    local below = math.max(0, opts.below or 0)
    local n = #cols
    for i = 1, n do
        local c = cols[i]
        local book_top = stand_h - math.min(c.h, stand_h)
        local floor = stand_h - (c.foot or 0)
        M.top(bb, a, ox + c.x, c.w, oy + book_top)
        -- Each side: the whole wedge in the gap before the next book; over
        -- that book, only what shows above it when it is shorter (under it
        -- the contact line is the shadow). Wedges from both sides of a gap
        -- overlap and multiply.
        local plank_end = oy + stand_h + below
        for _s, dir in ipairs({ "right", "left" }) do
            -- not `and cols[i + 1] or cols[i - 1]`: with no book to the
            -- right that picks the one to the LEFT
            local nb
            if dir == "right" then nb = cols[i + 1] else nb = cols[i - 1] end
            local edge = (dir == "right") and (c.x + c.w) or c.x
            local room
            if nb then
                room = (dir == "right") and (nb.x - edge) or (edge - (nb.x + nb.w))
            else
                room = (dir == "right") and (width - edge) or edge
            end
            room = math.max(0, room)
            local parts = { { 0, room, 0, plank_end } }
            if nb then
                local far = room + nb.w
                local nb_top = stand_h - math.min(nb.h, stand_h)
                if nb_top > book_top then
                    parts[#parts + 1] = { room, far, 0, oy + nb_top }
                end
            end
            M.side(bb, a, ox + edge, dir, oy + book_top, oy + floor, parts, opts.wall,
                   (not nb) and room or nil)
        end
    end
    -- contact line: under each run of standing (not face-out) books
    if below > 0 then
        local i = 1
        while i <= n do
            local c = cols[i]
            if (c.foot or 0) == 0 then
                local j = i
                while j < n and (cols[j + 1].foot or 0) == 0
                        and cols[j + 1].x <= cols[j].x + cols[j].w do
                    j = j + 1
                end
                local x0, x1 = c.x, cols[j].x + cols[j].w
                local lroom = (i > 1) and (x0 - (cols[i - 1].x + cols[i - 1].w)) or x0
                local rroom = (j < n) and (cols[j + 1].x - x1) or (width - x1)
                M.foot(bb, a, ox + x0, ox + x1, oy + stand_h, below,
                       math.max(0, lroom), math.max(0, rroom))
                i = j + 1
            else
                i = i + 1
            end
        end
    end
    return true
end

return M
