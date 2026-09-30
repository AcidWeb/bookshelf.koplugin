-- tests/_test_pack_pickers_wiring.lua
-- One place to choose each kind (5.3): where the menus send the reader.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq
local settings = io.open("lib/bookshelf_settings.lua"):read("*a")

t.test("the two wallpaper rows open the wallpaper picker", function()
    local menu = settings:match("function Settings:_wallpaperMenu%(%)(.-)\nend\n")
    assert(menu, "_wallpaperMenu moved")
    assert(menu:find('bookshelf_wallpaper_browser").show(key', 1, true), "the rows do not open the picker")
    assert(menu:find("openPicker(Wallpaper.SETTING)", 1, true)
        and menu:find("openPicker(Wallpaper.FULL_SETTING)", 1, true), "a row is not wired")
    assert(not settings:find("_wallpaperSubItems", 1, true), "the old list menu is still there")
end)

t.test("the Shelf plank row opens the plank picker, in both menus", function()
    local row = settings:match("function Settings:_plankRow%(.-\nend\n")
    assert(row and row:find('bookshelf_plank_browser").show(', 1, true), "the plank row does not open the picker")
    local bg = settings:match("function Settings:_backgroundSubItems%(%)(.-)\nend\n")
    assert(bg and bg:find("self:_plankRow(", 1, true), "no plank row next to the wallpaper rows")
    local colours = settings:match("function Settings:_colorsSubItems%(.-\nend\n")
    assert(colours and colours:find("self:_plankRow(markDirty)", 1, true), "no plank row in Accent colors")
    assert(not settings:find("plank active - tap to deactivate", 1, true), "the deactivate row is still there")
end)

t.test("the plank colour dialog no longer offers Oak", function()
    local pp = settings:match("function Settings:_pickPlank%(.-\nend\n")
    assert(pp and not pp:find("special_tile", 1, true) and not pp:find("Oak wood", 1, true))
    assert(pp:find('choosePlank("colour")', 1, true), "picking a colour does not make the plank the colour")
end)

t.test("Performance tweaks names the plank from plankRowLabel", function()
    local perf = settings:match("function Settings:_performanceSubItems%(%)(.-)\nend\n")
    assert(perf and perf:find(").plankRowLabel()", 1, true), "the row does not name the plank in use")
    assert(perf:find("TP.setDesignsOn(", 1, true), "the row does not switch designs")
    assert(not settings:find("plank colour dialog or the ornaments browser", 1, true), "old help text")
end)

t.test("pickers mark the choice with painted marks, not words", function()
    local pb = io.open("lib/bookshelf_plank_browser.lua"):read("*a")
    assert(pb:find("Marks.Radio:new{ checked = PB.inUse(o) }", 1, true), "no radio mark on a plank")
    assert(not pb:find('_("In use")', 1, true), "the plank picker still says In use")
    local ob = io.open("lib/bookshelf_ornament_browser.lua"):read("*a")
    assert(ob:find("Marks.Check:new{ checked = not item.off, enabled = not item.pack_off }", 1, true),
        "no checkbox on an ornament card")
    assert(not ob:find('_("Off")', 1, true), "the card still says Off")
end)

local browser = io.open("lib/bookshelf_ornament_browser.lua"):read("*a")
t.test("the collection shows ornaments only, and offers Apply pack theme", function()
    local items = browser:match("function Browser:_items%(%)(.-)\nend\n")
    assert(items and not items:find("plankEntries", 1, true), "plank tiles are still listed")
    assert(not browser:find("is_plank", 1, true), "plank branches are still there")
    local foot = browser:match("function Browser:_footerRows%(%)(.-)\nend\n")
    assert(foot and foot:find('_("Apply pack theme")', 1, true), "no Apply pack theme")
    assert(foot:find('_("Undo pack theme")', 1, true) and foot:find("TP.appliedPack() == pack", 1, true),
        "the button does not become Undo for the applied pack")
    assert(foot:find("ConfirmBox:new{", 1, true) and foot:find("TP.applySummary(pack)", 1, true),
        "Apply does not ask first, naming what changes")
    assert(not foot:find('_("Colors: on")', 1, true), "the colors toggle is still in the footer")
    local apply = browser:match("function Browser:_applyTheme%(pack%)(.-)\nend\n")
    assert(apply and apply:find('bookshelf_plank_browser").show(', 1, true), "several planks do not open the picker")
end)

