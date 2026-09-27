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

t.done()
