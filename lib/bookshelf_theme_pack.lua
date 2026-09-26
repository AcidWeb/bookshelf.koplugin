-- bookshelf_theme_pack.lua
-- Theme packs: an ornament pack's theme/ subfolder, and which pack's parts are
-- BORROWED right now.
--
--   <pack>/theme/wallpaper.<ext>            + .full / .dark / .full.dark variants
--   <pack>/theme/plank.middle.png           + plank.left.png / plank.right.png
--   <pack>/theme/plank.<name>.middle.png    a NAMED plank (+ .left / .right):
--                                           a pack may hold several, e.g. a
--                                           pack of wood shelves
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
-- The BUILT-IN wood plank (v5.3): "oak" or false/nil. Shipped in the plugin
-- (assets/planks/oak), toggled from the plank colour dialog, seeded on for
-- new installs (Fonts.maybeSeedFreshInstall). A pack's plank overrides it;
-- switching pack planks off falls back to it, and with it off the shelf has
-- its coloured plank as before.
M.WOOD_SETTING      = "plank_wood"
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
local function read(k)
    local s = store()
    if not s then return nil end
    return s.read(k)            -- false survives: theme_plank_pack = false is "none"
end
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

-- _plankPart(file) -> name, part for "plank[.<name>].<middle|left|right>.png"
-- (name "" for the unnamed plank), or nil.
function M._plankPart(file)
    local stem = file:match("^(.+)%.[Pp][Nn][Gg]$")
    if not stem or stem:sub(1, 6):lower() ~= "plank." then return nil end
    local rest = stem:sub(7)
    local name, part = rest:match("^(.*)%.([^%.]+)$")
    if not name then name, part = "", rest end
    part = part:lower()
    if part ~= "middle" and part ~= "left" and part ~= "right" then return nil end
    return name, part
end