t.test("Accent colors starts with a Color theme row; no override rows remain", function()
    local body = settings:match("function Settings:_colorsSubItems%(.-\nend\n")
    assert(body and body:find('_("Color theme: %1")', 1, true), "no Color theme row")
    assert(body:find("table.insert(items, 1, theme_row)", 1, true), "the row is not first")
    assert(not settings:find("withOverride", 1, true), "withOverride is still used")
    assert(not settings:find("active - tap to deactivate", 1, true), "an override row is still there")
    local tp = io.open("lib/bookshelf_theme_pack.lua"):read("*a")
    assert(not tp:find("function M.withOverride", 1, true), "withOverride still exists")
end)

t.test("a Color theme from an off pack is marked, and choosing it switches the pack on", function()
    local body = settings:match("function Settings:_colorsSubItems%(.-\nend\n")
    local row = body and body:match("local theme_row = {(.-)\n    }\n")
    assert(row and row:find("isPackOff(p)", 1, true), "an off pack is not marked")
    assert(row:find("setPackOff(p, false)", 1, true), "choosing it does not switch the pack on")
end)

t.test("while a pack's theme is applied its tab offers Undo, not Switch pack off as well", function()
    local foot = browser:match("function Browser:_footerRows%(%)(.-)\nend\n")
    assert(foot, "_footerRows moved")
    local applied = foot:match("if TP%.appliedPack%(%) == pack then\n(.-)\n        end\n")
    assert(applied, "no footer of its own for an applied theme")
    assert(applied:find('_("Undo pack theme")', 1, true) and applied:find("close", 1, true),
        "the applied footer is Undo and Apply")
    assert(not applied:find("_packAction", 1, true), "Switch pack off is offered beside Undo")
end)

t.test("the pickers put KOReader's menu away while open and bring it back once", function()
    local body = settings:match("\n(function Settings:_hidePickerMenu%(.-\nend)\n")
    assert(body, "no _hidePickerMenu")
    local env = setmetatable({ Settings = {} }, { __index = _G })
    local chunk = assert((loadstring or load)(body, "=hide", "t", env))
    if setfenv then setfenv(chunk, env) end
    chunk()
    local hidden, restored = 0, 0
    local S = { _plugin = { hideMenu = function(_p, tmi) hidden = hidden + 1; return function() restored = restored + 1 end end } }
    local restore = env.Settings._hidePickerMenu(S, {})
    eq(hidden, 1, "hidden through the plugin's guarded hideMenu")
    restore(); restore()
    eq(restored, 1, "brought back once, however many ways the picker closes")
    local row = settings:match("function Settings:_plankRow%(.-\nend\n")
    assert(row:find("self:_hidePickerMenu(touchmenu_instance)", 1, true) and row:find("on_closed = restore", 1, true),
        "the plank picker does not put the menu away")
    local menu = settings:match("function Settings:_wallpaperMenu%(%)(.-)\nend\n")
    assert(menu:find("self:_hidePickerMenu(touchmenu_instance)", 1, true) and menu:find("end, restore)", 1, true),
        "the wallpaper picker does not put the menu away")
end)

t.test("choosing a plain plank colour comes back to the plank picker, not the menu", function()
    local pb = io.open("lib/bookshelf_plank_browser.lua"):read("*a")
    local tap = pb:match("on_cell_tap = function%(o%)(.-)\n        end,")
    assert(tap and tap:find("opts.pick_colour(before, reopen)", 1, true), "the colour dialog is not told to come back")
    local closed = pb:match("on_closed = function%(%)(.-)\n        end,")
    assert(closed and closed:find("if not self.reopening", 1, true), "the menu comes back between the picker and the dialog")
    local pc = settings:match("function Settings:_pickColor%(.-\nend\n")
    assert(pc and pc:find("wood.on_done", 1, true), "the colour dialogs have no way to say they closed")
    local pp = settings:match("function Settings:_pickPlank%(.-\nend\n")
    assert(pp and pp:find("on_done = on_done", 1, true), "the plank colour dialog does not pass it on")
end)

t.done()
