-- tests/_test_version_gate.lua
-- Bookshelf crashes on KOReader older than v2025.08 (reports from users of
-- older KOReader); now main.lua's first act is to ask the gate, and on an
-- older version the plugin is a stub with one menu line saying what to do.
-- v2025.08 to v2026.02 run, with square cover corners on colour screens, so
-- they are let through (maintainer).
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq

package.loaded["logger"] = { dbg = function() end, info = function() end, warn = function() end, err = function() end }
local REV
package.loaded["version"] = {
    getCurrentRevision = function() return REV end,
    getNormalizedVersion = function(_self, rev)
        if not rev then return end
        local year, month, point, revision = rev:match("v(%d%d%d%d)%.(%d%d)%.?(%d?%d?)-?(%d*)")
        return ((tonumber(year) or 0) * 100 + (tonumber(month) or 0)) * 1000000
               + (tonumber(point) or 0) * 10000 + (tonumber(revision) or 0)
    end,
}
local Gate = dofile("lib/bookshelf_version_gate.lua")

t.test("older than v2025.08 is too old; v2025.08 and newer are not", function()
    for _i, rev in ipairs({ "v2025.07", "v2025.04-148-g1a2b3c", "v2024.11-1-gabc", "v2023.10" }) do
        REV = rev
        eq(Gate.tooOld(), true, rev .. " let through")
    end
    for _i, rev in ipairs({ "v2025.08", "v2025.08-3-gabc", "v2025.10", "v2026.02", "v2026.03", "v2026.07", "v2027.01" }) do
        REV = rev
        eq(Gate.tooOld(), false, rev .. " turned away")
    end
end)

t.test("a version that cannot be read is let through", function()
    -- No git-rev at all, or one KOReader's own parser makes nothing of: a
    -- custom build is not shut out on a guess.
    for _i, rev in ipairs({ false, "fatal: No names found", "my-build" }) do
        REV = rev or nil
        eq(Gate.tooOld(), false, tostring(rev) .. " turned away")
    end
end)

t.test("the stub is one menu line saying what to do", function()
    local registered, items
    local WidgetContainer = { extend = function(_self, o)
        o.__index = o
        return setmetatable(o, { __index = function() end })
    end }
    local Stub = Gate.stub(WidgetContainer)
    eq(Stub.name, "bookshelf")
    local inst = setmetatable({ ui = { menu = { registerToMainMenu = function(_m, p) registered = p end } } },
                              { __index = Stub })
    Stub.init(inst)
    assert(registered == inst, "the stub does not put itself in the menu")
    items = {}
    Stub.addToMainMenu(inst, items)
    local n, item = 0, nil
    for _k, v in pairs(items) do n = n + 1; item = v end
    eq(n, 1, "the stub adds more than one line")
    eq(item.text, "Update KOReader to v2025.08 or newer to use Bookshelf")
    assert(item.callback, "tapping the line does nothing")
end)

t.test("main.lua asks the gate before anything else of bookshelf's runs", function()
    local src = io.open("main.lua"):read("*a")
    local gate = src:find('require("lib/bookshelf_version_gate")', 1, true)
    local move = src:find('require("lib/bookshelf_storage_move").run()', 1, true)
    assert(gate and move and gate < move, "the gate comes after the storage move")
    for _i, m in ipairs({ "lib/bookshelf_settings_store", "lib/bookshelf_i18n" }) do
        local at = src:find('require("' .. m .. '")', 1, true)
        assert(at and gate < at, m .. " loads before the gate")
    end
end)

t.done()
