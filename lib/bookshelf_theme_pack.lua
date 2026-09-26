-- bookshelf_theme_pack.lua
-- Theme packs: an ornament pack's theme/ subfolder, and which pack's parts are
-- BORROWED right now.
--
--   <pack>/theme/wallpaper.<ext>            + .full / .dark / .full.dark variants
--   <pack>/theme/plank.middle.png           + plank.left.png / plank.right.png
--   <pack>/theme/colours.json               {"day": {name: "#RRGGBB"}, "night": {...}}
--
-- In a subfolder on purpose: the ornament scan is one level deep and png/svg
-- only (bookshelf_ornaments.listAll), so 5.2.x installs a theme pack as a plain
-- ornament pack and never mistakes wallpaper.png for an ornament.
--
-- BORROWING. A theme never writes the reader's own settings. Three keys say
-- which pack is lent to what; everything that paints asks here first and
-- falls back to the reader's own choice. Turning a part off deletes one key,
-- and the reader's settings are exactly as they left them however long the
-- theme was on (maintainer's ruling: borrow, not apply).
--
-- Wallpaper and colours switch separately (a reader may want a pack's picture
-- and keep their own colours, especially on black-and-white screens). The
-- plank design goes with the ornaments: it follows the pack's on/off and has
-- its own entry in the ornament off-set; one plank shows at a time.
local logger = require("logger")

local M = {}

M.SUBDIR            = "theme"
M.WALLPAPER_SETTING = "theme_wallpaper_pack"
M.COLOURS_SETTING   = "theme_colours_pack"
M.PLANK_SETTING     = "theme_plank_pack"
M.SCAN_TTL          = 15
M._clock            = os.time

M.WALL_EXTS = { png = true, jpg = true, jpeg = true, webp = true, bmp = true, gif = true }
local VARIANT = { ["wallpaper"] = "base", ["wallpaper.full"] = "full",
                  ["wallpaper.dark"] = "dark", ["wallpaper.full.dark"] = "full_dark" }

-- The names a pack author writes in colours.json, and the settings they lend.
M.COLOUR_NAMES = {
    ["text"]                 = "ink_color",
    ["progress bar"]         = "progress_fill",
    ["progress track"]       = "progress_track",
    ["bookmark"]             = "bookmark_color",
    ["finished bookmark"]    = "complete_bookmark_color",
    ["favourite star"]       = "favorite_star_color",
    ["favourite heart"]      = "favorite_heart_color",
    ["badge text"]           = "badge_fg",
    ["badge background"]     = "badge_bg",
    ["menu bar"]             = "chrome_bg",
    ["module card"]          = "module_bg",
    ["module border"]        = "module_border",
    ["cover border"]         = "border_color",
    ["selection"]            = "selection_color",
    ["cover shadow"]         = "card_shadow_color",
    ["plank"]                = "spine_plank_color",
    ["folder label"]         = "folder_overlay_bg",
    ["folder text"]          = "folder_overlay_fg",
    ["selected shelf"]       = "chip_selected_bg",
    ["selected shelf text"]  = "chip_selected_fg",
    ["page"]                 = "wallpaper_bg",
}

-- Seams for the tests.
M._store, M._lfs, M._decode, M._orn = nil, nil, nil, nil

local function store()
    if M._store then return M._store end
    local ok, S = pcall(require, "lib/bookshelf_settings_store")
    return ok and S or nil
end
local function read(k) local s = store(); return s and s.read(k) or nil end
local function save(k, v)
    local s = store(); if not s then return end
    s.save(k, v); if s.flush then pcall(s.flush) end
end
local function fs() return M._lfs or require("libs/libkoreader-lfs") end
local function orn() return M._orn or require("lib/bookshelf_ornaments") end
local function decode(text)
    if M._decode then return M._decode(text) end
    return require("rapidjson").decode(text)
end

local function listDir(d)
    local out = {}
    local ok = pcall(function()
        for name in fs().dir(d) do
            if name:sub(1, 1) ~= "." and fs().attributes(d .. "/" .. name, "mode") == "file" then
                out[#out + 1] = name
            end
        end
    end)
    if not ok then return {} end
    table.sort(out)
    return out
end

local function parseColours(path, pack)
    local f = io.open(path, "rb"); if not f then return nil end
    local text = f:read("*a"); f:close()
    local ok, doc = pcall(decode, text)
    if not ok or type(doc) ~= "table" then
        logger.warn("[bookshelf] theme colours.json could not be read:", pack)
        return nil
    end
    local out, any = { day = {}, night = {} }, false
    for _i, look in ipairs({ "day", "night" }) do
        local set = doc[look]
        if type(set) == "table" then
            for name, hex in pairs(set) do
                local key = type(name) == "string" and M.COLOUR_NAMES[name:lower()]
                if key and type(hex) == "string" and hex:match("^#%x%x%x%x%x%x$") then
                    out[look][key] = hex:upper(); any = true
                else
                    logger.warn("[bookshelf] theme colour skipped:", pack, look, tostring(name), tostring(hex))
                end
            end
        end
    end
    return any and out or nil
end

-- theme(pack) -> what the pack's theme/ holds (fields nil when absent).
M._cache = {}
function M.theme(pack)
    local now = M._clock()
    local hit = M._cache[pack]
    if hit and M.SCAN_TTL > 0 and (now - hit.at) < M.SCAN_TTL then return hit.v end
    local d = orn().dir()
    local tdir = d and (d .. "/" .. pack .. "/" .. M.SUBDIR) or nil
    local v = { dir = tdir }
    if tdir and fs().attributes(tdir, "mode") == "directory" then
        local names = listDir(tdir)
        local w = {}
        local plank = {}
        for _i, n in ipairs(names) do
            local stem, ext = n:match("^(.-)%.([^%.]+)$")
            local lstem = stem and stem:lower()
            if lstem and M.WALL_EXTS[ext:lower()] and VARIANT[lstem] and not w[VARIANT[lstem]] then
                w[VARIANT[lstem]] = n
            elseif n:lower() == "plank.middle.png" then plank.middle = tdir .. "/" .. n
            elseif n:lower() == "plank.left.png" then plank.left = tdir .. "/" .. n
            elseif n:lower() == "plank.right.png" then plank.right = tdir .. "/" .. n
            elseif n:lower() == "colours.json" then v.colours = parseColours(tdir .. "/" .. n, pack)
            end
        end
        if w.base then v.wallpaper = w end
        if plank.middle then v.plank = plank end
    end
    M._cache[pack] = { at = now, v = v }
    return v
end

function M.invalidate() M._cache = {} end

-- wallpaperFile(w, is_full, is_dark) -> file name, and whether it is a dark
-- variant (shown as drawn: the reader's invert-at-night does not apply).
function M.wallpaperFile(w, is_full, is_dark)
    if not w then return nil end
    local order
    if is_full and is_dark then order = { "full_dark", "full", "dark", "base" }
    elseif is_full then order = { "full", "base" }
    elseif is_dark then order = { "dark", "base" }
    else order = { "base" } end
    for _i, k in ipairs(order) do
        if w[k] then return w[k], (k == "dark" or k == "full_dark") end
    end
    return nil
end

local function packExists(pack)
    local d = orn().dir()
    return d and fs().attributes(d .. "/" .. pack, "mode") == "directory"
end

-- A borrowed part whose pack or file has gone: clear the key, fall back.
local function activeFor(key, part)
    local pack = read(key)
    if type(pack) ~= "string" or pack == "" then return nil end
    if packExists(pack) and M.theme(pack)[part] then return pack end
    save(key, nil)
    return nil
end

function M.activeWallpaperPack() return activeFor(M.WALLPAPER_SETTING, "wallpaper") end
function M.setWallpaperPack(pack) save(M.WALLPAPER_SETTING, pack) end
function M.activeColoursPack() return activeFor(M.COLOURS_SETTING, "colours") end
function M.setColoursPack(pack) save(M.COLOURS_SETTING, pack) end

function M.plankItemName(pack) return pack .. "/" .. M.SUBDIR .. "/plank" end

-- activePlankPack() -> the one pack whose plank design shows, or nil. The
-- chosen one if it still qualifies, else the first (by name) that does: a
-- plank shows by default, like ornaments do, when its pack is on.
function M.activePlankPack()
    local O = orn()
    local _all, packs = O.listAll()
    local ok_list = {}
    for _i, p in ipairs(packs or {}) do
        if M.theme(p).plank and not O.isPackOff(p) and not O.isOff(M.plankItemName(p)) then
            ok_list[#ok_list + 1] = p
        end
    end
    local chosen = read(M.PLANK_SETTING)
    for _i, p in ipairs(ok_list) do if p == chosen then return p end end
    return ok_list[1]
end

function M.setPlankOn(pack, on)
    local O = orn()
    O.setOff(M.plankItemName(pack), not on)
    if on then save(M.PLANK_SETTING, pack)
    elseif read(M.PLANK_SETTING) == pack then save(M.PLANK_SETTING, nil) end
end

-- invertHex("#RRGGBB") -> its negative, same shape. What
-- bookshelf_color.invertValue does for a hex value; kept here because a pack
-- only ever lends "#RRGGBB" and this module must load without Blitbuffer.
function M.invertHex(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return hex end
    return string.format("#%02X%02X%02X", 255 - tonumber(r, 16),
                         255 - tonumber(g, 16), 255 - tonumber(b, 16))
end

-- colourOverride(key, dark) -> the borrowed colour for that setting in the
-- STORED convention of its slot, or nil. Night slots hold colours pre-inverted
-- for a frame that will flip (see bookshelf_color.invertValue); the plank is
-- the one exception, kept in display space in both.
function M.colourOverride(key, dark)
    local pack = M.activeColoursPack()
    if not pack then return nil end
    local c = M.theme(pack).colours
    local set = c and (dark and c.night or c.day)
    local hex = set and set[key]
    if not hex then return nil end
    if dark and key ~= "spine_plank_color" then hex = M.invertHex(hex) end
    return { hex = hex }
end

-- A borrowed wallpaper travels under a NAME, like every other wallpaper, so
-- Wallpaper.bg's cache and the widget's plumbing need no second path. The
-- prefix cannot collide with a file name (it carries a control character) and
-- Wallpaper.pathFor hands names carrying it to wallpaperPath.
M.NAME_PREFIX = "theme-pack\1"

function M.wallpaperName(is_full, is_dark)
    local pack = M.activeWallpaperPack()
    if not pack then return nil end
    local file = M.wallpaperFile(M.theme(pack).wallpaper, is_full, is_dark)
    return file and (M.NAME_PREFIX .. pack .. "\1" .. file) or nil
end

function M.wallpaperPath(rest)
    local pack, file = tostring(rest):match("^([^\1]+)\1([^\1]+)$")
    if not pack then return nil end
    for _i, part in ipairs({ pack, file }) do
        if part:find("/", 1, true) or part:find("\\", 1, true) or part == "." or part == ".." then
            return nil
        end
    end
    local th = M.theme(pack)
    local path = th.dir and (th.dir .. "/" .. file) or nil
    if path and fs().attributes(path, "mode") == "file" then return path end
    return nil
end

function M.isDarkName(name)
    if type(name) ~= "string" then return false end
    local file = name:match("\1([^\1]+)$")
    local stem = file and file:match("^(.-)%.[^%.]+$")
    stem = stem and stem:lower()
    return stem == "wallpaper.dark" or stem == "wallpaper.full.dark"
end

return M
