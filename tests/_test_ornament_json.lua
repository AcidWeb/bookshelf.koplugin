-- tests/_test_ornament_json.lua
-- ornaments.json: per-ornament placement (size, height, padding, hang,
-- night, mirror, tap action) that follows the FILE onto every shelf. One in
-- the ornaments folder for the reader's own changes, one in each pack for
-- what the pack ships. Numbers are in the ornament's own proportions and the
-- books' height, so they hold at any DPI and shelf size.

package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg = function() end, info = function() end,
                              warn = function() end, err = function() end }
package.loaded["ui/widget/widget"] = { extend = function(_, t) return t end }
package.loaded["ui/geometry"] = { new = function(_, t) return t end }
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
        elseif attr == "modification" then
            local m = sh("stat -c %Y " .. q)
            return tonumber(m)
        end
        return nil
    end,
    mkdir = function(path) return os.execute("mkdir -p '" .. path .. "'") end,
    dir = function(path)
        local list = {}
        for name in sh("ls -a '" .. path .. "'"):gmatch("[^\n]+") do list[#list + 1] = name end
        local i = 0
        return function() i = i + 1; return list[i] end
    end,
}


local t  = dofile("tests/_helpers.lua").runner()
local eq = dofile("tests/_helpers.lua").eq

local mem = {}
local function fresh()
    package.loaded["lib/bookshelf_ornaments"] = nil
    local O = dofile("lib/bookshelf_ornaments.lua")
    O.SCAN_TTL = 0
    mem = {}
    O._store = { read = function(k) return mem[k] end, save = function(k, v) mem[k] = v end }
    return O
end
local tmp = os.getenv("TMPDIR") or "/tmp"
local function scratch()
    local d = string.format("%s/bookshelf_orn_json_%d_%d", tmp, os.time(), math.random(1e6))
    os.execute("rm -rf '" .. d .. "' && mkdir -p '" .. d .. "'")
    return d
end
local function svg(path, extra)
    local f = assert(io.open(path, "w")); f:write('<svg viewBox="0 0 10 10">' .. (extra or "") .. '</svg>'); f:close()
end
local function write(path, text) local f = assert(io.open(path, "w")); f:write(text); f:close() end
-- A tiny JSON reader for the test: the device uses rapidjson.
local function decode(text)
    local lua = text:gsub('"([^"]-)"%s*:', '["%1"]=')
    local f = assert(load("return " .. lua), "bad json")
    return f()
end
local function setup()
    local O = fresh()
    local d = scratch()
    O._data_dir = d; O._lfs = lfs_shim; O._decode = decode
    local new = d .. "/settings/bookshelf/ornaments"
    os.execute("mkdir -p '" .. new .. "/Autumn'")
    return O, new
end
local function byName(O)
    local out = {}
    for _i, e in ipairs(O.listAll()) do out[e.name] = e end
    return out
end

t.test("defaults when there is no file", function()
    local O, new = setup()
    svg(new .. "/cat.svg")
    local e = byName(O)["cat.svg"]
    eq(e.scale, 1); eq(e.lift, 0); eq(e.pad, 0); eq(e.mirror, "off")
    eq(e.hang, nil); eq(e.tap, nil)
end)

t.test("a pack's file places its pieces", function()
    local O, new = setup()
    svg(new .. "/Autumn/owl.svg")
    write(new .. "/Autumn/ornaments.json", '{ "owl.svg": { "scale": 1.5, "lift": -0.1, "hang": true, "mirror": "alternate" } }')
    local e = byName(O)["Autumn/owl.svg"]
    eq(e.scale, 1.5); eq(e.lift, -0.1); eq(e.hang, true); eq(e.mirror, "alternate")
end)

t.test("the reader's own file wins, field by field, keyed Pack/file", function()
    local O, new = setup()
    svg(new .. "/Autumn/owl.svg")
    write(new .. "/Autumn/ornaments.json", '{ "owl.svg": { "scale": 1.5, "pad": 0.1 } }')
    write(new .. "/ornaments.json", '{ "Autumn/owl.svg": { "scale": 0.8 } }')
    local e = byName(O)["Autumn/owl.svg"]
    eq(e.scale, 0.8, "the reader's scale")
    eq(e.pad, 0.1, "the pack's padding, which the reader did not change")
end)

t.test("a directive still works, below the files", function()
    local O, new = setup()
    svg(new .. "/pot.svg", "<!-- bookshelf:overhang=2 -->")
    local e = byName(O)["pot.svg"]
    eq(e.lift, -0.2, "overhang 2 of 10 is a lift of -0.2")
    write(new .. "/ornaments.json", '{ "pot.svg": { "lift": 0 } }')
    O.invalidate()
    eq(byName(O)["pot.svg"].lift, 0, "the file beats the directive")
end)

