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

t.done()