-- theme(pack) -> what the pack's theme/ holds (fields nil when absent).
M._cache = {}
function M.theme(pack)
    local now = M._clock()
    local hit = M._cache[pack]
    if hit and M.SCAN_TTL > 0 and (now - hit.at) < M.SCAN_TTL then return hit.v end
    local d = orn().dir()
    local tdir = d and (d .. "/" .. pack .. "/" .. M.SUBDIR) or nil
    -- exists: the pack folder is there, checked once per scan rather than on
    -- every colour read (a stat is dear on a Kindle's FUSE storage).
    local v = { dir = tdir, planks = {},
                exists = d and fs().attributes(d .. "/" .. pack, "mode") == "directory" or false }
    if tdir and fs().attributes(tdir, "mode") == "directory" then
        local names = listDir(tdir)
        local w = {}
        local planks = {}          -- by name ("" = the unnamed plank)
        for _i, n in ipairs(names) do
            local stem, ext = n:match("^(.-)%.([^%.]+)$")
            local lstem = stem and stem:lower()
            if lstem and M.WALL_EXTS[ext:lower()] and VARIANT[lstem] and not w[VARIANT[lstem]] then
                w[VARIANT[lstem]] = n
            elseif M._plankPart(n) then
                local name, part = M._plankPart(n)
                planks[name] = planks[name] or {}
                planks[name][part] = tdir .. "/" .. n
            elseif n:lower() == "colours.json" then v.colours = parseColours(tdir .. "/" .. n, pack)
            end
        end
        if w.base then v.wallpaper = w end
        v.planks = {}
        for name, pl in pairs(planks) do
            if pl.middle then
                pl.pack = pack
                pl.name = name ~= "" and name or nil
                pl.id = pack .. "/" .. M.SUBDIR .. "/plank" .. (pl.name and ("." .. name) or "")
                v.planks[#v.planks + 1] = pl
            end
        end
        table.sort(v.planks, function(a, b)
            if (a.name == nil) ~= (b.name == nil) then return a.name == nil end
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
    end
    M._cache[pack] = { at = now, v = v }
    return v
end

function M.invalidate() M._cache = {}; M._plank_memo = nil end

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

-- A borrowed part whose pack or file has gone: clear the key, fall back.
local function activeFor(key, part)
    local pack = read(key)
    if type(pack) ~= "string" or pack == "" then return nil end
    local th = M.theme(pack)
    if th.exists and th[part] then return pack end
    save(key, nil)
    return nil
end

function M.activeWallpaperPack() return activeFor(M.WALLPAPER_SETTING, "wallpaper") end
function M.setWallpaperPack(pack) save(M.WALLPAPER_SETTING, pack) end
function M.activeColoursPack() return activeFor(M.COLOURS_SETTING, "colours") end
function M.setColoursPack(pack) save(M.COLOURS_SETTING, pack) end

-- The plugin's root (one level up from lib/), for the built-in plank's files;
-- the idiom Wallpaper.seedSource uses. A seam for the tests.
M._plugin_root = nil
local function pluginRoot()
    if M._plugin_root then return M._plugin_root end
    local src = debug.getinfo(1, "S").source or ""
    local dir = src:match("^@(.*)/lib/[^/]*$")
    return dir or "."
end

-- builtinPlank() -> the shipped Oak plank's record, or nil if its files are
-- missing (a source checkout that lost them).
function M.builtinPlank()
    local d = pluginRoot() .. "/assets/planks/oak"
    local function f(part)
        local path = d .. "/plank." .. part .. ".png"
        return fs().attributes(path, "mode") == "file" and path or nil
    end
    local middle = f("middle")
    if not middle then return nil end
    return { id = "builtin:oak", name = "Oak", builtin = true,
             middle = middle, left = f("left"), right = f("right") }
end

function M.woodOn() return read(M.WOOD_SETTING) == "oak" end
function M.setWood(on)
    save(M.WOOD_SETTING, on and "oak" or false)
    M._plank_memo = nil
end

-- plankLabel(p) -> what menus call a plank: its name, or its pack's.
function M.plankLabel(p) return p and (p.name or p.pack) or nil end

-- activePlank() -> the plank design on show ({id, pack, name, middle, left,
-- right}; the built-in Oak has builtin = true and no pack), or nil for the
-- coloured plank. A pack's plank first, then the built-in wood if it is on. The chosen one if it still qualifies, else the first there
-- is: a plank shows by default, like ornaments do, when its pack is on.
--
-- Cached for the scan TTL: it is asked on every shelf build, a page turn bumps
-- the settings generation, and answering means listing the ornaments folder.
-- A switch (setPlankOn, invalidate) drops the answer at once.
--
-- theme_plank_pack = false means "none": switching the SHOWN plank off must
-- not hand the shelf to the next plank that happens to be on too. Otherwise it
-- holds the chosen plank's id.
M._plank_memo = nil
function M.activePlank()
    local now = M._clock()
    local memo = M._plank_memo
    if memo and M.SCAN_TTL > 0 and (now - memo.at) < M.SCAN_TTL then return memo.v end
    local v = M._activePlank() or (M.woodOn() and M.builtinPlank()) or nil
    M._plank_memo = { at = now, v = v }
    return v
end

function M._activePlank()
    local O = orn()
    local _all, packs = O.listAll()
    local ok_list = {}
    for _i, p in ipairs(packs or {}) do
        if not O.isPackOff(p) then
            for _j, pl in ipairs(M.theme(p).planks or {}) do
                if not O.isOff(pl.id) then ok_list[#ok_list + 1] = pl end
            end
        end
    end
    local chosen = read(M.PLANK_SETTING)
    if chosen == false then return nil end
    for _i, pl in ipairs(ok_list) do if pl.id == chosen then return pl end end
    return ok_list[1]
end

-- setPlankOn(id, on): switch one plank design; switching one on makes it the
-- one shown.
function M.setPlankOn(id, on)
    local O = orn()
    local cur = M._activePlank()
    O.setOff(id, not on)
    if on then
        save(M.PLANK_SETTING, id)
    elseif cur and cur.id == id then
        save(M.PLANK_SETTING, false)        -- none, not the next in line
    end
    M._plank_memo = nil
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

-- plankEntries(pack) -> ornament-shaped entries for the pack's plank designs,
-- so the browser shows and switches them like ornaments. Previewed from each
-- middle image; never placed on a shelf by the ornament picker (is_plank).
function M.plankEntries(pack)
    local out = {}
    for _i, p in ipairs(M.theme(pack).planks or {}) do
        local f = io.open(p.middle, "rb")
        local head = f and f:read(64)
        if f then f:close() end
        local aspect = head and require("lib/bookshelf_ornaments").parsePngHeader(head)
        if aspect then
            out[#out + 1] = { path = p.middle, name = p.id, file = p.name or "Plank",
                              pack = pack, aspect = aspect, overhang = 0,
                              is_plank = true, plank = p }
        end
    end
    return out
end

-- withOverride(items, label, on_deactivate, keep) -> the menu with, while a
-- part is borrowed (label non-nil), a first row saying so; tapping it turns
-- the part off, removes itself and brings the greyed rows back. keep[i]: rows
-- that stay live (the day/night editing switch, the shelf theme); a row with
-- _theme_keep stays live too (another borrowed part's own override row).
function M.withOverride(items, label, on_deactivate, keep)
    if not label then return items end
    local active = true
    local out = {}
    local line = { text = label, keep_menu_open = true, separator = true }
    out[1] = line
    for i, it in ipairs(items) do
        if not ((keep and keep[i]) or it._theme_keep) then
            local was = it.enabled_func
            it.enabled_func = function()
                if active then return false end
                return was == nil or was()
            end
        end
        out[#out + 1] = it
    end
    line.callback = function(touchmenu_instance)
        active = false
        on_deactivate()
        local tbl = touchmenu_instance and touchmenu_instance.item_table
        if tbl and tbl[1] == line then table.remove(tbl, 1) end
        if touchmenu_instance and touchmenu_instance.updateItems then touchmenu_instance:updateItems() end
    end
    return out
end

return M
