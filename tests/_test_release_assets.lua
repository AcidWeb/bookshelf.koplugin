-- tests/_test_release_assets.lua
-- The release zip is `git archive`, and .gitattributes leaves assets/ out
-- unless a path is whitelisted. A runtime asset missing from the whitelist
-- ships in a checkout and vanishes from every release (and every git-archive
-- deploy) with no error: the built-in oak plank did, the moment the whitelist
-- landed. Every asset folder the code reads at runtime is pinned here.
-- Run from the plugin root: lua tests/_test_release_assets.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local t = dofile("tests/_helpers.lua").runner()
local ga = io.open(".gitattributes"):read("*a")

local function whitelisted(path)
    return ga:find("\n" .. path:gsub("%p", "%%%0") .. "%s+%-export%-ignore") ~= nil
end

for _i, dir in ipairs({ "assets/wallpapers", "assets/planks" }) do
    t.test(dir .. " ships in the release archive", function()
        assert(whitelisted(dir), dir .. " (the folder) is not whitelisted in .gitattributes")
        assert(whitelisted(dir .. "/**"), dir .. "/** (its contents) is not whitelisted")
    end)
end

t.test("the built-in oak plank reads from a whitelisted folder", function()
    local tp = io.open("lib/bookshelf_theme_pack.lua"):read("*a")
    assert(tp:find('"/assets/planks/oak"', 1, true), "the built-in plank moved; update the whitelist and this test")
end)

t.done()