t.test("bad values are skipped and clamped, the rest applies", function()
    local O, new = setup()
    svg(new .. "/cat.svg")
    write(new .. "/ornaments.json", '{ "cat.svg": { "scale": 99, "lift": "high", "mirror": "sideways", "pad": -0.05 } }')
    local e = byName(O)["cat.svg"]
    eq(e.scale, 4, "clamped to the most a nudge allows")
    eq(e.lift, 0, "a non-number is ignored")
    eq(e.mirror, "off")
    eq(e.pad, -0.05, "negative padding tightens")
end)

t.test("an edited file is seen without a restart", function()
    local O, new = setup()
    O.SCAN_TTL = 0
    svg(new .. "/cat.svg")
    write(new .. "/ornaments.json", '{ "cat.svg": { "scale": 1.2 } }')
    eq(byName(O)["cat.svg"].scale, 1.2)
    os.execute("sleep 1")
    write(new .. "/ornaments.json", '{ "cat.svg": { "scale": 1.4 } }')
    eq(byName(O)["cat.svg"].scale, 1.4, "the change was missed")
end)

t.test("a broken file is logged and ignored, not fatal", function()
    local O, new = setup()
    svg(new .. "/cat.svg")
    write(new .. "/ornaments.json", '{ this is not json')
    O._decode = function() error("bad json") end
    local e = byName(O)["cat.svg"]
    assert(e, "the ornament vanished")
    eq(e.scale, 1)
end)

t.test("a reader's change applies at once, and is written when asked", function()
    local O, new = setup()
    svg(new .. "/Autumn/owl.svg")
    write(new .. "/Autumn/ornaments.json", '{ "owl.svg": { "scale": 1.5, "pad": 0.1 } }')
    local e = byName(O)["Autumn/owl.svg"]
    O.readerSet(e, "scale", 0.7)
    eq(e.scale, 0.7, "not applied to the piece")
    eq(e.pad, 0.1, "the pack's other values went")
    local written
    O._encode = function(t) written = t; return "{}" end
    assert(O.saveReader())
    eq(written["Autumn/owl.svg"].scale, 0.7, "keyed Pack/file in the reader's file")
    local f = io.open(new .. "/Autumn/ornaments.json"):read("*a")
    assert(not f:find("0.7", 1, true), "the pack's own file was written")
end)

t.test("reset drops the reader's record; the pack shows again", function()
    local O, new = setup()
    svg(new .. "/Autumn/owl.svg")
    write(new .. "/Autumn/ornaments.json", '{ "owl.svg": { "scale": 1.5 } }')
    local e = byName(O)["Autumn/owl.svg"]
    O.readerSet(e, "scale", 0.7)
    O.readerSet(e, "lift", 0.2)
    O.readerReset(e)
    eq(e.scale, 1.5); eq(e.lift, 0)
    eq(O.readerTable()["Autumn/owl.svg"], nil)
end)

t.test("a directive survives a reader's change to another field", function()
    local O, new = setup()
    svg(new .. "/pot.svg", "<!-- bookshelf:overhang=2 -->")
    local e = byName(O)["pot.svg"]
    O.readerSet(e, "scale", 1.2)
    eq(e.lift, -0.2, "the directive's overhang was lost on re-apply")
    O.readerSet(e, "lift", nil)
    eq(e.lift, -0.2)
end)

t.test("nudges step on a grid and stop at the limits", function()
    package.loaded["ffi/util"] = { template = function(s) return s end }
    package.loaded["lib/bookshelf_ornaments"] = fresh()
    local Menu = dofile("lib/bookshelf_ornament_menu.lua")
    local e = { scale = 1, lift = 0, pad = 0 }
    local v = 0
    for _i = 1, 3 do e.lift = Menu.nudged(e, "lift", 0.1) end
    eq(e.lift, 0.3, "three steps of 0.1 drifted")
    e.scale = 3.9
    eq(Menu.nudged(e, "scale", 0.25), 4, "past the most a nudge allows")
    local src = io.open("lib/bookshelf_ornament_menu.lua"):read("*a")
    assert(src:find("\\xEE\\xA1\\x82", 1, true) and src:find("\\xEE\\xA0\\xBF", 1, true),
        "up/down are not the bookends chevrons")
    assert(src:find("hold_callback", 1, true), "no big step on hold")
    assert(src:find("function dialog:onCloseWidget%(%.%.%.%)\n%s*Orn%.saveReader%(%)"),
        "nothing writes the file when the menu closes")
end)

