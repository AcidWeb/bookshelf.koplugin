package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t = H.runner()
local src = io.open("lib/bookshelf_ornament_browser.lua"):read("*a")

t.test("the browser has a pick mode", function()
    assert(src:find("function Browser.show(on_change, opts)", 1, true))
    local b = src:match("function Browser:_pick%(item%)(.-)\nend\n")
    assert(b, "no _pick")
    assert(not src:find("is_plank", 1, true), "plank tiles are back in the collection")
    assert(b:find('O().setOff(item.entry.name, false)', 1, true), "a picked off piece stays off")
    assert(b:find('O().setPackOff(item.entry.pack, false)', 1, true), "a picked piece's off pack stays off")
    assert(b:find("self.opts.pick(item.entry)", 1, true))
    assert(b:find("self._close()", 1, true), "picking does not close the browser")
    assert(src:find('self.opts.pick and _("Cancel") or _("Apply")', 1, true), "the pick footer still says Apply")
end)

t.test("the browser's title is the collection, as its settings row", function()
    assert(src:find('title = self.opts.pick and _("Swap for") or _("Ornament collection"),', 1, true),
        "the browser is not titled Ornament collection")
end)

t.done()
