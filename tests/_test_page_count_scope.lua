-- tests/_test_page_count_scope.lua
-- Extract page counts for one folder (GitHub issue 459): "choose the specific
-- folders ... I also just want to sometimes refresh a specific folder with an
-- updated page count." A folder's (or any stack's) long-press menu opens the
-- same dialog, scoped to that stack's books.
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = dofile("tests/_helpers.lua")
local t = H.runner()
local main = io.open("main.lua"):read("*a")
local dlg = io.open("lib/bookshelf_page_count_dialog.lua"):read("*a")
local wid = io.open("lib/bookshelf_widget.lua"):read("*a")

t.test("the scan takes the paths it is handed", function()
    local body = main:match("function Bookshelf:scanPageCounts%(opts%)(.-)\nend\n")
    assert(body, "scanPageCounts moved")
    assert(body:find("local fps = opts.paths or", 1, true), "the scan still walks the whole library")
end)

t.test("a scoped dialog starts the scan on its own books", function()
    assert(dlg:find("if self.scope then opts.paths = self.scope.paths end", 1, true),
        "Start does not pass the scope's paths")
end)

t.test("a scoped dialog does not offer to delete every scanned count", function()
    -- Delete clears the whole library's counts, which is not what a reader
    -- holding one folder expects.
    assert(dlg:find("if not self.scope then", 1, true), "Delete is offered on a scoped dialog")
end)

t.test("the stack menu opens the scoped dialog with the stack's books", function()
    local menu = wid:match("function BookshelfWidget:_openGroupMenu%(group, kind%)(.-)\nend\n")
    assert(menu, "_openGroupMenu moved")
    assert(menu:find('_("Extract page counts\\xE2\\x80\\xA6")', 1, true), "no row in the stack menu")
    assert(menu:find("showScoped(display_name, bw_ref:_resolveStackPaths(group)", 1, true),
        "the row does not scope the dialog to the stack's books")
end)

t.test("the scan holds the device awake, and lets it sleep again on every exit", function()
    -- AutoSuspend reads PluginShare.pause_auto_suspend, not UIManager's standby
    -- count (review finding), so that is the flag that keeps a long scan from
    -- suspending. The value it had before (Keep-alive may have set it) comes back.
    local body = main:match("function Bookshelf:scanPageCounts%(opts%)(.-)\nend\n")
    local hold = body and body:match("local function holdAwake%(on%)(.-)\n    end\n")
    assert(hold, "no holdAwake")
    assert(hold:find("pause_auto_suspend = true", 1, true), "auto-suspend is not paused")
    assert(hold:find("pause_auto_suspend = held_prev", 1, true), "the earlier value is not restored")
    local wrap = body:match("Trapper:wrap%(function%(%)(.*)$")
    local on = wrap:find("holdAwake(true)", 1, true)
    local run = wrap:find("xpcall(function()", 1, true)
    local failed = wrap:find('"bookshelf: page count scan failed:"', 1, true)
    local off = wrap:find("holdAwake(false)", failed or 1, true)
    assert(on and run and on < run, "the device is not held awake before the job runs")
    assert(off and failed and off > failed, "the hold is not released after the job, error path included")
end)

t.test("a scan waiting for an open book lets the device sleep", function()
    local body = main:match("function Bookshelf:scanPageCounts%(opts%)(.-)\nend\n")
    local wait = body:match("(holdAwake%(false%)%s+while Progress%.reading%(%).-holdAwake%(true%))")
    assert(wait, "the reader's session keeps the device awake while the scan waits")
end)

t.done()
