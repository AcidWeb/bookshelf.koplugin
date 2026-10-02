-- tests/_test_shelf_theme_menu.lua
-- Theme packs are chosen in the Shelf theme menu, as a second group under
-- Auto / Light / Dark (maintainer, 2026-10-02). The menu is built each time it
-- opens and rescans the packs first, so one copied in since start-up shows.
-- Usage (from plugin root): lua tests/_test_shelf_theme_menu.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local src = io.open("lib/bookshelf_settings.lua"):read("*a")

local function grab(pat, what)
    local body = src:match(pat)
    assert(body, what .. " not found")
    return body
end
local CODE = table.concat({
    grab("\n(Settings%.SHELF_THEMES = {.-\n})\n", "SHELF_THEMES"),
    grab("\n(function Settings:_shelfTheme%(%).-\nend)\n", "_shelfTheme"),
    grab("\n(function Settings:_shelfThemeLabel%(%).-\nend)\n", "_shelfThemeLabel"),
    grab("\n(function Settings:_themePackLabel%(%).-\nend)\n", "_themePackLabel"),
    grab("\n(function Settings:_shelfThemeSubItems%(%).-\nend)\n", "_shelfThemeSubItems"),
    grab("\n(function Settings:_shelfThemeRow%(%).-\nend)\n", "_shelfThemeRow"),
}, "\n")

-- build(packs, current) -> the menu's rows and what the stubs saw.
local function build(packs, current)
    local seen = { rescans = 0, chosen = {}, cleared = 0, toasts = {}, dirty = 0, full = 0, store = {} }
    local TP = {
        rescan = function() seen.rescans = seen.rescans + 1 end,
        themePacks = function() return packs end,
        currentTheme = function() return current end,
        chooseTheme = function(p) seen.chosen[#seen.chosen + 1] = p; current = p; return true end,
        clearTheme = function() seen.cleared = seen.cleared + 1; current = nil end,
    }
    local env = setmetatable({
        Settings = {},
        _ = function(s) return s end,
        T = function(f, ...)
            local a = { ... }
            return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end))
        end,
        BookshelfSettings = { read = function(k) return seen.store[k] end,
                              save = function(k, v) seen.store[k] = v end, flush = function() end },
        UIManager = { show = function(_u, w) seen.toasts[#seen.toasts + 1] = w.text end,
                      setDirty = function(_u, w, mode) if w == "all" and mode == "full" then seen.full = seen.full + 1 end end },
        require = function(m)
            if m == "lib/bookshelf_theme_pack" then return TP end
            if m == "lib/bookshelf_cover_progress" then return { THEME_SETTING = "shelf_theme" } end
            if m == "ui/widget/infomessage" then return { new = function(_s, o) return o end } end
            return require(m)
        end,
    }, { __index = _G })
    local chunk = assert((loadstring or load)(CODE, "=menu", "t", env))
    if setfenv then setfenv(chunk, env) end
    chunk()
    local self = setmetatable({ _markDirty = function() seen.dirty = seen.dirty + 1 end },
                              { __index = env.Settings })
    return self, env.Settings, seen
end

local HW = { pack = "Halloween", name = "Halloween", description = "Bats and ghosts.", shelf = "dark" }
local UK = { pack = "Ukiyo-e", name = "Ukiyo-e" }

t.test("with no theme packs the menu is the three rows it always was", function()
    local self, S, seen = build({}, nil)
    local rows = S._shelfThemeSubItems(self)
    eq(#rows, 3)
    eq(rows[3].separator, nil, "a separator with nothing under it")
    eq(seen.rescans, 1, "opening the menu did not rescan the packs")
end)

t.test("theme packs follow a separator: No theme pack, then each by name", function()
    local self, S = build({ HW, UK }, "Halloween")
    local rows = S._shelfThemeSubItems(self)
    eq(#rows, 6)
    eq(rows[3].separator, true)
    eq(rows[4].text, "No theme pack"); eq(rows[5].text, "Halloween"); eq(rows[6].text, "Ukiyo-e")
    eq(rows[5].help_text, "Bats and ghosts.")
    for i = 4, 6 do eq(rows[i].radio, true); eq(rows[i].keep_menu_open, true) end
    eq(rows[4].checked_func(), false); eq(rows[5].checked_func(), true); eq(rows[6].checked_func(), false)
end)

t.test("choosing a theme pack applies it, rebuilds the whole screen and says so", function()
    local self, S, seen = build({ HW, UK }, nil)
    local rows = S._shelfThemeSubItems(self)
    local updated = 0
    rows[6].callback({ updateItems = function() updated = updated + 1 end })
    eq(seen.chosen[1], "Ukiyo-e")
    eq(seen.dirty, 1, "the shelf was not rebuilt"); eq(seen.full, 1, "no full refresh for a whole new look")
    eq(seen.toasts[1], "Ukiyo-e theme on")
    eq(updated, 1, "the menu's marks did not update")
end)

t.test("No theme pack clears a theme, and does nothing without one", function()
    local self, S, seen = build({ HW }, "Halloween")
    local rows = S._shelfThemeSubItems(self)
    rows[4].callback(nil)
    eq(seen.cleared, 1); eq(seen.toasts[1], "Theme pack off")
    rows[4].callback(nil)
    eq(seen.cleared, 1, "cleared again with no theme on"); eq(#seen.toasts, 1)
end)

t.test("the row names the light/dark choice and the theme", function()
    local self, S, seen = build({ HW, UK }, "Halloween")
    seen.store.shelf_theme = "dark"
    eq(S._shelfThemeRow(self).text_func(), "Shelf theme: Dark, Halloween")
    local self2, S2, seen2 = build({ HW }, nil)
    seen2.store.shelf_theme = "dark"
    eq(S2._shelfThemeRow(self2).text_func(), "Shelf theme: Dark")
end)

t.done()
