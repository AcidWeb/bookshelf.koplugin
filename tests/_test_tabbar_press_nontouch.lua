-- tests/_test_tabbar_press_nontouch.lua
-- Press on a focused tab in book details switches to it on a keys-only device.
--
-- FocusManager turns Press into a synthetic tap at the focused cell's centre;
-- TabBar:onTapTab turns that tap into the switch. The TapTab gesture range was
-- only registered on touch devices, so on a non-touch Kindle the tap found no
-- handler: Left/Right moved the highlight along the tabs and Press did nothing
-- (GitHub issue 361, reproduced on the rig with isTouchDevice faked off).
package.path = "./?.lua;./?/init.lua;" .. package.path
local t  = dofile("tests/_helpers.lua").runner()

local src = io.open("lib/bookshelf_reviews_modal.lua"):read("*a")
local init = src:match("\nfunction TabBar:init%(%)\n(.-)\nend\n")
assert(init, "could not find TabBar:init() - renamed?")

t.test("TapTab is registered whatever the device", function()
    local reg = init:find("TapTab%s*=")
    assert(reg, "TabBar:init no longer registers TapTab")
    -- The nearest enclosing `if` before the registration must not be a touch gate.
    local before = init:sub(1, reg)
    local last_if = nil
    for pos, cond in before:gmatch("()if%s+(.-)%s+then") do last_if = cond end
    assert(not (last_if and last_if:find("isTouchDevice")),
        "TapTab sits behind isTouchDevice: Press on a key device cannot switch tabs")
end)

t.done()