t.test("the piece on the shelf answers long-press and, with an action, tap", function()
    local O = fresh()
    local held, tapped
    O.handlers = { hold = function(e) held = e return true end, tap = function(e) tapped = e return true end }
    local plain = { entry = { name = "a.svg" } }
    local w = setmetatable({ placement = plain }, { __index = O.Ornament })
    assert(w:onHoldOrnament(), "long-press not taken")
    eq(held, plain.entry)
    eq(w:onTapOrnament(), false, "a piece with no action took the tap from the shelf")
    local acting = { entry = { name = "b.svg", tap = { action = "x" } } }
    local w2 = setmetatable({ placement = acting }, { __index = O.Ornament })
    assert(w2:onTapOrnament())
    eq(tapped, acting.entry)
    local wsrc = io.open("lib/bookshelf_widget.lua"):read("*a")
    assert(wsrc:find('Gestures.on("ornament_hold")', 1, true) and wsrc:find('Gestures.on("ornament_tap")', 1, true),
        "the ornament gestures cannot be switched off")
end)

t.test("the menu opens clear of the piece it adjusts", function()
    package.loaded["ffi/util"] = { template = function(s) return s end }
    package.loaded["lib/bookshelf_ornaments"] = fresh()
    local Menu = dofile("lib/bookshelf_ornament_menu.lua")
    eq(Menu.offsetFor({ y = 700, h = 200 }, 1648), 412, "a piece in the top half: menu goes down")
    eq(Menu.offsetFor({ y = 1200, h = 200 }, 1648), -412, "bottom half: menu goes up")
    eq(Menu.offsetFor(nil, 1648), 0)
    local src = io.open("lib/bookshelf_ornament_menu.lua"):read("*a")
    assert(src:find("dialog:reinit(); place()", 1, true), "a redraw loses the offset")
end)

t.test("menu fix: rapid nudges cannot dismiss the menu by missing it", function()
    local src = io.open("lib/bookshelf_ornament_menu.lua"):read("*a")
    local show = src:match("dialog = ButtonDialog:new{(.-)\n    }")
    assert(show and show:find("dismissable = false", 1, true), "a tap outside still closes the nudge menu")
end)

t.test("an edit reaches the piece the shelf draws, even after a rescan made new entries", function()
    -- Device report: "sometimes I'll make changes in the ornament menu and
    -- nothing changes; if I close and reopen, it has reverted". The menu
    -- held the entry from before a rescan (the reader's own save changes
    -- the file's mtime, which is in the scan key), and edited that one.
    local O, new = setup()
    O.SCAN_TTL = 0
    O._encode = function() return "{}" end
    svg(new .. "/cat.svg")
    local old = byName(O)["cat.svg"]
    O.readerSet(old, "scale", 1.2)
    O.saveReader()
    os.execute("sleep 1")
    write(new .. "/ornaments.json", '{ "cat.svg": { "scale": 1.2 } }')   -- as saved
    local fresh = byName(O)["cat.svg"]
    assert(fresh ~= old, "the rescan was expected to build new entries")
    O.readerSet(old, "scale", 1.5)       -- the menu still holds the old entry
    eq(byName(O)["cat.svg"].scale, 1.5, "the shelf's entry did not get the edit")
    eq(O.current(old).scale, 1.5, "the menu cannot find the live entry")
end)

t.test("an edit reaches the list() entry the shelf draws, while list() is still cached", function()
    -- The shelf draws from list(), which is served from its cache for
    -- SCAN_TTL. A save changes the file's mtime, so listAll() builds new
    -- entries; list() still hands out the old ones until the TTL runs out,
    -- and an edit applied only to listAll()'s never reached the shelf (rig:
    -- a hanging piece's height nudge did nothing).
    local O, new = setup()
    O.SCAN_TTL = 1000
    O._encode = function() return "{}" end
    svg(new .. "/cat.svg")
    local drawn = O.list()[1]
    O.readerSet(drawn, "scale", 1.2)
    O.saveReader()
    os.execute("sleep 1")
    write(new .. "/ornaments.json", '{ "cat.svg": { "scale": 1.2 } }')
    local live = O.current(drawn)
    assert(live ~= drawn, "the rescan was expected to build new entries")
    assert(O.list()[1] == drawn, "list() was expected to still be cached")
    O.readerSet(live, "lift", 0.2)       -- the menu edits the live entry
    eq(O.list()[1].lift, 0.2, "the entry the shelf draws did not get the edit")
end)

t.test("menu: Swap replaces Switch off, and Shuffle all is there", function()
    local src = io.open("lib/bookshelf_ornament_menu.lua"):read("*a")
    assert(not src:find('_("Switch off")', 1, true), "Switch off is still in the menu")
    assert(src:find('_("Swap")', 1, true), "no Swap")
    assert(src:find('_("Shuffle all")', 1, true), "no Shuffle all")
    assert(src:find("Deck.swap(entry.name, chosen.name)", 1, true), "Swap does not trade places")
    assert(src:find("bw:onBookshelfShuffleOrnaments()", 1, true), "Shuffle all is not the shuffle action")
end)

t.done()
