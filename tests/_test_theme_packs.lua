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
    eq(TP.theme("A").plank, nil, "no middle, no plank")
    touch(d .. "/B/theme/plank.middle.png"); touch(d .. "/B/theme/plank.right.png")
    local p = TP.theme("B").plank
    assert(p.middle:match("/B/theme/plank%.middle%.png$")); eq(p.left, nil)
    assert(p.right:match("plank%.right%.png$"))
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
    eq(TP.activePlankPack(), "A", "unset: the first pack with a plank")
    TP.setPlankOn("B", true); eq(TP.activePlankPack(), "B")
    TP.setPlankOn("B", false); eq(TP.activePlankPack(), "A", "B off: A is next")
    TP.setPlankOn("A", false); eq(TP.activePlankPack(), nil)
    TP.setPlankOn("A", true); packs_off["A"] = true
    eq(TP.activePlankPack(), nil, "a switched-off pack shows no plank")
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

t.test("plankEntry: a browser item for the pack's plank design", function()
    local TP, d = setup()
    eq(TP.plankEntry("None"), nil)
    local png = "\137PNG\r\n\026\n" .. string.char(0,0,0,13) .. "IHDR"
                .. string.char(0,0,1,0) .. string.char(0,0,0,96) .. string.char(8,6,0,0,0)
    touch(d .. "/Xmas/theme/plank.middle.png", png)
    package.loaded["lib/bookshelf_ornaments"] = { parsePngHeader = function(b)
        local w = b:byte(17) * 16777216 + b:byte(18) * 65536 + b:byte(19) * 256 + b:byte(20)
        local h = b:byte(21) * 16777216 + b:byte(22) * 65536 + b:byte(23) * 256 + b:byte(24)
        return w / h end }
    local e = TP.plankEntry("Xmas")
    eq(e.name, "Xmas/theme/plank"); eq(e.file, "Plank"); eq(e.is_plank, true)
    eq(e.aspect, 256 / 96)
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

t.done()
