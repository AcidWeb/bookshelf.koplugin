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

t.test("borrowed wallpaper: only a pack that has one; one at a time", function()
    local TP, d, settings = setup()
    touch(d .. "/A/theme/wallpaper.png"); touch(d .. "/B/theme/wallpaper.png"); touch(d .. "/C/Owl.png")
    TP.setWallpaperPack("A"); eq(TP.activeWallpaperPack(), "A")
    TP.setWallpaperPack("B"); eq(TP.activeWallpaperPack(), "B", "a second pack replaces the first")
    TP.setWallpaperPack("C"); eq(TP.activeWallpaperPack(), nil, "C has no wallpaper")
    TP.setWallpaperPack(nil); eq(settings[TP.WALLPAPER_SETTING], nil)
end)

t.test("stale pack falls back and the setting is cleared", function()
    local TP, d, settings = setup()
    touch(d .. "/A/theme/wallpaper.png")
    touch(d .. "/A/theme/colours.json", '{"day": {"text": "#101010"}}')
    TP.setWallpaperPack("A"); TP.setColoursPack("A")
    os.execute("rm -rf '" .. d .. "/A'")
    eq(TP.activeWallpaperPack(), nil); eq(settings[TP.WALLPAPER_SETTING], nil)
    eq(TP.activeColoursPack(), nil); eq(TP.colourOverride("ink_color", false), nil)
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

t.test("plank: on by default when one pack has it, one at a time, follows the pack", function()
    local TP, d, settings, packs_off = setup()
    touch(d .. "/A/theme/plank.middle.png"); touch(d .. "/B/theme/plank.middle.png")
    touch(d .. "/B/theme/plank.oak.middle.png")
    TP.setWood(false)                -- pack planks alone; the built-in oak has its own test
    local function shown() local p = TP.activePlank(); return p and p.id end
    eq(shown(), "A/theme/plank", "unset: the first plank there is")
    TP.setPlankOn("B/theme/plank.oak", true); eq(shown(), "B/theme/plank.oak")
    TP.setPlankOn("B/theme/plank.oak", false); eq(shown(), nil,
        "switching the shown plank off shows none, not the next one")
    TP.setPlankOn("A/theme/plank", true); packs_off["A"] = true
    eq(shown(), "B/theme/plank", "a switched-off pack's plank never shows; the next one does")
end)

t.test("borrowed wallpaper resolves through a theme name, dark variant flagged", function()
    local TP, d = setup()
    touch(d .. "/Xmas/theme/wallpaper.png"); touch(d .. "/Xmas/theme/wallpaper.dark.png")
    eq(TP.wallpaperName(false, false), nil, "nothing borrowed")
    TP.setWallpaperPack("Xmas")
    local n = TP.wallpaperName(false, true)
    eq(n, TP.NAME_PREFIX .. "Xmas\1wallpaper.dark.png"); eq(TP.isDarkName(n), true)
    eq(TP.isDarkName(TP.wallpaperName(false, false)), false)
    eq(TP.wallpaperPath("Xmas\1wallpaper.png"), d .. "/Xmas/theme/wallpaper.png")
    eq(TP.wallpaperPath("Xmas\1../../etc/passwd"), nil, "no path escapes")
    eq(TP.wallpaperPath("..\1wallpaper.png"), nil)
    eq(TP.wallpaperPath("Xmas\1missing.png"), nil)
end)

t.test("the shelf asks the theme first, and pathFor knows theme names", function()
    local w = io.open("lib/bookshelf_widget.lua"):read("*a")
    assert(w:find("TP.wallpaperName(", 1, true), "_wallpaperName does not consult the theme")
    assert(w:find("TP.isDarkName(", 1, true), "_wallpaperWidget does not skip the invert for a dark variant")
    local wp = io.open("lib/bookshelf_wallpaper.lua"):read("*a")
    assert(wp:find("wallpaperPath(", 1, true), "pathFor does not resolve theme names")
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

t.test("plankEntries: a browser item per plank design", function()
    local TP, d = setup()
    eq(#TP.plankEntries("None"), 0)
    local png = "\137PNG\r\n\026\n" .. string.char(0,0,0,13) .. "IHDR"
                .. string.char(0,0,1,0) .. string.char(0,0,0,96) .. string.char(8,6,0,0,0)
    touch(d .. "/Xmas/theme/plank.middle.png", png)
    package.loaded["lib/bookshelf_ornaments"] = { parsePngHeader = function(b)
        local w = b:byte(17) * 16777216 + b:byte(18) * 65536 + b:byte(19) * 256 + b:byte(20)
        local h = b:byte(21) * 16777216 + b:byte(22) * 65536 + b:byte(23) * 256 + b:byte(24)
        return w / h end }
    touch(d .. "/Xmas/theme/plank.gold.middle.png", png)
    local es = TP.plankEntries("Xmas")
    eq(#es, 2)
    eq(es[1].name, "Xmas/theme/plank"); eq(es[1].file, "Plank"); eq(es[1].is_plank, true)
    eq(es[1].aspect, 256 / 96)
    eq(es[2].name, "Xmas/theme/plank.gold"); eq(es[2].file, "gold")
    package.loaded["lib/bookshelf_ornaments"] = nil
end)

t.test("withOverride: a first line while active, the rest greyed; tapping restores", function()
    local TP = setup()
    local items = { { text = "a" }, { text = "b", enabled_func = function() return true end } }
    local plain = TP.withOverride(items, nil, function() end)
    eq(#plain, 2, "nothing borrowed: menu unchanged")
    local turned_off = false
    local out = TP.withOverride({ { text = "a" }, { text = "b" }, { text = "c" } },
                                "Xmas wallpaper active - tap to deactivate",
                                function() turned_off = true end, { [3] = true })
    eq(#out, 4); eq(out[1].text, "Xmas wallpaper active - tap to deactivate")
    eq(out[2].enabled_func(), false); eq(out[4].enabled_func == nil or out[4].enabled_func(), true)
    local menu = { item_table = out, updateItems = function() end }
    out[1].callback(menu)
    eq(turned_off, true); eq(#menu.item_table, 3, "the line is gone")
    eq(out[2].enabled_func(), true, "rows live again")
end)

t.test("withOverride leaves a row marked _theme_keep live (another part's own line)", function()
    local TP = setup()
    local out = TP.withOverride({ { text = "a" }, { text = "plank", _theme_keep = true } },
                                "X colors active - tap to deactivate", function() end)
    eq(out[2].enabled_func(), false)
    eq(out[3].enabled_func == nil or out[3].enabled_func(), true)
end)


t.test("activePlank is cached for the scan TTL; setPlankOn and invalidate() drop it", function()
    local TP, d = setup()
    touch(d .. "/A/theme/plank.middle.png")
    TP.setWood(false)                -- pack planks alone
    TP.SCAN_TTL = 15
    local now = 1000; TP._clock = function() return now end
    local calls = 0
    local real = TP._orn.listAll
    TP._orn.listAll = function(...) calls = calls + 1; return real(...) end
    eq(TP.activePlank().pack, "A"); eq(TP.activePlank().pack, "A")
    eq(calls, 1, "a page turn must not re-list the ornaments folder")
    TP.setPlankOn("A/theme/plank", false); eq(TP.activePlank(), nil, "a switch is seen at once")
    TP.setPlankOn("A/theme/plank", true); TP.invalidate(); eq(TP.activePlank().pack, "A")
    now = now + 16; TP.activePlank(); eq(calls >= 3, true, "and it expires")
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
        "a plank tap still flashes the whole screen")
    assert(toggle:find("setPackOff(item.pack, false)", 1, true),
        "a plank tap in a switched-off pack does not switch the pack on")
    local closed = b:match("local function closed%(%).-\n    end")
    assert(closed and closed:find("endDeferred", 1, true) and closed:find("on_change", 1, true)
        and closed:find('setDirty("all", "full")', 1, true),
        "closing must flush, rebuild the shelf once, and repaint fully when the plank or wallpaper changed")
    local st = io.open("lib/bookshelf_settings.lua"):read("*a")
    local row = st:match("TP%.setPlankOn%(p%.id, false%).-return")
    assert(row and row:find('setDirty("all", "full")', 1, true),
        "the plank row's deactivate must repaint fully too")
end)


t.test("built-in Oak: shows when switched on, under any pack plank, and comes back when a pack plank goes", function()
    local TP, d, settings = setup()
    TP._plugin_root = "."            -- the repo's own assets/planks/oak
    TP.setWood(false)
    eq(TP.activePlank(), nil, "wood off, no packs: the coloured plank")
    TP.setWood(true)
    local p = TP.activePlank()
    assert(p and p.builtin, "wood on: the built-in plank")
    eq(p.name, "Oak"); eq(TP.plankLabel(p), "Oak")
    assert(p.middle:match("assets/planks/oak/plank%.middle%.png$") and io.open(p.middle, "rb"), "ships in the plugin")
    assert(p.left and p.right, "with both ends")
    touch(d .. "/Woods/theme/plank.birch.middle.png")
    TP.invalidate()
    eq(TP.activePlank().id, "Woods/theme/plank.birch", "a pack plank overrides the built-in Oak")
    TP.setPlankOn("Woods/theme/plank.birch", false)
    assert(TP.activePlank().builtin, "switching the pack plank off falls back to Oak, not the coloured plank")
    TP.setWood(false)
    eq(TP.activePlank(), nil, "and Oak off leaves the coloured plank")
    eq(settings[TP.WOOD_SETTING], false)
end)

t.test("unset, the Oak is on unless the reader picked a plank colour of their own", function()
    local TP, _d, settings = setup()
    TP._plugin_root = "."
    eq(TP.woodOn(), true, "never touched: the new default oak, on upgrade as on a new install")
    settings["spine_plank_color"] = { hex = "#806040" }
    eq(TP.woodOn(), false, "a day plank colour they picked stays")
    settings["spine_plank_color"] = nil; settings["spine_plank_color_night"] = { grey = 90 }
    eq(TP.woodOn(), false, "so does a night one")
    TP.setWood(true); eq(TP.woodOn(), true, "an explicit choice wins either way")
    TP.setWood(false); settings["spine_plank_color_night"] = nil
    eq(TP.woodOn(), false)
end)

t.test("the plank colour dialogs carry the Oak switch (palette tile and greyscale button)", function()
    local st = io.open("lib/bookshelf_settings.lua"):read("*a")
    local row = st:match('pickColor%("spine_plank_color".-end,')
    assert(st:find("_pickPlank(", 1, true), "the plank row does not open the plank dialog")
    local pp = st:match("function Settings:_pickPlank%(.-\nend\n")
    assert(pp and pp:find("special_tile", 1, true), "no Oak tile in the colour palette")
    assert(pp:find("extra_button", 1, true) or pp:find("text_func", 1, true), "no Oak switch in the greyscale dialog")
    local pal = io.open("lib/bookshelf_color_palette.lua"):read("*a")
    assert(pal:find("special_tile", 1, true), "the palette cannot show a custom tile")
end)

t.test("Performance tweaks can switch plank designs off; choosing a plank switches them back on", function()
    -- Maintainer: optional things turned on by default get a switch in
    -- Performance tweaks (a plank design costs ~35ms a spine tap on a PW5),
    -- and it must not stop a reader choosing a plank.
    local TP, d, settings = setup()
    TP._plugin_root = "."
    touch(d .. "/Woods/theme/plank.birch.middle.png")
    TP.invalidate()
    TP.setPlankOn("Woods/theme/plank.birch", true)
    eq(TP.activePlank().id, "Woods/theme/plank.birch")
    TP.setDesignsOn(false)
    eq(TP.activePlank(), nil, "designs off: none drawn")
    eq(TP.chosenPlank().id, "Woods/theme/plank.birch", "but the menu still knows which is chosen")
    eq(TP.designsOn(), false)
    TP.setPlankOn("Woods/theme/plank.birch", true)
    eq(TP.designsOn(), true, "choosing a pack plank switches designs back on")
    eq(TP.activePlank().id, "Woods/theme/plank.birch")
    TP.setDesignsOn(false)
    TP.setWood(true)
    eq(TP.designsOn(), true, "choosing Oak switches designs back on")
    TP.setDesignsOn(false)
    TP.setWood(false)
    eq(TP.designsOn(), false, "switching Oak OFF is not a choice of plank")
    eq(settings[TP.DESIGNS_OFF_SETTING], true)
    TP.setDesignsOn(true)
    eq(settings[TP.DESIGNS_OFF_SETTING], nil, "on is the default, stored as nothing")
end)

t.test("the Performance tweaks row names the design in use", function()
    local st = io.open("lib/bookshelf_settings.lua"):read("*a")
    local perf = st:match("function Settings:_performanceSubItems%(%)(.-)\nend\n")
    assert(perf and perf:find("TP.chosenPlank()", 1, true), "the row does not say which plank is in use")
    assert(perf:find("TP.setDesignsOn(", 1, true), "the row does not switch designs")
end)

t.done()
