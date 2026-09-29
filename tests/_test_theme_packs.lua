-- tests/_test_theme_packs.lua
-- Theme packs: the theme/ subfolder of an ornament pack (wallpaper variants,
-- plank design, colours.json) and the "which pack is borrowed" state.
-- Run from the plugin root: lua tests/_test_theme_packs.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg = function() end, info = function() end,
                             warn = function() end, err = function() end }

local function sh(cmd)
    local f = io.popen(cmd .. " 2>/dev/null"); local out = f:read("*a"); f:close(); return out
end
local lfs_shim = {
    attributes = function(path, attr)
        local q = "'" .. path .. "'"
        if attr == "mode" then
            if sh("test -d " .. q .. " && echo d"):match("d") then return "directory" end
            if sh("test -e " .. q .. " && echo f"):match("f") then return "file" end
            return nil
        elseif attr == "modification" then return tonumber(sh("stat -c %Y " .. q)) end
        return nil
    end,
    dir = function(path)
        local list = {}
        for name in sh("ls -a '" .. path .. "'"):gmatch("[^\n]+") do list[#list + 1] = name end
        local i = 0
        return function() i = i + 1; return list[i] end
    end,
}

local t  = dofile("tests/_helpers.lua").runner()
local eq = dofile("tests/_helpers.lua").eq

-- A tiny JSON decoder for the tests only (the module uses rapidjson on the
-- device): objects of objects of strings, which is all colours.json holds.
local function tiny_json(s)
    local f, err = load("return " .. s:gsub('"([^"]-)"%s*:', '["%1"]='))
    if not f then error(err) end
    return f()
end

local tmp = os.getenv("TMPDIR") or "/tmp"
local function scratch()
    local d = string.format("%s/bookshelf_theme_test_%d_%d", tmp, os.time(), math.random(1e6))
    os.execute("rm -rf '" .. d .. "' && mkdir -p '" .. d .. "'")
    return d
end
local function touch(p, body)
    os.execute("mkdir -p \"$(dirname '" .. p .. "')\"")
    local f = io.open(p, "wb"); f:write(body or "x"); f:close()
end

-- Fake ornaments module + store, so the suite needs neither KOReader nor
-- the real ornaments scan.
local function setup()
    local d = scratch()
    local settings = {}
    local off, packs_off = {}, {}
    local orn = {
        dir = function() return d end,
        listAll = function()
            local packs = {}
            for name in sh("ls '" .. d .. "'"):gmatch("[^\n]+") do
                if lfs_shim.attributes(d .. "/" .. name, "mode") == "directory" then
                    packs[#packs + 1] = name
                end
            end
            table.sort(packs)
            return {}, packs
        end,
        isPackOff = function(p) return packs_off[p] == true end,
        isOff = function(r) return off[r] == true end,
        setPackOff = function(p, v) packs_off[p] = v and true or nil end,
        setOff = function(r, v) off[r] = v and true or nil end,
    }
    package.loaded["lib/bookshelf_theme_pack"] = nil
    local TP = dofile("lib/bookshelf_theme_pack.lua")
    TP._lfs = lfs_shim
    TP._orn = orn
    TP._decode = tiny_json
    TP._store = { read = function(k) return settings[k] end,
                  save = function(k, v) settings[k] = v end,
                  flush = function() end }
    TP.SCAN_TTL = 0
    return TP, d, settings, packs_off, off
end

t.test("a pack without theme/ has no parts", function()
    local TP, d = setup()
    touch(d .. "/Autumn/Owl.png")
    local th = TP.theme("Autumn")
    eq(th.wallpaper, nil); eq(th.plank, nil); eq(th.colours, nil)
end)

t.test("wallpaper variants are found and chosen per view and look", function()
    local TP, d = setup()
    for _, f in ipairs({ "wallpaper.jpg", "wallpaper.full.png", "wallpaper.dark.jpg", "other.png" }) do
        touch(d .. "/Xmas/theme/" .. f)
    end
    local w = TP.theme("Xmas").wallpaper
    eq(w.base, "wallpaper.jpg"); eq(w.full, "wallpaper.full.png"); eq(w.dark, "wallpaper.dark.jpg")
    eq(w.full_dark, nil)
    eq(TP.wallpaperFile(w, false, false), "wallpaper.jpg")
    local f, dv = TP.wallpaperFile(w, false, true); eq(f, "wallpaper.dark.jpg"); eq(dv, true)
    eq(TP.wallpaperFile(w, true, false), "wallpaper.full.png")
    f, dv = TP.wallpaperFile(w, true, true)
    eq(f, "wallpaper.full.png", "full screen + dark: full.dark missing, full wins over dark")
    eq(dv, false)
end)

t.test("a wallpaper variant without the base file is no wallpaper", function()
    local TP, d = setup()
    touch(d .. "/Xmas/theme/wallpaper.dark.jpg")
    eq(TP.theme("Xmas").wallpaper, nil)
end)

t.test("plank files: middle required, ends optional", function()
    local TP, d = setup()
    touch(d .. "/A/theme/plank.left.png")
    eq(#TP.theme("A").planks, 0, "no middle, no plank")
    touch(d .. "/B/theme/plank.middle.png"); touch(d .. "/B/theme/plank.right.png")
    local p = TP.theme("B").planks[1]
    assert(p.middle:match("/B/theme/plank%.middle%.png$")); eq(p.left, nil)
    assert(p.right:match("plank%.right%.png$"))
    eq(p.id, "B/theme/plank"); eq(p.name, nil); eq(p.pack, "B")
end)

t.test("a pack of planks: each named plank is its own design", function()
    local TP, d = setup()
    for _, f in ipairs({ "plank.Dark Oak.middle.png", "plank.Dark Oak.left.png",
                         "plank.birch.middle.png", "plank.middle.png", "plank.ash.left.png" }) do
        touch(d .. "/Woods/theme/" .. f)
    end
    local ps = TP.theme("Woods").planks
    eq(#ps, 3, "unnamed, birch, Dark Oak; ash has no middle")
    eq(ps[1].name, nil); eq(ps[2].name, "birch"); eq(ps[3].name, "Dark Oak")
    eq(ps[3].id, "Woods/theme/plank.Dark Oak")
    assert(ps[3].left:match("plank%.Dark Oak%.left%.png$")); eq(ps[2].left, nil)
    eq(TP.plankLabel(ps[3]), "Dark Oak"); eq(TP.plankLabel(ps[1]), "Woods")
end)

t.test("colours.json maps friendly names to settings", function()
    local TP, d = setup()
    touch(d .. "/Xmas/theme/colours.json",
        '{"day": {"plank": "#8A5A3C", "selected shelf": "#B22222"}, "night": {"text": "#EEEEEE"}}')
    local c = TP.theme("Xmas").colours
    eq(c.day.spine_plank_color, "#8A5A3C"); eq(c.day.chip_selected_bg, "#B22222")
    eq(c.night.ink_color, "#EEEEEE")
end)

t.test("bad colours.json: good entries apply, bad ones are skipped", function()
    local TP, d = setup()
    touch(d .. "/A/theme/colours.json", '{"day": {"plank": "#12", "sparkles": "#FFFFFF", "text": "#000000"}}')
    local c = TP.theme("A").colours
    eq(c.day.ink_color, "#000000"); eq(c.day.spine_plank_color, nil)
    touch(d .. "/B/theme/colours.json", "{ not json")
    eq(TP.theme("B").colours, nil, "unparseable file: no colour theme, no error")
end)


t.test("stale pack falls back and the setting is cleared", function()
    local TP, d, settings = setup()
    touch(d .. "/A/theme/wallpaper.png")
    touch(d .. "/A/theme/colours.json", '{"day": {"text": "#101010"}}')
    TP.setColoursPack("A")
    local name = TP.wallpaperEntries()[1].name
    os.execute("rm -rf '" .. d .. "/A'")
    TP.invalidate()
    eq(TP.variantName(name, false, false), nil, "a gone pack's wallpaper names nothing")
    eq(TP.activeColoursPack(), nil); eq(TP.colourOverride("ink_color", false), nil)
    eq(settings[TP.COLOURS_SETTING], nil)
end)

t.test("colour override: day as written, night pre-inverted, plank never", function()
    local TP, d = setup()
    touch(d .. "/A/theme/colours.json",
        '{"day": {"text": "#101010"}, "night": {"text": "#F0F0F0", "plank": "#806040"}}')
    TP.setColoursPack("A")
    eq(TP.colourOverride("ink_color", false).hex, "#101010")
    eq(TP.colourOverride("ink_color", true).hex:upper(), "#0F0F0F", "night slot is stored pre-inverted")
    eq(TP.colourOverride("spine_plank_color", true).hex, "#806040", "plank is display space")
    eq(TP.colourOverride("badge_bg", false), nil, "a colour the pack does not set")
    TP.setColoursPack(nil)
    eq(TP.colourOverride("ink_color", false), nil)
end)




t.test("every colour read consults the borrowed theme; the menu reads the reader's own", function()
    local cp = io.open("lib/bookshelf_cover_progress.lua"):read("*a")
    assert(cp:find("local function _readOwnColor", 1, true), "no _readOwnColor")
    assert(cp:find("TP.colourOverride, base_key", 1, true), "_readModeColor does not ask the theme")
    local raw = cp:match("function M%.rawColors%(%).-\nend")
    assert(raw and not raw:find("_readModeColor(", 1, true), "rawColors must read the reader's OWN colours")
    local cb = io.open("lib/bookshelf_chip_bar.lua"):read("*a")
    assert(cb:find("TP.colourOverride, base_key", 1, true), "selected chip colours ignore the theme")
    local w = io.open("lib/bookshelf_widget.lua"):read("*a")
    local pg = w:match("function BookshelfWidget:_pageGroundColor%(%).-\nend")
    assert(pg and pg:find("colourOverride(", 1, true), "page ground ignores the theme")
end)

t.test("borrowed colours cost no file checks per read within the scan TTL", function()
    local TP, d = setup()
    touch(d .. "/A/theme/colours.json", '{"day": {"text": "#101010"}}')
    TP.setColoursPack("A")
    TP.SCAN_TTL = 15; TP._clock = function() return 5 end
    TP.colourOverride("ink_color", false)
    local stats = 0
    local real = TP._lfs.attributes
    TP._lfs.attributes = function(...) stats = stats + 1; return real(...) end
    for _i = 1, 20 do TP.colourOverride("ink_color", false) end
    TP._lfs.attributes = real
    eq(stats, 0, "twenty colour reads, no stat calls")
end)


t.test("the browser: a tap redraws only itself; the shelf and a full repaint wait for close", function()
    local b = io.open("lib/bookshelf_ornament_browser.lua"):read("*a")
    local changed = b:match("function Browser:_changed%(.-\nend")
    assert(changed and changed:find("forgetChoice", 1, true),
        "a switch must drop the cached plank choice")
    assert(not changed:find("on_change", 1, true), "every tap still rebuilds the shelf behind")
    assert(changed:find("if rescan then", 1, true), "every tap still rescans the ornament folders")
    local toggle = b:match("function Browser:_toggle%(item%).-\nend")
    assert(toggle and not toggle:find('setDirty("all", "full")', 1, true),
        "a tap still flashes the whole screen")
    local closed = b:match("local function closed%(%).-\n    end")
    assert(closed and closed:find("endDeferred", 1, true) and closed:find("on_change", 1, true)
        and closed:find('setDirty("all", "full")', 1, true),
        "closing must flush, rebuild the shelf once, and repaint fully when the plank or wallpaper changed")
    local pb = io.open("lib/bookshelf_plank_browser.lua"):read("*a")
    local tap = pb:match("on_cell_tap = function%(o%).-\n        end,")
    assert(tap and tap:find('setDirty("all", "full")', 1, true),
        "the plank picker's choice must repaint fully too")
end)




t.test("plankRowLabel: Oak, a pack plank with its pack, nil for the colour", function()
    local TP, d = setup()
    TP._plugin_root = "."
    touch(d .. "/Planks/theme/plank.Walnut.middle.png")
    TP.invalidate()
    TP.choosePlank("oak"); eq(TP.plankRowLabel(), "Oak")
    TP.choosePlank("Planks/theme/plank.Walnut"); eq(TP.plankRowLabel(), "Walnut (Planks pack)")
    TP.choosePlank("colour"); eq(TP.plankRowLabel(), nil)
end)

-- ── The plank: one choice (theme_plank_pack) ─────────────────────────────
t.test("plank choice: a fresh install is Oak; an own plank colour stays a colour", function()
    local TP, _d, settings = setup()
    TP._plugin_root = "."
    eq(TP.plankChoice(), "oak")
    assert(TP.activePlank().builtin, "Oak is not what shows")
    settings["spine_plank_color"] = { hex = "#806040" }
    TP.forgetChoice()
    eq(TP.plankChoice(), "colour", "an upgrader's own plank colour was replaced")
    settings["spine_plank_color"] = nil; settings["spine_plank_color_night"] = { grey = 90 }
    eq(TP.plankChoice(), "colour", "so was a night one")
    settings["spine_plank_color_night"] = nil; settings[TP.WOOD_SETTING] = false
    eq(TP.plankChoice(), "colour", "an Oak switched off before stays off")
end)

t.test("plank choice: installing a pack's plank does not switch it on", function()
    local TP, d = setup()
    TP._plugin_root = "."
    touch(d .. "/Planks/theme/plank.Walnut.middle.png")
    TP.invalidate()
    eq(TP.plankChoice(), "oak")
    assert(TP.activePlank().builtin)
end)

t.test("choosePlank: a pack plank, Oak or the colour; a design choice switches designs on", function()
    local TP, d, settings = setup()
    TP._plugin_root = "."
    touch(d .. "/Planks/theme/plank.Walnut.middle.png")
    TP.invalidate()
    TP.setDesignsOn(false)
    TP.choosePlank("Planks/theme/plank.Walnut")
    eq(TP.plankChoice(), "Planks/theme/plank.Walnut")
    eq(TP.designsOn(), true)
    eq(TP.activePlank().name, "Walnut")
    TP.setDesignsOn(false)
    eq(TP.activePlank(), nil, "designs off: none drawn")
    eq(TP.chosenPlank().name, "Walnut", "but the menu still knows which is chosen")
    TP.choosePlank("colour")
    eq(TP.designsOn(), false, "choosing the colour is not a choice of design")
    TP.setDesignsOn(true)
    eq(TP.activePlank(), nil)
    TP.choosePlank("oak")
    assert(TP.activePlank().builtin)
    eq(settings[TP.WOOD_SETTING], nil, "plank_wood is folded into the one choice")
end)

t.test("a chosen plank's pack switched off falls back, and comes back when it is on", function()
    local TP, d, _s, packs_off = setup()
    TP._plugin_root = "."
    touch(d .. "/Planks/theme/plank.Walnut.middle.png")
    TP.invalidate()
    TP.choosePlank("Planks/theme/plank.Walnut")
    packs_off["Planks"] = true
    TP.forgetChoice()
    eq(TP.plankChoice(), "oak")
    packs_off["Planks"] = nil
    TP.forgetChoice()
    eq(TP.plankChoice(), "Planks/theme/plank.Walnut")
end)

t.test("plankOptions: the colour, Oak, then each pack's planks by pack", function()
    local TP, d, _s, packs_off = setup()
    TP._plugin_root = "."
    touch(d .. "/Planks/theme/plank.Walnut.middle.png"); touch(d .. "/Planks/theme/plank.Ash.middle.png")
    touch(d .. "/Japan/theme/plank.Gallery.middle.png")
    packs_off["Planks"] = true
    TP.invalidate()
    local o = TP.plankOptions()
    eq(o[1].kind, "colour"); eq(o[2].kind, "oak")
    eq(o[3].pack, "Japan"); eq(o[4].plank.name, "Ash"); eq(o[5].plank.name, "Walnut")
    eq(o[4].pack_off, true, "a pack that is off is still listed, marked")
end)

t.test("activePlank is cached for the scan TTL; a choice is seen at once", function()
    local TP, d = setup()
    TP._plugin_root = "."
    touch(d .. "/A/theme/plank.middle.png")
    local now, calls = 0, 0
    TP._clock = function() return now end
    TP.SCAN_TTL = 15
    local real = TP.theme
    TP.theme = function(p) calls = calls + 1; return real(p) end
    TP.choosePlank("A/theme/plank")
    eq(TP.activePlank().pack, "A"); eq(TP.activePlank().pack, "A")
    TP.choosePlank("colour"); eq(TP.activePlank(), nil, "a choice is seen at once")
    TP.choosePlank("A/theme/plank"); eq(TP.activePlank().pack, "A")
    now = now + 16; TP.activePlank(); eq(calls >= 2, true, "and it expires")
end)

t.test("a pack that is off lends no colour theme; switched on it does again", function()
    local TP, d, _s, packs_off = setup()
    touch(d .. "/Japan/theme/colours.json", '{"day":{"text":"#112233"},"night":{}}')
    TP.invalidate()
    TP.setColoursPack("Japan")
    packs_off["Japan"] = true
    eq(TP.activeColoursPack(), nil)
    packs_off["Japan"] = nil
    eq(TP.activeColoursPack(), "Japan")
    eq(TP.colourThemes()[1], "Japan")
end)


-- ── A pack's wallpaper is an ordinary choice ──────────────────────────────
t.test("pack wallpapers are listed as ordinary choices, off packs marked", function()
    local TP, d, _s, packs_off = setup()
    touch(d .. "/Japan/theme/wallpaper.png"); touch(d .. "/Autumn/Owl.png")
    packs_off["Japan"] = true
    local e = TP.wallpaperEntries()
    eq(#e, 1); eq(e[1].pack, "Japan"); eq(e[1].pack_off, true)
    eq(TP.isPackName(e[1].name), true); eq(TP.isPackName("leaves.png"), false)
    eq(e[1].path, d .. "/Japan/theme/wallpaper.png")
end)

t.test("a pack wallpaper name resolves to its view's variant, and to nothing when its pack is off", function()
    local TP, d, _s, packs_off = setup()
    for _, f in ipairs({ "wallpaper.png", "wallpaper.full.png", "wallpaper.dark.png" }) do
        touch(d .. "/Xmas/theme/" .. f)
    end
    local base = TP.wallpaperEntries()[1].name
    eq(TP.variantName(base, false, false), base)
    eq(TP.variantName(base, true, false), TP.NAME_PREFIX .. "Xmas\1wallpaper.full.png")
    local dark = TP.variantName(base, false, true)
    eq(dark, TP.NAME_PREFIX .. "Xmas\1wallpaper.dark.png"); eq(TP.isDarkName(dark), true)
    eq(TP.wallpaperPath("Xmas\1wallpaper.png"), d .. "/Xmas/theme/wallpaper.png")
    eq(TP.wallpaperPath("Xmas\1../../etc/passwd"), nil, "no path escapes")
    eq(TP.wallpaperPath("..\1wallpaper.png"), nil)
    eq(TP.wallpaperPath("Xmas\1missing.png"), nil)
    packs_off["Xmas"] = true
    eq(TP.variantName(base, false, false), nil)
    eq(TP.variantName("my.png", false, false), "my.png", "a reader's own name passes through")
end)

t.test("choosing a pack wallpaper remembers the reader's own; choosing their own forgets it", function()
    local TP, d, settings = setup()
    touch(d .. "/Japan/theme/wallpaper.png")
    settings["wallpaper_default"] = "leaves.png"
    local base = TP.wallpaperEntries()[1].name
    TP.chooseWallpaper("wallpaper_default", base)
    eq(settings["wallpaper_default"], base); eq(settings["wallpaper_default_own"], "leaves.png")
    TP.chooseWallpaper("wallpaper_default", base)
    eq(settings["wallpaper_default_own"], "leaves.png", "choosing it again keeps the own one")
    TP.chooseWallpaper("wallpaper_default", "sky.png")
    eq(settings["wallpaper_default"], "sky.png"); eq(settings["wallpaper_default_own"], nil)
end)

t.test("migrate: a borrowed wallpaper becomes the default choice, once", function()
    local TP, d, settings = setup()
    touch(d .. "/Japan/theme/wallpaper.png")
    settings["wallpaper_default"] = "leaves.png"
    settings["theme_wallpaper_pack"] = "Japan"
    TP.migrate()
    eq(TP.isPackName(settings["wallpaper_default"]), true)
    eq(settings["wallpaper_default_own"], "leaves.png")
    eq(settings["theme_wallpaper_pack"], nil)
    TP.migrate()
    eq(settings["wallpaper_default_own"], "leaves.png", "a second run changes nothing")
end)

t.test("the shelf maps a pack wallpaper to its variant and falls back to the reader's own", function()
    local w = io.open("lib/bookshelf_widget.lua"):read("*a")
    local b = w:match("function BookshelfWidget:_wallpaperName%(%)(.-)\nend\n")
    -- The mapping and fallbacks themselves are pinned by the shownWallpaper tests.
    assert(b and b:find("TP.shownWallpaper(full,", 1, true), "the shelf does not ask shownWallpaper")
    assert(not b:find("TP.wallpaperName(", 1, true), "the borrowed-wallpaper path is still there")
    assert(w:find("TP.isDarkName(", 1, true), "_wallpaperWidget does not skip the invert for a dark variant")
    assert(w:find('bookshelf_theme_pack").migrate()', 1, true), "the old borrowed wallpaper is not migrated")
    local wp = io.open("lib/bookshelf_wallpaper.lua"):read("*a")
    assert(wp:find("wallpaperPath(", 1, true), "pathFor does not resolve theme names")
end)

-- ── Apply pack theme ──────────────────────────────────────────────────────
local function mkwall(d, p) touch(d .. "/" .. p .. "/theme/wallpaper.png") end
local function mkplank(d, p, n) touch(d .. "/" .. p .. "/theme/plank." .. n .. ".middle.png") end
local function mkcolours(d, p) touch(d .. "/" .. p .. "/theme/colours.json", '{"day":{"text":"#112233"},"night":{}}') end

t.test("Apply pack theme sets exactly what the pack has, and switches the pack on", function()
    local TP, d, settings, packs_off = setup()
    TP._plugin_root = "."
    mkwall(d, "Japan"); mkplank(d, "Japan", "Gallery"); mkcolours(d, "Japan")
    TP.invalidate()
    packs_off["Japan"] = true
    local r = TP.applyPackTheme("Japan")
    eq(packs_off["Japan"], nil)
    eq(r.wallpaper, true); eq(r.colours, true); eq(r.plank, true); eq(r.pick_plank, false)
    eq(TP.isPackName(settings.wallpaper_default), true)
    eq(TP.activeColoursPack(), "Japan"); eq(TP.plankChoice(), "Japan/theme/plank.Gallery")
end)

t.test("Apply pack theme on a pack of several planks asks which, and changes nothing else", function()
    local TP, d, settings = setup()
    TP._plugin_root = "."
    mkplank(d, "Planks", "Walnut"); mkplank(d, "Planks", "Ash")
    TP.invalidate()
    settings.wallpaper_default = "leaves.png"
    local r = TP.applyPackTheme("Planks")
    eq(r.pick_plank, true); eq(r.plank, false); eq(r.wallpaper, false)
    eq(TP.plankChoice(), "oak"); eq(settings.wallpaper_default, "leaves.png")
end)

t.test("Undo pack theme puts the reader's own plank, wallpaper and colors back exactly", function()
    local TP, d, settings = setup()
    TP._plugin_root = "."
    mkwall(d, "Japan"); mkplank(d, "Japan", "Gallery"); mkcolours(d, "Japan")
    TP.invalidate()
    settings.wallpaper_default = "leaves.png"
    TP.choosePlank("colour")
    TP.applyPackTheme("Japan")
    eq(TP.appliedPack(), "Japan")
    TP.undoPackTheme()
    eq(settings.wallpaper_default, "leaves.png"); eq(TP.plankChoice(), "colour")
    eq(settings.wallpaper_default_own, nil)
    eq(TP.activeColoursPack(), nil); eq(TP.appliedPack(), nil)
end)

t.test("Undo restores unset values as unset (a fresh install stays a fresh install)", function()
    local TP, d, settings = setup()
    TP._plugin_root = "."
    mkwall(d, "Japan"); mkplank(d, "Japan", "Gallery")
    TP.invalidate()
    TP.applyPackTheme("Japan")
    TP.undoPackTheme()
    eq(settings.wallpaper_default, nil); eq(settings[TP.PLANK_SETTING], nil)
    eq(TP.plankChoice(), "oak")
end)

t.test("applying a second pack: Undo still returns to the reader's own, not the first pack's", function()
    local TP, d, settings = setup()
    mkwall(d, "Japan"); mkwall(d, "Autumn")
    TP.invalidate()
    settings.wallpaper_default = "leaves.png"
    TP.applyPackTheme("Japan"); TP.applyPackTheme("Autumn")
    eq(TP.appliedPack(), "Autumn")
    TP.undoPackTheme()
    eq(settings.wallpaper_default, "leaves.png")
end)

t.test("the confirmation names what will change", function()
    local TP, d = setup()
    mkwall(d, "Japan"); mkplank(d, "Japan", "Gallery")
    TP.invalidate()
    local s = TP.applySummary("Japan")
    assert(s:find("wallpaper and Gallery plank", 1, true), s)
    assert(not s:find("colors", 1, true), "it promises colors the pack does not have")
    mkplank(d, "Planks", "Walnut"); mkplank(d, "Planks", "Ash")
    TP.invalidate()
    assert(TP.applySummary("Planks"):find("a plank you choose", 1, true))
end)

t.test("Undo keeps what the reader chose after Apply, and restores the rest", function()
    local TP, d, settings = setup()
    TP._plugin_root = "."
    mkwall(d, "Japan"); mkplank(d, "Japan", "Gallery"); mkcolours(d, "Japan")
    TP.invalidate()
    settings.wallpaper_default = "leaves.png"
    TP.choosePlank("colour")
    TP.applyPackTheme("Japan")
    TP.chooseWallpaper("wallpaper_default", "sea.png")
    TP.choosePlank("oak")
    eq(TP.appliedPack(), "Japan", "the colours are still Japan's: Undo still has work to do")
    TP.undoPackTheme()
    eq(settings.wallpaper_default, "sea.png"); eq(TP.plankChoice(), "oak")
    eq(TP.activeColoursPack(), nil, "what Apply set and nobody changed goes back")
end)

t.test("once the reader has replaced everything Apply set, the button is Apply again", function()
    local TP, d, settings = setup()
    TP._plugin_root = "."
    mkwall(d, "Japan"); mkplank(d, "Japan", "Gallery")
    TP.invalidate()
    TP.applyPackTheme("Japan")
    TP.chooseWallpaper("wallpaper_default", "sea.png"); TP.choosePlank("oak")
    eq(TP.appliedPack(), nil)
end)

t.test("a deleted pack's snapshot is not reused by the next Apply", function()
    local TP, d, settings = setup()
    mkwall(d, "Japan"); mkwall(d, "Autumn")
    TP.invalidate()
    settings.wallpaper_default = "leaves.png"
    TP.applyPackTheme("Japan")
    os.execute("rm -rf '" .. d .. "/Japan'"); TP.invalidate()
    TP.chooseWallpaper("wallpaper_default", "sea.png")
    TP.applyPackTheme("Autumn")
    TP.undoPackTheme()
    eq(settings.wallpaper_default, "sea.png")
end)

t.test("Undo puts Plank designs back off when Apply switched them on", function()
    local TP, d = setup()
    TP._plugin_root = "."
    mkplank(d, "Japan", "Gallery")
    TP.invalidate()
    TP.setDesignsOn(false)
    TP.applyPackTheme("Japan")
    eq(TP.designsOn(), true)
    TP.undoPackTheme()
    eq(TP.designsOn(), false)
end)

t.test("a pack of several planks applies no plank, so there is nothing to undo there", function()
    local TP, d = setup()
    TP._plugin_root = "."
    mkplank(d, "Planks", "Walnut"); mkplank(d, "Planks", "Ash")
    TP.invalidate()
    TP.applyPackTheme("Planks")
    eq(TP.appliedPack(), nil, "the tab must not offer Undo for a plank the picker chose")
end)

t.test("shownWallpaper: a full screen pack pick over Same as default falls back to the default", function()
    local TP, d, settings, packs_off = setup()
    touch(d .. "/Japan/theme/wallpaper.png"); touch(d .. "/Japan/theme/wallpaper.full.png")
    TP.invalidate()
    settings.wallpaper_default = "leaves.png"
    local jp = TP.wallpaperEntries()[1].name
    TP.chooseWallpaper("wallpaper_full", jp)
    eq(TP.shownWallpaper(true, false), "theme-pack\1Japan\1wallpaper.full.png", "the pack's full variant")
    eq(TP.shownWallpaper(false, false), "leaves.png", "the default view is untouched")
    packs_off["Japan"] = true
    eq(TP.shownWallpaper(true, false), "leaves.png", "pack off: the default, not nothing")
end)

t.test("shownWallpaper: a pack default switched off shows the reader's own, in both views", function()
    local TP, d, settings, packs_off = setup()
    touch(d .. "/Japan/theme/wallpaper.png")
    TP.invalidate()
    settings.wallpaper_default = "leaves.png"
    TP.chooseWallpaper("wallpaper_default", TP.wallpaperEntries()[1].name)
    packs_off["Japan"] = true
    eq(TP.shownWallpaper(false, false), "leaves.png"); eq(TP.shownWallpaper(true, false), "leaves.png")
    settings.wallpaper_full = false
    eq(TP.shownWallpaper(true, false), nil, "full screen None stays None")
end)

t.done()
