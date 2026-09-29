-- tests/_test_pack_pickers_wiring.lua
-- One place to choose each kind (5.3): where the menus send the reader.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t = H.runner()
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

t.done()
