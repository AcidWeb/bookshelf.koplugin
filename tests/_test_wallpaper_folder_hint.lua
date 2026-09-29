-- tests/_test_wallpaper_folder_hint.lua
-- The wallpaper picker always says where pictures come from.
--
-- WHAT CHANGED. The line naming the folder appeared only when the folder was
-- EMPTY, on the reasoning that a reader who already has pictures knows where
-- they put them. Bundling a picture breaks that reasoning: the folder is
-- never empty on a fresh install, so the one line that tells a reader how to
-- add their own would only ever be seen by someone who had first deleted the
-- shipped one (maintainer).
--
-- Since 5.3 the picker is a browser (bookshelf_wallpaper_browser), and the
-- line is on the None card, which comes first on every tab of the reader's
-- own pictures.
--
-- Usage (from plugin root): lua tests/_test_wallpaper_folder_hint.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local helpers = dofile("tests/_helpers.lua")
local t = helpers.runner()
local src = io.open("lib/bookshelf_wallpaper_browser.lua"):read("*a")

t.test("the folder is named whether or not there are pictures", function()
    local none = src:match('if item%.kind == "none" then(.-)\n        elseif')
    assert(none, "the None card's hint moved")
    assert(none:find("Images are loaded from %1", 1, true), "no always-on folder hint")
    assert(none:find("No images in %1", 1, true), "the empty case lost its message")
    assert(none:find("Wallpaper.dir", 1, true), "the hint must name the real folder, not a guess at it")
end)

t.done()
