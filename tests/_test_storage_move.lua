-- tests/_test_storage_move.lua
-- Everything bookshelf keeps moves under two folders (maintainer: "back up
-- that folder to back up bookshelf"): what is the reader's own, or dear to
-- rebuild, under settings/bookshelf/; caches under cache/bookshelf/. A move
-- runs once at start-up, before anything opens these files.
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["logger"] = { dbg = function() end, info = function() end,
                             warn = function() end, err = function() end }
local H = dofile("tests/_helpers.lua")
local t, eq = H.runner(), H.eq

local function sh(cmd) local f = io.popen(cmd .. " 2>/dev/null"); local o = f:read("*a"); f:close(); return o end
local function exists(p) return sh("test -e '" .. p .. "' && echo y"):match("y") ~= nil end
local function write(p, body)
    os.execute("mkdir -p \"$(dirname '" .. p .. "')\"")
    local f = io.open(p, "wb"); f:write(body or "x"); f:close()
end
local function read(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

local function setup()
    local root = string.format("%s/bookshelf_move_%d_%d", os.getenv("TMPDIR") or "/tmp", os.time(), math.random(1e6))
    os.execute("rm -rf '" .. root .. "' && mkdir -p '" .. root .. "/settings' '" .. root .. "/cache'")
    package.loaded["datastorage"] = {
        getSettingsDir = function() return root .. "/settings" end,
        getDataDir = function() return root end,
    }
    package.loaded["lib/bookshelf_paths"] = nil
    package.loaded["lib/bookshelf_storage_move"] = nil
    local Move = dofile("lib/bookshelf_storage_move.lua")
    Move._fs = {
        exists = exists,
        isDir = function(p) return sh("test -d '" .. p .. "' && echo y"):match("y") ~= nil end,
        mkdir = function(p) os.execute("mkdir -p '" .. p .. "'"); return true end,
        rename = os.rename,
        list = function(p)
            local out = {}
            for n in sh("ls -A '" .. p .. "'"):gmatch("[^\n]+") do out[#out + 1] = n end
            return out
        end,
        rmdir = function(p) return os.execute("rmdir '" .. p .. "'") end,
    }
    return Move, root
end

t.test("the reader's own files move into settings/bookshelf, caches into cache/bookshelf", function()
    local Move, root = setup()
    local S = root .. "/settings"
    write(S .. "/bookshelf.lua", "prefs"); write(S .. "/bookshelf.lua.old", "prefs-old")
    write(S .. "/bookshelf_micromodules.lua", "mm")
    write(S .. "/bookshelf_hardcover_links.lua", "links")
    write(S .. "/bookshelf_book_facts.sqlite3", "facts"); write(S .. "/bookshelf_book_facts.sqlite3-wal", "w")
    write(S .. "/bookshelf_hardcover.sqlite3", "hc")
    write(S .. "/bookshelf_opds.sqlite3", "opds"); write(S .. "/bookshelf_opds.sqlite3-shm", "s")
    write(S .. "/bookshelf_changelog.lua", "notes")
    write(S .. "/bookshelf_covers/opds/abc/1.img", "img")
    write(S .. "/bookshelf_hardcover/x.jpg", "jpg")
    write(S .. "/bookshelf_cache/bookshelf.koplugin.zip", "zip")
    write(root .. "/cache/bookshelf_covers/k.bsc", "bsc")
    Move.run()
    local B, C = S .. "/bookshelf", root .. "/cache/bookshelf"
    eq(read(B .. "/settings.lua"), "prefs"); eq(read(B .. "/settings.lua.old"), "prefs-old")
    eq(read(B .. "/micromodule_data.lua"), "mm")
    eq(read(B .. "/hardcover_links.lua"), "links")
    eq(read(B .. "/book_facts.sqlite3"), "facts"); eq(read(B .. "/book_facts.sqlite3-wal"), "w", "a database moves with its companions")
    eq(read(B .. "/hardcover.sqlite3"), "hc")
    eq(read(C .. "/opds.sqlite3"), "opds"); eq(read(C .. "/opds.sqlite3-shm"), "s")
    eq(read(C .. "/changelog.lua"), "notes")
    eq(read(C .. "/covers/opds/abc/1.img"), "img", "folders move whole")
    eq(read(C .. "/hardcover/x.jpg"), "jpg")
    eq(read(C .. "/updater/bookshelf.koplugin.zip"), "zip")
    eq(read(C .. "/scaled_covers/k.bsc"), "bsc")
    eq(exists(S .. "/bookshelf.lua"), false, "nothing is left at the old place")
    eq(exists(S .. "/bookshelf_covers"), false)
end)

t.test("a second run changes nothing; a file already at the new place is kept", function()
    local Move, root = setup()
    local S, B = root .. "/settings", root .. "/settings/bookshelf"
    write(B .. "/settings.lua", "new")
    write(S .. "/bookshelf.lua", "old")   -- e.g. an older version ran again after the move
    Move.run(); Move.run()
    eq(read(B .. "/settings.lua"), "new", "the newer file wins")
    eq(read(S .. "/bookshelf.lua"), "old", "and the old one is left alone, not overwritten or deleted")
end)

t.test("a fresh install gets both folders and no stray files", function()
    local Move, root = setup()
    Move.run()
    eq(exists(root .. "/settings/bookshelf"), true); eq(exists(root .. "/cache/bookshelf"), true)
end)

t.test("paths: every store names the new places", function()
    local _Move, root = setup()
    local P = require("lib/bookshelf_paths")
    eq(P.settingsFile("settings.lua"), root .. "/settings/bookshelf/settings.lua")
    eq(P.cacheFile("covers"), root .. "/cache/bookshelf/covers")
    local store = io.open("lib/bookshelf_settings_store.lua"):read("*a")
    assert(store:find('Paths.settingsFile("settings.lua")', 1, true), "the main settings file is not in settings/bookshelf")
    local main = io.open("main.lua"):read("*a")
    local move_at = main:find('require("lib/bookshelf_storage_move").run()', 1, true)
    local store_at = main:find('require("lib/bookshelf_settings_store")', 1, true)
    assert(move_at and store_at and move_at < store_at, "the move must run before the settings store opens its file")
    -- No store builds an old flat path any more.
    for _i, f in ipairs({ "lib/bookshelf_opds_db.lua", "lib/bookshelf_book_facts_db.lua", "lib/bookshelf_hardcover.lua",
                          "lib/bookshelf_cover_fetch.lua", "lib/bookshelf_cover_apply.lua", "lib/bookshelf_opds_covers.lua",
                          "lib/bookshelf_updater.lua", "lib/bookshelf_module_breaker.lua", "lib/bookshelf_changelog.lua",
                          "lib/bookshelf_micromodule_store.lua", "lib/bookshelf_cover_disk_cache.lua" }) do
        local src = io.open(f):read("*a")
        assert(not src:find('getSettingsDir() .. "/bookshelf_', 1, true)
            and not src:find('"/cache/bookshelf_covers"', 1, true)
            and not src:find('new("bookshelf_', 1, true), f .. " still names an old location")
    end
end)

t.test("Delete plugin settings leaves other plugins' files alone", function()
    local main = io.open("main.lua"):read("*a")
    local del = main:match("function Bookshelf:deletePluginSettings%(%)(.-)\nend\n")
    assert(del and not del:find("hardcoversync_settings", 1, true), "it deletes the Hardcover sync plugin's settings")
    assert(del:find("Paths.settingsDir()", 1, true) and del:find("Paths.cacheDir()", 1, true), "it misses the new folders")
end)

t.test("ornaments: the old icons/bookshelf.ornaments folder moves into settings/bookshelf/ornaments", function()
    -- Maintainer: back up settings/bookshelf to back up bookshelf. Every 5.2
    -- reader with ornaments has them in the old folder. A piece is named by its
    -- path inside the folder, so the deck, switched-off pieces and packs carry
    -- over unchanged.
    local Move, root = setup()
    local L = root .. "/icons/bookshelf.ornaments"
    write(L .. "/cactus.svg", "c"); write(L .. "/Japan/wave.png", "w"); write(L .. "/Japan/pack.json", "j")
    Move.run()
    local N = root .. "/settings/bookshelf/ornaments"
    eq(read(N .. "/cactus.svg"), "c")
    eq(read(N .. "/Japan/wave.png"), "w", "a pack moves whole")
    eq(read(N .. "/Japan/pack.json"), "j")
    eq(exists(L), false, "the emptied old folder is left behind")
end)

t.test("ornaments: a piece already in the new folder wins, and its old twin stays", function()
    local Move, root = setup()
    local L, N = root .. "/icons/bookshelf.ornaments", root .. "/settings/bookshelf/ornaments"
    write(N .. "/template.svg", "new"); write(N .. "/ornaments.json", "new-json")
    write(L .. "/template.svg", "old"); write(L .. "/ornaments.json", "old-json"); write(L .. "/leaf.svg", "l")
    write(L .. "/.stfolder/x", "sync")             -- a sync tool's marker stays put
    Move.run(); Move.run()
    eq(read(N .. "/template.svg"), "new"); eq(read(N .. "/ornaments.json"), "new-json")
    eq(read(L .. "/template.svg"), "old", "the old copy was overwritten or deleted")
    eq(read(N .. "/leaf.svg"), "l", "a piece with no twin did not move")
    eq(exists(L .. "/.stfolder/x"), true, "a hidden entry was moved")
    eq(exists(L), true, "a folder still holding things was removed")
end)

t.test("ornaments: no old folder, nothing happens", function()
    local Move, root = setup()
    Move.run()
    eq(exists(root .. "/icons"), false)
end)

t.done()
