-- tests/_test_shelf_size_back_key.lua
-- Back closes "Adjust shelf/top panel size" on a device with keys, as Cancel.
--
-- The dialog is dismissable = false (Cancel/Accept only, tap-outside off), and
-- ButtonDialog binds Back only for dismissable dialogs, so on a keys-only
-- device Back did nothing at all (GitHub issue 361). It now reverts and
-- closes, exactly as Cancel does.
package.path = "./?.lua;./?/init.lua;" .. package.path
local t  = dofile("tests/_helpers.lua").runner()

local src = io.open("lib/bookshelf_settings.lua"):read("*a")
local s = src:find('title = _("Adjust shelf/top panel size")', 1, true)
assert(s, "Adjust shelf/top panel size dialog not found")
local e = src:find("UIManager:show(dialog)", s, true)
local block = src:sub(s, e)

t.test("Back is bound on the dialog", function()
    assert(block:find("key_events%.BSSizeBack%s*=%s*{%s*{%s*Device%.input%.group%.Back%s*}%s*}"),
        "Back is not bound on the size dialog")
end)

t.test("Back runs Cancel", function()
    assert(block:find("onBSSizeBack%s*=%s*function%(%)%s*cancel%(%)%s*return true%s*end"),
        "Back does not run cancel()")
end)

t.done()
