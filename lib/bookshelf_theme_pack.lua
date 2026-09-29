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
local ok_i, I18n = pcall(require, "lib/bookshelf_i18n")
local _ = (ok_i and I18n and I18n.gettext) or function(x) return x end
local ok_u, FUtil = pcall(require, "ffi/util")
local T = (ok_u and FUtil and FUtil.template) or function(f, ...)
    local args = { ... }
    return (f:gsub("%%(%d)", function(i) return tostring(args[tonumber(i)]) end))
end

local M = {}

M.SUBDIR            = "theme"
M.COLOURS_SETTING   = "theme_colours_pack"
M.PLANK_SETTING     = "theme_plank_pack"
-- The BUILT-IN wood plank (v5.3): "oak" (on), false (off), or unset. Shipped
-- in the plugin (assets/planks/oak), toggled from the plank colour dialog.
-- UNSET means the default: on, unless the reader has picked a plank colour of
-- their own (day or night), which they keep -- so an upgrade gives the oak to
-- everyone who never touched the plank, as a new install does (maintainer).
-- A pack's plank overrides it; switching pack planks off falls back to it,
-- and with it off the shelf has its coloured plank.
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
    -- Deferred with the ornaments while the browser is open (Orn.beginDeferred).
    local O = M._orn or package.loaded["lib/bookshelf_ornaments"]
    if O and O._defer and s.saveDeferred then s.saveDeferred(k, v) return end
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
    -- The pack's own folder, in whichever ornaments folder holds it (the
    -- new one first: Orn.packDir). A stub without packDir has one folder.
    local O = orn()
    local pdir = (O.packDir and O.packDir(pack))
                 or (O.dir() and (O.dir() .. "/" .. pack)) or nil
    local tdir = pdir and (pdir .. "/" .. M.SUBDIR) or nil
    -- exists: the pack folder is there, checked once per scan rather than on
    -- every colour read (a stat is dear on a Kindle's FUSE storage).
    local v = { dir = tdir, planks = {},
                exists = pdir and fs().attributes(pdir, "mode") == "directory" or false }
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
-- forgetChoice(): after a switch, work out which plank shows again, without
-- re-listing every pack's theme folder the way invalidate() does.
function M.forgetChoice() M._plank_memo = nil end

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
-- A pack that is switched off lends nothing, but keeps the key, so switching
-- it back on brings its part back; a pack (or part) that is gone clears it.
local function activeFor(key, part)
    local pack = read(key)
    if type(pack) ~= "string" or pack == "" then return nil end
    local th = M.theme(pack)
    if not (th.exists and th[part]) then save(key, nil); return nil end
    if orn().isPackOff(pack) then return nil end
    return pack
end

function M.activeColoursPack() return activeFor(M.COLOURS_SETTING, "colours") end
function M.setColoursPack(pack) save(M.COLOURS_SETTING, pack) end

-- colourThemes() -> the packs with a colours.json, for the Color theme row.
function M.colourThemes()
    local _all, packs = orn().listAll()
    local out = {}
    for _i, p in ipairs(packs or {}) do
        if M.theme(p).colours then out[#out + 1] = p end
    end
    return out
end

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
    if not M.designsOn() then return nil end
    return M.chosenPlank()
end

-- chosenPlank() -> the plank design the reader has chosen (a pack's, or the
-- built-in Oak), whether or not designs are switched on: what Performance
-- tweaks names.
function M.chosenPlank()
    local now = M._clock()
    local memo = M._plank_memo
    if memo and M.SCAN_TTL > 0 and (now - memo.at) < M.SCAN_TTL then return memo.v end
    local c = M.plankChoice()
    local v
    if c == "oak" then v = M.builtinPlank()
    elseif c ~= "colour" then v = M._packPlank(c) end
    M._plank_memo = { at = now, v = v }
    return v
end

-- Plank designs on or off (Settings > Advanced > Performance tweaks): a
-- design costs a black and white Kindle ~35ms on each spine-shelf tap (its
-- shadow is blended onto the screen), and Oak is on by default, so it gets a
-- switch there (maintainer). Off draws Bookshelf's own plank colour. It never
-- stops a reader choosing a plank: choosing one switches designs back on.
M.DESIGNS_OFF_SETTING = "plank_designs_off"
function M.designsOn() return read(M.DESIGNS_OFF_SETTING) ~= true end
function M.setDesignsOn(on)
    save(M.DESIGNS_OFF_SETTING, (not on) and true or nil)
    M._plank_memo = nil
end

-- The plank is ONE choice (theme_plank_pack): a pack plank's id, "oak", or
-- false for the plain colour. Unset: Oak on a fresh install, the reader's own
-- colour if they ever set one (plank_wood = false, or a plank colour), so an
-- upgrade never changes a shelf. A pack's plank is never chosen by installing
-- its pack: only by the plank picker or Apply pack theme (maintainer).

-- _packPlank(id) -> that pack plank, when its pack is on and it is there.
function M._packPlank(id)
    local O = orn()
    local _all, packs = O.listAll()
    for _i, p in ipairs(packs or {}) do
        if not O.isPackOff(p) then
            for _j, pl in ipairs(M.theme(p).planks or {}) do
                if pl.id == id then return pl end
            end
        end
    end
    return nil
end

local function fallbackChoice()
    local wood = read(M.WOOD_SETTING)
    if wood == "oak" then return "oak" end
    if wood == false then return "colour" end
    if read("spine_plank_color") ~= nil or read("spine_plank_color_night") ~= nil then
        return "colour"
    end
    return "oak"
end

-- plankChoice() -> "colour" | "oak" | a pack plank's id: what shows (a pack
-- plank whose pack is off or gone reads as the fallback, and comes back when
-- the pack is on again).
function M.plankChoice()
    local v = read(M.PLANK_SETTING)
    if v == false then return "colour" end
    if v == "oak" then return "oak" end
    if type(v) == "string" and M._packPlank(v) then return v end
    return fallbackChoice()
end

-- choosePlank(choice): the reader's pick. Choosing a design shows it, even
-- with designs off (Performance tweaks); choosing the colour does not touch
-- that switch.
function M.choosePlank(choice)
    -- Not `and false or choice`: false is falsy, so that saved the word.
    local v = choice
    if choice == "colour" then v = false end
    save(M.PLANK_SETTING, v)
    save(M.WOOD_SETTING, nil)          -- folded into the one choice
    if choice ~= "colour" and not M.designsOn() then M.setDesignsOn(true) end
    M._plank_memo = nil
end

-- plankRowLabel() -> what the Shelf plank row and Performance tweaks name:
-- "Oak", "Walnut (Planks pack)", or nil for the plain colour (the caller shows the
-- colour's value).
function M.plankRowLabel()
    local c = M.plankChoice()
    if c == "colour" then return nil end
    local p
    if c == "oak" then p = M.builtinPlank() else p = M._packPlank(c) end
    if not p then return nil end
    if p.pack and p.name then return T(_("%1 (%2 pack)"), p.name, p.pack) end
    return M.plankLabel(p)
end

-- plankOptions() -> the plank picker's entries, in order: the colour, Oak,
-- then each pack's planks (packs A-Z; a pack that is off is listed, marked).
function M.plankOptions()
    local O = orn()
    local out = { { kind = "colour" }, { kind = "oak", plank = M.builtinPlank() } }
    local _all, packs = O.listAll()
    local sorted = {}
    for _i, p in ipairs(packs or {}) do sorted[#sorted + 1] = p end
    table.sort(sorted)
    for _i, p in ipairs(sorted) do
        local pls = {}
        for _j, pl in ipairs(M.theme(p).planks or {}) do pls[#pls + 1] = pl end
        table.sort(pls, function(a, b) return (a.name or "") < (b.name or "") end)
        for _j, pl in ipairs(pls) do
            out[#out + 1] = { kind = "pack", pack = p, plank = pl, pack_off = O.isPackOff(p) or nil }
        end
    end
    return out
end

-- ── Apply pack theme ──────────────────────────────────────────────────────
-- One tap on a pack's tab uses what its theme/ has: its wallpaper as the
-- default wallpaper (full screen follows through "Same as default" unless the
-- reader set their own), its colour theme, its plank (a pack of several opens
-- the plank picker instead of guessing). It asks first, naming what will
-- change, and saves what it replaces, so the same button then undoes it
-- exactly: "I applied a theme and want my plank back" (maintainer).
--
-- The snapshot is taken once: applying a second pack keeps the ORIGINAL
-- values, so Undo returns to the reader's own look, not the first pack's.
M.APPLIED_SETTING = "theme_applied"
local SNAP = { plank = M.PLANK_SETTING, wood = M.WOOD_SETTING, wallpaper = "wallpaper_default",
               wallpaper_own = "wallpaper_default_own", colours = M.COLOURS_SETTING }
-- A saved nil, which a settings table cannot hold as a value.
local NIL_MARK = "\0nil"

function M.appliedPack()
    local s = read(M.APPLIED_SETTING)
    return type(s) == "table" and s.pack or nil
end

local function snapshot(pack)
    local s = read(M.APPLIED_SETTING)
    if type(s) ~= "table" or type(s.values) ~= "table" then
        s = { values = {} }
        for k, key in pairs(SNAP) do
            local v = read(key)
            if v == nil then v = NIL_MARK end
            s.values[k] = v
        end
    end
    s.pack = pack
    save(M.APPLIED_SETTING, s)
end

-- undoPackTheme(): every saved value back as it was, unset ones unset.
function M.undoPackTheme()
    local s = read(M.APPLIED_SETTING)
    if type(s) ~= "table" then return end
    for k, key in pairs(SNAP) do
        local v = s.values and s.values[k]
        if v == NIL_MARK then v = nil end
        save(key, v)
    end
    save(M.APPLIED_SETTING, nil)
    M._plank_memo = nil
end

-- applySummary(pack) -> the confirmation's text: what applying will change.
function M.applySummary(pack)
    local th, parts = M.theme(pack), {}
    if th.wallpaper then parts[#parts + 1] = _("wallpaper") end
    local planks = th.planks or {}
    if #planks == 1 then parts[#parts + 1] = T(_("%1 plank"), planks[1].name or pack)
    elseif #planks > 1 then parts[#parts + 1] = _("a plank you choose") end
    if th.colours then parts[#parts + 1] = _("colors") end
    local list = parts[#parts] or ""
    if #parts > 1 then
        list = T(_("%1 and %2"), table.concat(parts, ", ", 1, #parts - 1), parts[#parts])
    end
    return T(_("Uses %1's %2. Undo pack theme on this tab puts yours back."), pack, list)
end

-- applyPackTheme(pack) -> { wallpaper, colours, plank, pick_plank }: what it
-- did (pick_plank: the pack has several planks, the caller opens the picker).
function M.applyPackTheme(pack)
    snapshot(pack)
    orn().setPackOff(pack, false)
    local th = M.theme(pack)
    local r = { wallpaper = false, colours = false, plank = false, pick_plank = false }
    if th.wallpaper then
        for _i, e in ipairs(M.wallpaperEntries()) do
            if e.pack == pack then M.chooseWallpaper("wallpaper_default", e.name); r.wallpaper = true end
        end
    end
    if th.colours then M.setColoursPack(pack); r.colours = true end
    local planks = th.planks or {}
    if #planks == 1 then M.choosePlank(planks[1].id); r.plank = true
    elseif #planks > 1 then r.pick_plank = true end
    M._plank_memo = nil
    return r
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

function M.isPackName(name)
    return type(name) == "string" and name:sub(1, #M.NAME_PREFIX) == M.NAME_PREFIX
end

-- wallpaperEntries() -> every pack's wallpaper as a choice for the wallpaper
-- picker ({name, label, pack, path}; a pack that is off is listed, marked).
-- The name is the base file's: the view's variant is picked at paint time.
function M.wallpaperEntries()
    local O = orn()
    local _all, packs = O.listAll()
    local out = {}
    for _i, p in ipairs(packs or {}) do
        local th = M.theme(p)
        local file = th.wallpaper and th.wallpaper.base
        if file then
            out[#out + 1] = { name = M.NAME_PREFIX .. p .. "\1" .. file, label = p, pack = p,
                              path = th.dir .. "/" .. file, pack_off = O.isPackOff(p) or nil }
        end
    end
    return out
end

-- variantName(name, is_full, is_dark) -> for a pack wallpaper's name, that
-- pack's wallpaper for this view (full screen, dark), or nil when its pack is
-- off or gone; any other name is returned as it is.
function M.variantName(name, is_full, is_dark)
    if not M.isPackName(name) then return name end
    local pack = name:sub(#M.NAME_PREFIX + 1):match("^([^\1]+)\1")
    local th = pack and M.theme(pack)
    if not (th and th.exists and th.wallpaper) or orn().isPackOff(pack) then return nil end
    local file = M.wallpaperFile(th.wallpaper, is_full, is_dark)
    return file and (M.NAME_PREFIX .. pack .. "\1" .. file) or nil
end

-- chooseWallpaper(key, name): store a wallpaper choice (wallpaper_default or
-- wallpaper_full). A pack's replacing the reader's own remembers theirs in
-- <key>_own, which the shelf shows again if the pack goes or is switched off;
-- choosing one of their own forgets it.
function M.chooseWallpaper(key, name)
    local cur = read(key)
    if M.isPackName(name) then
        if cur ~= nil and not M.isPackName(cur) then save(key .. "_own", cur) end
    else
        save(key .. "_own", nil)
    end
    save(key, name)
end

-- migrate(): the 5.3 betas "lent" a pack's wallpaper over the reader's own
-- (theme_wallpaper_pack); it is now an ordinary choice. Moved once.
function M.migrate()
    local pack = read("theme_wallpaper_pack")
    if type(pack) ~= "string" then return end
    for _i, e in ipairs(M.wallpaperEntries()) do
        if e.pack == pack then M.chooseWallpaper("wallpaper_default", e.name) end
    end
    save("theme_wallpaper_pack", nil)
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
