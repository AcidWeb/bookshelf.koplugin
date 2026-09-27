-- bookshelf_ornaments.lua
-- Ornaments: user-supplied SVGs that stand in the gaps of a spine shelf, the
-- way a shop dresses a half-empty shelf with a plant or a figurine.
--
-- Deliberately undocumented -- a thing to find. The first spine render creates
-- <KOReader data dir>/icons/bookshelf.ornaments/ holding template.svg (a
-- potted plant, carrying the conventions in its comments) and cactus.svg; both
-- are ordinary ornaments, and any *.svg or *.png dropped beside them joins the
-- pool. The template's comment block is the whole documentation, so anything
-- a reader needs to know has to end up in there.
-- The template is written only when the folder is first created -- a user who
-- deletes the plant keeps it deleted.
--
-- INSIDE icons/ on purpose. That is KOReader's own user-asset directory (see
-- iconwidget.lua, which prepends <data dir>/icons to its search path), so it
-- is where a reader already goes to manage SVGs of their own. A
-- bookshelf.ornaments/ folder in the root of KOReader's storage would be one
-- plugin helping itself to the top level (maintainer ruling). Still namespaced
-- by the folder name, so it cannot collide with an icon a reader drops in, and
-- still outside plugins/, so a plugin update never touches it.
--
-- Conventions the SVG follows (also in the template): the bottom of the
-- viewBox is the plank surface the ornament stands on; a comment
-- "bookshelf:overhang=N" declares that the lowest N viewBox units hang below
-- the surface, over the plank's front (a paw, a trailing vine). Rendering is
-- KOReader's own RenderImage (nanosvg), so: bold solid shapes, no text, no
-- filters, no masks. Night mode pre-inverts the bitmap, alpha kept.
--
-- A PNG carries the same directives as tEXt chunks (keyword "bookshelf",
-- text "overhang=N" / "hang" / "night=invert"), N in the image's own pixels;
-- aspect comes from the IHDR chunk and the night flag may also come from the
-- filename (cat.invert.png). See parsePngHeader. Nothing else about the
-- pipeline differs -- same pick(), same cache, same widget -- because the only
-- thing that actually varies is how an entry is measured and which RenderImage
-- call draws it.
--
-- "bookshelf:hang" (either format): the piece HANGS from the shelf above
-- instead of standing on its own -- a bat, a spider on its thread. Its top
-- meets the underside of the plank above, so it is only offered where there is
-- one: row ends and bare planks from a page's second row down, never the
-- section gaps (those are chosen before rows exist). See pick()'s o.no_hang.
--
-- Placement is deterministic per page composition (seeded by the row's first
-- book and its index range), so an ornament stays put while a page is looked
-- at and changes across pages; about half the eligible gaps stay empty.

local logger = require("logger")
local Widget = require("ui/widget/widget")

local M = {}

-- THE FOLDERS. Since v5.3 the ornaments live beside the wallpapers, in
-- koreader/settings/bookshelf/ornaments, so one folder backs up (or moves to
-- another device) everything Bookshelf (maintainer). Until then they lived in
-- koreader/icons/bookshelf.ornaments, which is still read and never moved or
-- created; where both hold the same file, the new folder's copy wins. The
-- help, the browser and the README name only the new one.
M.NEW_PARENT    = "bookshelf"
M.NEW_SUBDIR    = "ornaments"
-- The old one. KOReader does not create icons/ itself.
M.PARENT        = "icons"
M.SUBDIR        = "bookshelf.ornaments"
M.TEMPLATE_NAME = "template.svg"
M.MIN_GAP_DP    = 48     -- a gap narrower than this stays empty
M.MIN_H_DP      = 28     -- and an ornament that would come out smaller isn't placed
M.MIN_H_FRAC    = 0.45   -- ...nor one shrunk (to fit a narrow gap) below this share
                         -- of the books' height: ornaments scale with the shelf,
                         -- a speck beside tall books looked wrong (user report)
M.HEIGHT_FRAC   = 0.8    -- height as a fraction of the books' stand height
-- THE ROW END, where width is the scarce thing and height is not.
--
-- The slot used to be a stand-height SQUARE. Anything wider than that was
-- shrunk to fit and, once the shrinking took it under MIN_H_FRAC, dropped --
-- so a broad ornament simply never appeared, and nothing on screen said why
-- (maintainer: "users will wonder why their ornament never appears if it's
-- just over some hidden limit"). The square is not a rule anybody chose; it
-- is just what falls out of using the height for the width too.
--
-- There is no ceiling here worth the name. An ornament that spans the shelf
-- is a decoration somebody drew that way, and the row it stands on carries no
-- books rather than squeezing one in beside it: "I have no issue with a png
-- taking a full shelf, we don't always need to have a book" (maintainer).
--
-- What the row does hold back is one book's width, measured on the widest
-- thing a row can hold -- a face-out cover. Without it a row is FORCED to
-- seat a book (SpineLayout.fillRows seats at least one), and with only a
-- sliver left that book gets painted past the end of the plank, which is what
-- the device showed. The slot itself is worked out in bookshelf_spine_shelf.
-- The widest a piece stands by default, anywhere: its stand height, in book
-- heights (ASIDE_STANDS). A wider piece is scaled down to it, never left out.
-- Measured against the BOOKS, not the row, so taller rows (fewer of them)
-- grow the ornaments with the books: it was a quarter of the row, which stayed
-- the same width while the books grew around it (maintainer). At the PW5's two
-- rows the two agree (280px against 284px). Only a reader's own size nudge
-- takes a piece past it, up to the whole row.
M.ASIDE_STANDS  = 1.0
function M.maxWidth(stand_h, row_w)
    return math.max(0, math.min(row_w or 0, math.floor((stand_h or 0) * M.ASIDE_STANDS)))
end
-- ...and a piece that spreads across a row-end slot may stand shorter than
-- one wedged into a gap between books. There is nothing above a row end to
-- crowd, so a low wide piece reads as an ornament rather than as a mistake,
-- where the same piece squeezed between two spines would not.
M.ROW_END_MIN_H_FRAC = 0.3
M.CHANCE        = 0.5    -- fraction of eligible gaps that get an ornament
M.GROUP_CHANCE  = 0.08   -- ...and of the gaps BETWEEN sections on a grouping
                         -- chip, which are far more numerous: the same odds
                         -- there would put a plant between every other series
M.CACHE_MAX     = 12     -- rendered bitmaps kept (path x size x night)

-- ── Frequency ──────────────────────────────────────────────────────
--
-- A MULTIPLIER on the odds above, not a replacement for them. The two base
-- chances are deliberately far apart -- a grouping chip's section breaks are
-- far more numerous than the gaps on a plain shelf, so identical odds would
-- put a plant between every other series -- and that relationship should hold
-- at every setting. Scaling both keeps it.
-- The PER-SHELF key: a chip carries its own number in its tab record. There
-- is deliberately no library-wide setting behind it. A default that every
-- shelf can override is a trap -- change the default later and nothing
-- happens, because by then every shelf has a value of its own (maintainer).
-- A shelf that has never been touched holds nothing and gets FREQ_DEFAULT.
M.FREQ_SETTING  = "ornament_frequency"
M.FREQ_DEFAULT  = 1

-- Above this, ornaments stop waiting for a gap wide enough and have a place
-- RESERVED at the end of each shelf (see SpineShelf.plan). Below it they are
-- opportunistic, which is what "occasional" has always meant here.
M.FREQ_RESERVE_AT = 1.5
-- The odds a RESERVED row end (see SpineShelf.plan) actually takes a piece,
-- before pick() scales them by the level: Often (2) keeps about half its
-- row ends, Lots (3) about five in six. Maintainer: "allow some rows even on
-- 'lots' setting to be occasionally filled with books". A row that rolls
-- nothing gives nothing up, so the odd bookless row costs no shelf.
M.ROW_END_CHANCE = 0.28

-- Odds that survive pick()'s scaling by the level, for the one placement that
-- is a promise rather than a roll. A plain 1 would not do: pick multiplies by
-- the frequency, so at Rarely a "certainty" of 1 comes back out as 0.5.
M.CHANCE_CERTAIN = math.huge

-- ── The group channel has its own curve ───────────────────────────────────
--
-- One level scales every channel, but the channels do not offer the same
-- NUMBER of chances. A plain shelf offers a couple of row ends per page; a
-- grouping chip can offer thirty section breaks. Multiplying both by the same
-- number gives the two complaints that arrived one after the other: nothing
-- at all on a packed plain shelf, and "set ornaments to rarely appear and I
-- have 4 on screen right now" on a chip full of small groups.
--
-- So the section-break channel is damped at the lower levels rather than
-- following the level directly. Per gap, and across a page holding thirty of
-- them:
--
--     level        per gap    expected on such a page
--     Rarely        1.6%              0.5
--     Often         5.6%              1.7
--     Always       16.0%              4.8
--
-- Not a per-screen CAP, which is what this wanted to be: the section-break
-- placement widens the gap it stands in, so it changes how many books fit,
-- and a cap counted per screen would give plan()'s two callers different
-- answers and break page boundaries again (see pageGuaranteed). A curve is a
-- pure function of the level, so both passes still agree.
M.GROUP_LEVEL = { [0] = 0, [0.5] = 0, [1] = 0.7, [2] = 2 }

-- The row end gets a curve too, and for the same reason: it is the channel
-- that was actually doing the work on a grouped chip (instrumented: six
-- placements at 0.28 against one section break at 0.08), so damping the
-- section breaks alone left Rarely at "9 ornaments across 11 pages... often 2
-- on a page", which is not rare.
--
-- ZERO at Rarely. That setting is then exactly its promise -- one page in
-- four stands a piece, and no other channel adds to it -- which is both rare
-- and predictable. Everything above it keeps a roll on top of the promise.
M.ROW_END_LEVEL = { [0] = 0, [0.5] = 0, [1] = 0.7, [2] = 2 }

local function levelFrom(curve)
    local f = M.frequency()
    local best, dist = 0, math.huge
    for level, mul in pairs(curve) do
        local d = math.abs(level - f)
        if d < dist then best, dist = mul, d end
    end
    return best
end

function M.rowEndLevel() return levelFrom(M.ROW_END_LEVEL) end

-- ── A ceiling for the channels that can have one ──────────────────────────
--
-- The curve above thins the section breaks, but the other channels keep
-- adding: the promised row end, the odd row end that rolls one anyway, the
-- leftover slack beside a short row. Measured on a grouped chip at Rarely
-- that came to about two a page, which is not what "rarely" promises.
--
-- So the channels that do NOT affect packing take a hard per-screen ceiling,
-- counting everything already standing (a section-break piece is placed
-- earlier, in plan, and counts against it). Only those channels: the
-- section-break piece widens the gap it stands in, so capping it would give
-- plan()'s two callers different answers and break page boundaries -- the
-- constraint that also ruled out a cap for the group channel.
M.PAGE_BUDGET = { [0] = 0, [0.5] = 1, [1] = 2, [2] = 4 }

function M.pageBudget()
    local f = M.frequency()
    local best, dist = 0, math.huge
    for level, n in pairs(M.PAGE_BUDGET) do
        local d = math.abs(level - f)
        if d < dist then best, dist = n, d end
    end
    return best
end

-- budgetLeft() -> how many more a screen may take, for budgeted channels.
function M.budgetLeft()
    local n = 0
    for _k in pairs(M._used) do n = n + 1 end
    return M.pageBudget() - n
end

function M.groupLevel() return levelFrom(M.GROUP_LEVEL) end

-- ── The per-PAGE promise ──────────────────────────────────────────────────
--
-- Every other placement is opportunistic: a piece appears where a gap happens
-- to be wide enough. On a plain shelf that can mean almost never. A shelf with
-- no groups has no section breaks at all -- the default Home shelf, flattened
-- folders, is exactly that -- and a densely packed row leaves a few dozen
-- pixels at its end, under MIN_GAP_DP. Both channels empty, at every level
-- below the top one: "set to often, there was only one ornament in total on
-- the whole shelf" (maintainer).
--
-- So a level also says how often a PAGE is promised a piece, and a promised
-- page stands one at a row end whether or not a gap turned up. One page in N:
M.PAGE_PERIOD = { [0] = 0, [0.5] = 4, [1] = 2, [2] = 1 }

function M.pagePeriod()
    local f = M.frequency()
    local best, dist = 0, math.huge
    for level, period in pairs(M.PAGE_PERIOD) do
        local d = math.abs(level - f)
        if d < dist then best, dist = period, d end
    end
    return best
end

-- pageGuaranteed(page) -> is THIS page promised a piece?
--
-- Hashed from the page's ORDINAL, not from its books. The ordinal is the one
-- thing both of plan()'s callers agree on: the render knows it, and the
-- pagination pass derives it from the row index. Seeding on anything else --
-- the page's first book, say -- gives the two passes different answers, and
-- they then pack differently and disagree about where pages start.
function M.pageGuaranteed(page)
    local period = M.pagePeriod()
    if period <= 0 then return false end
    if period == 1 then return true end
    return (M.hash("page:" .. tostring(page)) % period) == 0
end

-- The shelf on screen may pin its own frequency, so the value is pushed in
-- rather than read from the library setting alone: a chip's pin is resolved
-- against the global by the widget (BookshelfWidget:_chipListValue) and handed
-- over before anything is built, the same way the spine renderer is told about
-- the ground. nil means nobody pinned anything and the library setting stands.
M._chip_frequency = nil
function M.setChipFrequency(v)
    M._chip_frequency = (type(v) == "number" and v >= 0) and v or nil
end

function M.frequency()
    local pinned = M._chip_frequency
    if type(pinned) ~= "number" or pinned < 0 then return M.FREQ_DEFAULT end
    if pinned > 4 then return 4 end
    return pinned
end

-- ── One of each, per screen ───────────────────────────────────────
--
-- Placements are seeded independently -- a section break knows the two books
-- either side of it, a row end knows its row -- so nothing stopped two of them
-- landing on the same file. With a folder of three that is not unlikely; it
-- reads as a mistake rather than as decoration, which is the maintainer's
-- report.
--
-- A set rather than a counter: the question is only "is this one already
-- standing on this screen", and when every entry is spoken for a repeat still
-- beats a blank gap.
M._used = {}

-- beginScreen() -- forget what is standing, for a screen about to be built.
-- Called from SpineShelf.plan, which runs once per page and before any row.
function M.beginScreen()
    M._used = {}
end

-- reservesRowEnds() -> should a shelf keep a slot free at its end?
function M.reservesRowEnds()
    return M.frequency() >= M.FREQ_RESERVE_AT
end


M.TEMPLATE_SVG = [==[<?xml version="1.0" encoding="UTF-8"?>
<!-- bookshelf:seed=4 -->
<!--
  Bookshelf ornaments.

  Drop SVG or PNG files in this folder and they turn up now and then in the
  gaps on the spine shelf, standing on the plank like the books. This file is
  one: a potted plant (cactus.svg beside it is another). Copy it under a new
  name as a starting point, or delete either if you'd rather not see it;
  they won't come back. These two files are Bookshelf's own: when a release
  improves them they are rewritten in place, so an edit to one of them under
  its own name will not survive that.

  A PNG is the quick way in: any picture with a transparent background will
  do, and it stands on the plank at whatever shape it already is. It cannot
  hang over the front of the plank the way the drawing below can, and it is
  scaled to the shelf's height, so start from something reasonably large or
  it will look soft. To have a PNG shown light on a grey screen in night
  mode, put .invert before the extension: cat.invert.png.

  The rest of this file is about SVGs, which can do more.

  The rules of the shelf:

  - The BOTTOM of the viewBox is the plank's front edge. The books stand a
    little way back from it, so the two pieces here leave the last six
    units empty: that space is what sets them back onto the plank beside
    the books rather than on its lip. Leave nothing else floating below
    your last shape.
  - To hang over the front of the plank (a tail, a paw, a trailing vine),
    set the overhang line below to the number of viewBox units that should
    hang below the surface, and draw that part at the bottom.
  - The shelf is seen from slightly above (about 12 degrees), so anything
    with a top (a pot, a box, a cup) shows its opening as a shallow
    ellipse about a fifth as tall as it is wide. Match that and it belongs.
  - Use colour. Colour screens show it as drawn; grey e-ink shows it as
    shades of grey, so keep the tones fairly dark and distinct from each
    other, or it turns to mush. Bold, solid shapes read best. No text, no
    filters, no masks: the renderer is small and they will not show.
    Transparent background, so the shelf shows through.
  - An .svg has to be a DRAWING, not a picture. Converters asked to turn a
    photo into an SVG usually just wrap the photo inside it, and the
    renderer draws no pictures, so the file looks right and comes out
    blank. If you started from a picture, save it as a .png and drop that
    in instead: there is nothing to convert.
  - Height follows the shelf; width follows your aspect ratio. Aim for
    something about as tall as a book and no wider than two or three.
  - Night mode: colour screens always show your colours as drawn, and so
    does a grey e-ink screen here: the shelf turns black and these two
    pieces keep their tones, which still read against it. A plain dark
    silhouette would sink into that black, so for one of those add a line
    above the svg tag in the form of the overhang line, with night=invert
    in place of overhang=0: it is then shown light, like the spine titles.
  - Something that HANGS (a bat, a spider on its thread): add a line in the
    same form with hang in place of overhang=0, and draw it with its top at
    the top of the picture. It hangs from the shelf above instead of
    standing, so it only turns up from the second shelf down.
  - A .png can carry these too, as text chunks with the keyword bookshelf
    (overhang=N in the picture's own pixels, hang, night=invert).
-->
<!-- bookshelf:overhang=0 -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 106">
  <!-- A slight dark outline on every shape: over a wallpaper a flat fill
       sinks into the picture; the line is what keeps the piece an object. -->
  <path d="M12 70 H48 L43 97 A13 2.8 0 0 1 17 97 Z" fill="#a4512c" stroke="#4a2a17" stroke-width="1.2" stroke-linejoin="round"/>
  <ellipse cx="30" cy="68" rx="19" ry="4" fill="#3a2114"/>
  <path d="M30 70 C22 54 8 50 6 36 C20 36 30 46 30 70 Z" fill="#3f8a45" stroke="#1f3a22" stroke-width="1.2" stroke-linejoin="round"/>
  <path d="M30 70 C38 52 52 48 54 32 C40 34 30 46 30 70 Z" fill="#2f7237" stroke="#1f3a22" stroke-width="1.2" stroke-linejoin="round"/>
  <path d="M30 70 C28 48 30 30 30 12 C34 30 34 50 30 70 Z" fill="#245a2b" stroke="#1f3a22" stroke-width="1.2" stroke-linejoin="round"/>
  <path d="M11 68 A19 4 0 0 0 49 68 V72 A19 4 0 0 1 11 72 Z" fill="#c8693d" stroke="#4a2a17" stroke-width="1.2" stroke-linejoin="round"/>
</svg>
]==]

M.CACTUS_NAME = "cactus.svg"
M.CACTUS_SVG = [==[<?xml version="1.0" encoding="UTF-8"?>
<!-- bookshelf:seed=4 -->
<!-- A cactus, in the same pot as the plant. See template.svg for the rules. -->
<!-- bookshelf:overhang=0 -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 106">
  <path d="M14 74 H46 L42 97 A12 2.6 0 0 1 18 97 Z" fill="#a4512c" stroke="#4a2a17" stroke-width="1.2" stroke-linejoin="round"/>
  <ellipse cx="30" cy="72" rx="17" ry="3.6" fill="#3a2114"/>
  <!-- The arms are thick round-capped strokes, so their outline is the same
       path drawn wider and darker underneath; the body is drawn over the
       joins so the outline does not cross it. -->
  <path d="M30 56 H19 A5 5 0 0 1 14 51 V36" stroke="#1f3a22" stroke-width="10.4" stroke-linecap="round" fill="none"/>
  <path d="M30 44 H41 A5 5 0 0 0 46 39 V28" stroke="#1f3a22" stroke-width="10.4" stroke-linecap="round" fill="none"/>
  <rect x="24" y="18" width="12" height="56" rx="6" fill="#3f8a45" stroke="#1f3a22" stroke-width="1.2"/>
  <path d="M30 56 H19 A5 5 0 0 1 14 51 V36" stroke="#3f8a45" stroke-width="8" stroke-linecap="round" fill="none"/>
  <path d="M30 44 H41 A5 5 0 0 0 46 39 V28" stroke="#3f8a45" stroke-width="8" stroke-linecap="round" fill="none"/>
  <path d="M27 26 l-3 -2 M33 26 l3 -2 M27 40 l-3 -2 M33 40 l3 -2 M27 64 l-3 -2 M33 64 l3 -2 M12 42 l-3 -1 M48 34 l3 -1" stroke="#f3e9b8" stroke-width="1.2" fill="none"/>
  <path d="M13 72 A17 3.6 0 0 0 47 72 V76 A17 3.6 0 0 1 13 76 Z" fill="#c8693d" stroke="#4a2a17" stroke-width="1.2" stroke-linejoin="round"/>
</svg>
]==]

-- Written when the folder is first created: the template (a plant) and a
-- cactus. Both are ordinary ornaments; deleting either sticks.
-- The seeds carry "bookshelf:seed=N". A seed file that exists with an older
-- marker (or none: the first release had none) is ours and out of date, and
-- ensureTemplate rewrites it in place; one at the current version is left
-- alone; a deleted one stays deleted, and no other file is looked at.
M.SEED_VERSION = 4
function M.seedVersionOf(text)
    local v = type(text) == "string" and text:match("bookshelf:seed=(%d+)")
    return tonumber(v) or 0
end

M.SEED_FILES = {
    { name = M.TEMPLATE_NAME, svg = M.TEMPLATE_SVG },
    { name = M.CACTUS_NAME,   svg = M.CACTUS_SVG },
}

-- ── Seams (tests replace these) ─────────────────────────────────────────────
M._data_dir = nil          -- override for the data dir
M._lfs      = nil          -- lazily required
M._render   = nil          -- function(path, w, h) -> bb, default RenderImage
M._size     = nil          -- function(path) -> w, h, default nanosvg getSize
M._has_color = nil         -- override for Device:hasColorScreen()

function M.hasColorScreen()
    if M._has_color ~= nil then return M._has_color end
    local ok, Device = pcall(require, "device")
    if ok and Device and Device.hasColorScreen then
        local ok2, v = pcall(Device.hasColorScreen, Device)
        return ok2 and v or false
    end
    return false
end

local function lfs()
    if not M._lfs then
        local ok, mod = pcall(require, "libs/libkoreader-lfs")
        M._lfs = ok and mod or false
    end
    return M._lfs or nil
end

function M.dataDir()
    if M._data_dir then return M._data_dir end
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage and DataStorage.getDataDir then
        local ok2, d = pcall(DataStorage.getDataDir, DataStorage)
        if ok2 and type(d) == "string" and d ~= "" then return d end
    end
    return nil
end

-- settingsDir(): KOReader's settings folder (koreader/settings). A test that
-- names a data folder gets the settings folder inside it, as KOReader has it.
function M.settingsDir()
    if M._settings_dir then return M._settings_dir end
    if M._data_dir then return M._data_dir .. "/settings" end
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage and DataStorage.getSettingsDir then
        local ok2, d = pcall(DataStorage.getSettingsDir, DataStorage)
        if ok2 and type(d) == "string" and d ~= "" then return d end
    end
    local d = M.dataDir()
    return d and (d .. "/settings") or nil
end

-- dir(): the ornaments folder, the one to tell people about.
function M.dir()
    local s = M.settingsDir()
    return s and (s .. "/" .. M.NEW_PARENT .. "/" .. M.NEW_SUBDIR) or nil
end

-- legacyDir(): where they lived before v5.3; read, never created.
function M.parentDir()
    local d = M.dataDir()
    return d and (d .. "/" .. M.PARENT) or nil
end
function M.legacyDir()
    local p = M.parentDir()
    return p and (p .. "/" .. M.SUBDIR) or nil
end

-- roots() -> the folders that exist, the new one first.
function M.roots()
    local fs = lfs()
    local out = {}
    if not fs then return out end
    for _i, d in ipairs({ M.dir(), M.legacyDir() }) do
        if d and fs.attributes(d, "mode") == "directory" then out[#out + 1] = d end
    end
    return out
end

-- packDir(pack) -> the folder a pack lives in (the new one if both have it).
function M.packDir(pack)
    local fs = lfs()
    if not (fs and pack) then return nil end
    for _i, r in ipairs(M.roots()) do
        local p = r .. "/" .. pack
        if fs.attributes(p, "mode") == "directory" then return p end
    end
    return nil
end

-- refreshSeeds(d, fs): rewrite OUR seed files where they exist at an older
-- version. Reads only the head of each; never creates, never touches a file
-- under another name.
local function refreshSeeds(d, fs)
    for _i, seed in ipairs(M.SEED_FILES) do
        local path = d .. "/" .. seed.name
        if fs.attributes(path, "mode") == "file" then
            local f = io.open(path, "rb")
            local head = f and f:read(8192) or nil   -- the template's doc comment is long
            if f then f:close() end
            if head and M.seedVersionOf(head) < M.SEED_VERSION then
                local w = io.open(path, "w")
                if w then
                    w:write(seed.svg); w:close()
                    logger.dbg("[bookshelf] ornament seed refreshed:", seed.name)
                end
            end
        end
    end
end

-- ensureTemplate(): create the folder with the seeds in it, ONCE, when the
-- folder does not exist yet. An existing folder is left as the reader has it
-- -- a deleted seed stays deleted, their own files are never read -- with one
-- exception: a seed of OURS still present at an older version is rewritten
-- (refreshSeeds), so improvements to the artwork reach existing installs.
--
-- The new folder is always made, so the path the browser and the help show
-- exists; the seeds go into it only on a fresh install. A reader with the old
-- folder already has theirs there, and a second template would be a stray.
M._ensured = false
function M.ensureTemplate()
    if M._ensured then return end
    M._ensured = true
    local d = M.dir()
    local fs = lfs()
    if not (d and fs) then return end
    local old = M.legacyDir()
    local has_old = old and fs.attributes(old, "mode") == "directory"
    if has_old then pcall(refreshSeeds, old, fs) end
    if fs.attributes(d, "mode") ~= nil then
        pcall(refreshSeeds, d, fs)
        return
    end
    -- settings/ exists wherever KOReader runs; bookshelf/ may not yet.
    -- mkdir is not recursive, so a level at a time.
    local settings = M.settingsDir()
    local parent = settings and (settings .. "/" .. M.NEW_PARENT)
    for _i, p in ipairs({ settings, parent }) do
        if p and fs.attributes(p, "mode") == nil then
            pcall(fs.mkdir, p)
            if fs.attributes(p, "mode") ~= "directory" then return end
        end
    end
    local ok_mk = pcall(fs.mkdir, d)
    if not ok_mk or fs.attributes(d, "mode") ~= "directory" then return end
    if has_old then
        logger.dbg("[bookshelf] ornaments folder created (the old one stays in use too):", d)
        return
    end
    for _i, seed in ipairs(M.SEED_FILES) do
        local f = io.open(d .. "/" .. seed.name, "w")
        if f then f:write(seed.svg); f:close() end
    end
    logger.dbg("[bookshelf] ornaments folder created:", d)
end

-- parseHeader(text) -> aspect (w/h) or nil, overhang fraction (0..1),
-- night_invert (bool), hang (bool). Reads the viewBox and the "bookshelf:..." comments
-- from the SVG text; no XML parser, the facts are plain patterns.
function M.parseHeader(text)
    if type(text) ~= "string" then return nil, 0 end
    -- Separator is [%s,]+, not %s+: the spec allows the four viewBox numbers to
    -- be split by whitespace AND/OR a comma, and plenty of exporters write
    -- "0,0,60,100". Insisting on spaces dropped those files from the pool with
    -- no warning, which reads to a user as "my ornaments don't show up".
    local NUM = "([%-%d%.]+)"
    local SEP = "[%s,]+"
    local vb_pat = 'viewBox%s*=%s*["\']%s*' .. NUM .. SEP .. NUM .. SEP .. NUM .. SEP .. NUM
    local w, h
    local _x, _y, sw, sh = text:match(vb_pat)
    if sw then w, h = tonumber(sw), tonumber(sh) end
    if not (w and h and w > 0 and h > 0) then
        -- No usable viewBox: fall back to the <svg> tag's own width/height.
        -- nanosvg rasterises those perfectly well, so refusing them cost us
        -- files that would have rendered. Scoped to the opening tag so a
        -- child's stroke-width cannot size an ornament off a line weight, and
        -- the numeric prefix is taken so units ("60mm") work -- aspect is a
        -- ratio, so a shared unit cancels.
        --
        -- The viewBox still wins when present: it is the coordinate system the
        -- bookshelf:overhang convention is measured in.
        local tag = text:match("<svg(.-)>")
        if tag then
            local tw = tonumber(tag:match('%swidth%s*=%s*["\']%s*([%d%.]+)'))
            local th = tonumber(tag:match('%sheight%s*=%s*["\']%s*([%d%.]+)'))
            if tw and th and tw > 0 and th > 0 then w, h = tw, th end
        end
    end
    if not (w and h and w > 0 and h > 0) then return nil, 0 end
    local over = tonumber(text:match("bookshelf:overhang%s*=%s*([%d%.]+)")) or 0
    if over < 0 then over = 0 end
    if over > h then over = h end
    -- "bookshelf:night=invert": a silhouette that should turn light in night
    -- mode, like the spine titles, instead of keeping its colours the way a
    -- cover does. Default is faithful (colour artwork stays the right colour).
    local night_invert = text:match("bookshelf:night%s*=%s*invert") ~= nil
    return w / h, over / h, night_invert, M.declaresHang(text)
end

-- declaresHang(text) -> bool: "bookshelf:hang", on its own or as "=1"/"=yes".
function M.declaresHang(text)
    if type(text) ~= "string" then return false end
    local v = text:match("bookshelf:hang%s*=%s*(%w+)")
    if v then return v ~= "0" and v ~= "no" and v ~= "false" end
    return text:match("bookshelf:hang%f[^%w]") ~= nil
end

-- be32(s, i) -> the big-endian uint32 starting at byte i, or nil if short.
local function be32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    if not d then return nil end
    return ((a * 256 + b) * 256 + c) * 256 + d
end

-- parsePngHeader(bytes) -> aspect (w/h) or nil, overhang fraction, night_invert,
-- hang
--
-- The same contract as parseHeader, for a raster. Everything comes out of the
-- IHDR chunk, which a valid PNG is required to put first: the 8-byte
-- signature, then the chunk length and the tag "IHDR", then width and height
-- as big-endian uint32. So 24 bytes settle it and nothing is decoded to list a
-- folder -- which matters, because list() runs on every folder mtime change
-- and a decode is orders of magnitude dearer than a read.
--
-- DIRECTIVES come from tEXt chunks before the image data: keyword "bookshelf",
-- text "overhang=N", "hang" or "night=invert" (one per chunk, or several in
-- one separated by spaces or semicolons). N is in the image's own pixels, the
-- raster's equivalent of an SVG's viewBox units. A PNG with none -- a picture
-- someone had -- stands on the plank as it always did: overhang 0, not
-- hanging. The ornament packs write them (the leaves under an apple basket
-- hanging over the plank front, a contact shadow reaching onto it, a bat).
--
-- Only chunks inside `bytes` are seen (list() reads 8KB, and a tool that puts
-- its tEXt after the image data is not supported -- the pack builder writes
-- them straight after IHDR). The filename night flag (cat.invert.png) is
-- applied by the caller on top of whatever this returns.
function M.parsePngHeader(bytes)
    if type(bytes) ~= "string" or #bytes < 24 then return nil end
    if bytes:sub(1, 8) ~= "\137PNG\r\n\026\n" then return nil end
    -- Refuse a file whose first chunk is not IHDR rather than hunting for it:
    -- that file is malformed, and reading on would take whatever bytes came
    -- next as a size.
    if bytes:sub(13, 16) ~= "IHDR" then return nil end
    local w, h = be32(bytes, 17), be32(bytes, 21)
    if not (w and h) or w <= 0 or h <= 0 then return nil end
    local text = M.pngDirectives(bytes)
    local over = tonumber(text:match("bookshelf:overhang%s*=%s*([%d%.]+)")) or 0
    if over < 0 then over = 0 end
    if over > h then over = h end
    local night = text:match("bookshelf:night%s*=%s*invert") ~= nil
    return w / h, over / h, night, M.declaresHang(text)
end

-- pngDirectives(bytes) -> "bookshelf:<directive>" lines from the "bookshelf"
-- tEXt chunks ahead of the image data, or "". Walks the chunk list from the
-- one after IHDR; stops at IDAT/IEND, at a chunk that runs past `bytes`, or at
-- a length no real header chunk has.
function M.pngDirectives(bytes)
    local out = {}
    local pos = 9                                   -- first chunk, 1-based
    while pos + 8 <= #bytes do
        local len, typ = be32(bytes, pos), bytes:sub(pos + 4, pos + 7)
        if not len or len > 65536 or typ == "IDAT" or typ == "IEND" then break end
        if pos + 11 + len > #bytes + 4 then break end
        if typ == "tEXt" then
            local data = bytes:sub(pos + 8, pos + 7 + len)
            local z = data:find("\0", 1, true)
            if z and data:sub(1, z - 1) == "bookshelf" then
                for d in data:sub(z + 1):gmatch("[^;%s]+") do
                    out[#out + 1] = "bookshelf:" .. d
                end
            end
        end
        pos = pos + 12 + len                        -- length, type, data, crc
    end
    return table.concat(out, "\n")
end

-- The folder's cache key. Why it is not just an mtime -- a delete that does
-- not move the mtime on the Kindle's fuse.fsp mount, and whole-second
-- granularity swallowing a same-tick addition -- is written up in
-- lib/bookshelf_asset_folder.lua, which the wallpapers folder shares.
local AssetFolder = require("lib/bookshelf_asset_folder")
local ORNAMENT_EXTS = AssetFolder.extsFromList({ "svg", "png" })

-- list() -> { {path, name, aspect, overhang}, ... } sorted by name. Re-read
-- when the folder's contents or mtime change, else served from the session
-- cache (the same table, so callers may compare identity).
M._list_cache = nil
M._list_key   = nil
-- Seconds between folder scans. A scan is a directory listing plus a stat,
-- and list() is asked once per spine plan, which runs up to three times per
-- rebuild; on a tired Kindle's FUSE userstore a listing was measured at
-- 340ms. Within the TTL the last answer stands, so a file added or removed
-- shows up within this many seconds rather than on the very next paint.
-- Zero disables the limit (the tests set it so).
M.SCAN_TTL = 15
M._clock   = os.time

-- ── Packs, and switching ornaments off ──────────────────────────────────────
--
-- A PACK is a subfolder of the ornaments folder: a set someone made (autumn,
-- a cat collection) that is switched on and off as one. Files at the top
-- level are the reader's own loose ones and belong to no pack. One level
-- deep only: a pack is a folder of pictures, not a tree.
--
-- An ornament or a pack can be switched off without deleting it (the
-- ornaments browser, lib/bookshelf_ornament_browser). Both are remembered by
-- their path relative to the folder -- "cactus.svg", "Autumn/leaf.svg" -- so
-- a file of the same name in two packs is two ornaments.
M.OFF_KEY       = "ornaments_off"        -- { [relpath] = true }
M.PACKS_OFF_KEY = "ornament_packs_off"   -- { [pack]    = true }
M._store = nil   -- seam: { read = fn(k), save = fn(k, v), generation = fn() }

local function store()
    if M._store then return M._store end
    local ok, Store = pcall(require, "lib/bookshelf_settings_store")
    return ok and Store or nil
end

local function readSet(key)
    local st = store()
    local ok, v = pcall(function() return st and st.read(key) end)
    return (ok and type(v) == "table") and v or {}
end

-- While the ornaments browser is open (beginDeferred .. endDeferred), switches
-- are written in memory only and flushed once at the end: a save flushes the
-- whole settings file, and a reader tapping through a pack paid that per tap.
M._defer = false
function M.beginDeferred() M._defer = true end
function M.endDeferred()
    M._defer = false
    local st = store()
    if st and st.flush then pcall(st.flush) end
end

local function saveSet(key, set)
    local st = store()
    if not st then return end
    local v = (next(set) ~= nil) and set or nil
    if M._defer and st.saveDeferred then
        pcall(function() st.saveDeferred(key, v) end)
    else
        pcall(function() st.save(key, v) end)
    end
    M._list_cache, M._list_key = nil, nil   -- the next list() re-filters
end

function M.isOff(relpath) return readSet(M.OFF_KEY)[relpath] == true end
function M.isPackOff(pack) return pack ~= nil and readSet(M.PACKS_OFF_KEY)[pack] == true end

function M.setOff(relpath, off)
    local set = readSet(M.OFF_KEY)
    set[relpath] = off and true or nil
    saveSet(M.OFF_KEY, set)
end

function M.setPackOff(pack, off)
    if not pack then return end
    local set = readSet(M.PACKS_OFF_KEY)
    set[pack] = off and true or nil
    saveSet(M.PACKS_OFF_KEY, set)
end

-- entryFor(path, relpath, file, pack) -> an ornament entry, or nil when the
-- file cannot be sized (logged, so "my ornament doesn't show" is answerable).
local function entryFor(path, relpath, file, pack)
    local lname = file:lower()
    local is_png = lname:match("%.png$") ~= nil
    if not (is_png or lname:match("%.svg$")) then return nil end
    -- "rb": a PNG's header is binary, and a text-mode read is only the same
    -- thing by POSIX's good grace.
    local f = io.open(path, "rb")
    if not f then return nil end
    local head = f:read(8192)
    f:close()
    local aspect, over, night_invert, hang
    if is_png then
        aspect, over, night_invert, hang = M.parsePngHeader(head)
        -- The name can carry the night flag too: cat.invert.png, the one
        -- channel that needs no tooling.
        night_invert = night_invert or lname:match("%.invert%.png$") ~= nil
    else
        -- sizeOf rather than parseHeader: it falls back to the renderer's own
        -- natural size when the header carries no usable viewBox or size.
        aspect, over, night_invert, hang = M.sizeOf(path, head)
    end
    if not aspect then
        -- warn, not dbg: a dropped file is invisible on the shelf and the
        -- reader has nothing to go on. Fires at most once per folder change.
        logger.warn(
            "[bookshelf] ornament skipped, could not be "
            .. "sized: no viewBox or width/height in the first "
            .. "8KB, and the renderer could not open it "
            .. "either -- likely corrupt or not really an "
            .. "SVG: " .. tostring(relpath))
        return nil
    end
    if not is_png and M.looksLikeWrappedBitmap(head) then
        -- Kept in the pool deliberately: a hint off the first 8KB, not a
        -- verdict. The line is what turns "it just doesn't appear" into
        -- something answerable.
        logger.warn(
            "[bookshelf] ornament looks like a picture "
            .. "wrapped in an SVG rather than a drawing; "
            .. "the renderer draws no <image>, so it will "
            .. "come out blank. Drop the picture in as a "
            .. ".png instead: " .. tostring(relpath))
    end
    -- name is the relative path: unique across packs, and what the rotation
    -- and the on/off state key on. file is the bare file name, for display.
    return { path = path, name = relpath, file = file, pack = pack,
             aspect = aspect, overhang = over or 0, night_invert = night_invert,
             hang = hang or nil }
end

-- displayName(entry) -> the file name without its extension (or the
-- .invert flag before it), which is what a person called the ornament.
function M.displayName(entry)
    local f = entry.file or entry.name or ""
    local base = f:gsub("%.[Ii][Nn][Vv][Ee][Rr][Tt]%.[Pp][Nn][Gg]$", ""):gsub("%.[Pp][Nn][Gg]$", ""):gsub("%.[Ss][Vv][Gg]$", "")
    return base ~= "" and base or f
end

-- ── ornaments.json ──────────────────────────────────────────────────────────
-- Placement that belongs to an ornament FILE, so it follows the piece onto
-- every shelf: one file in each pack (what the pack ships) and one in the
-- ornaments folder (the reader's own changes, keyed "Pack/file.png" for a
-- pack's piece, and never written into a pack's file, so updating a pack does
-- not wipe them). Per field, the reader's file beats the old folder's, which
-- beats the pack's, which beats a PNG/SVG directive, which beats the default.
--
-- Units hold at any DPI and shelf size: scale against the default size, lift
-- in the piece's own height (+ up), pad in the books' stand height (each
-- side, - tightens it against the books).
M.JSON_NAME = "ornaments.json"
M.FIELDS = {
    scale  = { kind = "number", min = 0.5, max = 4, default = 1 },
    lift   = { kind = "number", min = -1,  max = 1, default = 0 },
    pad    = { kind = "number", min = -1,  max = 2, default = 0 },
    hang   = { kind = "boolean" },
    night  = { kind = "enum", values = { invert = true, off = true } },
    mirror = { kind = "enum", values = { off = true, always = true, alternate = true }, default = "off" },
    tap    = { kind = "table" },
}

-- cleanField(name, v) -> a usable value, or nil when v is not one.
function M.cleanField(name, v)
    local f = M.FIELDS[name]
    if not f then return nil end
    if f.kind == "number" then
        if type(v) ~= "number" or v ~= v then return nil end
        return math.max(f.min, math.min(f.max, v))
    elseif f.kind == "boolean" then
        if type(v) ~= "boolean" then return nil end
        return v
    elseif f.kind == "enum" then
        return (type(v) == "string" and f.values[v]) and v or nil
    elseif f.kind == "table" then
        return type(v) == "table" and v or nil
    end
end

local function decodeJson(text)
    if M._decode then return M._decode(text) end
    local ok, rj = pcall(require, "rapidjson")
    if ok and rj and rj.decode then return rj.decode(text) end
    return require("json").decode(text)
end

-- readJson(path) -> the file's table, or {} (absent, unreadable, not JSON:
-- the last two logged, and the ornaments still stand on their defaults).
function M.readJson(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local text = f:read("*a")
    f:close()
    local ok, t = pcall(decodeJson, text)
    if not ok or type(t) ~= "table" then
        logger.warn("[bookshelf] ornaments: could not read", path, tostring(t))
        return {}
    end
    return t
end

-- applyLayers(e, layers): merge the settings layers (highest first) over the
-- directives already on e, and derive what the painters read.
local function applyLayers(e, layers)
    local function get(name)
        for _i, layer in ipairs(layers) do
            local rec = layer and layer[e.lookup and e.lookup[_i] or e.name]
            if type(rec) == "table" and rec[name] ~= nil then
                local v = M.cleanField(name, rec[name])
                if v ~= nil then return v end
                logger.warn("[bookshelf] ornaments: ignoring", name, "=", tostring(rec[name]), "for", e.name)
            end
        end
        return nil
    end
    e.scale  = get("scale") or 1
    local lift = get("lift")
    if lift == nil then lift = -(e.overhang or 0) end
    e.lift   = lift
    e.pad    = get("pad") or 0
    local hang = get("hang")
    if hang ~= nil then e.hang = hang or nil end
    local night = get("night")
    if night ~= nil then e.night_invert = (night == "invert") end
    e.mirror = get("mirror") or "off"
    e.tap    = get("tap")
    -- What sizing and placement read: the part below the feet, and a raise.
    e.overhang = (lift < 0) and -lift or 0
    e.raise    = (lift > 0) and lift or 0
    e.lookup = nil
end

-- listAll() -> every ornament in the folders and their packs, switched off
-- or not, sorted by pack (loose ones first) then name; and the pack names.
-- Both folders are read (see M.dir); a relative path present in both is the
-- new folder's. Cached on the folders' own scan keys.
function M.listAll()
    local fs = lfs()
    local roots = M.roots()
    if not fs or #roots == 0 then return {}, {} end
    -- ONE listing of each folder for its files and its packs together: a FUSE
    -- directory listing was measured at 340ms on a tired Kindle, and this runs
    -- once per scan TTL. Same key as AssetFolder.scan: the folder's mtime and
    -- its sorted names.
    local key_parts = {}
    local loose, loose_root = {}, {}        -- name -> true, name -> root
    local pack_set, pack_files = {}, {}     -- pack -> true; pack -> { file -> root }
    for _r, d in ipairs(roots) do
        local mtime = fs.attributes(d, "modification")
        local names, packs = {}, {}
        local ok_l = mtime and pcall(function()
            for name in fs.dir(d) do
                if name:sub(1, 1) ~= "." then
                    local ext = name:match("%.([^%.]+)$")
                    if ext and ORNAMENT_EXTS[ext:lower()] then
                        names[#names + 1] = name
                    elseif fs.attributes(d .. "/" .. name, "mode") == "directory" then
                        packs[#packs + 1] = name
                    end
                end
            end
        end)
        if ok_l then
            table.sort(names)
            table.sort(packs)
            key_parts[#key_parts + 1] = d .. "\3" .. tostring(mtime) .. "|" .. table.concat(names, "\0")
                .. "\5" .. tostring(fs.attributes(d .. "/" .. M.JSON_NAME, "modification"))
            for _i, n in ipairs(names) do
                if not loose[n] then loose[n], loose_root[n] = true, d end
            end
            for _i, pack in ipairs(packs) do
                local pn, pk = AssetFolder.scan(fs, d .. "/" .. pack, ORNAMENT_EXTS)
                key_parts[#key_parts + 1] = "\1" .. pack .. "\2" .. tostring(pk) .. "\5"
                    .. tostring(fs.attributes(d .. "/" .. pack .. "/" .. M.JSON_NAME, "modification"))
                pack_set[pack] = true
                pack_files[pack] = pack_files[pack] or {}
                for _j, file in ipairs(pn or {}) do
                    if not pack_files[pack][file] then pack_files[pack][file] = d end
                end
            end
        end
    end
    local key = table.concat(key_parts, "\4")
    if M._all_cache and M._all_key == key then return M._all_cache, M._all_packs end
    local names = {}
    for n in pairs(loose) do names[#names + 1] = n end
    table.sort(names)
    local packs = {}
    for p in pairs(pack_set) do packs[#packs + 1] = p end
    table.sort(packs)
    local out = {}
    local ok = pcall(function()
        for _i = 1, #names do
            local n = names[_i]
            local e = entryFor(loose_root[n] .. "/" .. n, n, n, nil)
            if e then out[#out + 1] = e end
        end
        for _i, pack in ipairs(packs) do
            local files = {}
            for f in pairs(pack_files[pack]) do files[#files + 1] = f end
            table.sort(files)
            for _j, file in ipairs(files) do
                local rel = pack .. "/" .. file
                local e = entryFor(pack_files[pack][file] .. "/" .. rel, rel, file, pack)
                if e then out[#out + 1] = e end
            end
        end
    end)
    if not ok then out = {} end
    -- The settings layers. The root files of both folders, then each pack's
    -- own file, read from the folder its piece came from.
    local root_json = {}
    for _r, d in ipairs(roots) do root_json[_r] = M.readJson(d .. "/" .. M.JSON_NAME) end
    local pack_json = {}
    for _i, e in ipairs(out) do
        local layers = {}
        for _r = 1, #roots do layers[#layers + 1] = root_json[_r] end
        local lookup = {}
        for _r = 1, #roots do lookup[_r] = e.name end
        if e.pack then
            local pdir = e.path:match("^(.*)/[^/]+$")
            if pack_json[pdir] == nil then pack_json[pdir] = M.readJson(pdir .. "/" .. M.JSON_NAME) end
            layers[#layers + 1] = pack_json[pdir]
            lookup[#layers] = e.file
        end
        e.lookup = lookup
        pcall(applyLayers, e, layers)
    end
    M._all_cache, M._all_key, M._all_packs = out, key, packs
    return out, packs
end

-- list() -> the ornaments the shelf may place: every one in listAll() that is
-- not switched off and whose pack is not. Sorted by name (relative path),
-- which the rotation relies on.
function M.list()
    local now = M._clock()
    if M._list_cache and M._list_at and M.SCAN_TTL > 0
            and (now - M._list_at) < M.SCAN_TTL then
        return M._list_cache
    end
    local all = M.listAll()
    M._list_at = now
    local off, packs_off = readSet(M.OFF_KEY), readSet(M.PACKS_OFF_KEY)
    -- The same table while nothing changed: the rotation and the plan key on
    -- it, and re-filtering every render would hand out a new one each time.
    local sig = {}
    for k in pairs(off) do sig[#sig + 1] = k end
    for k in pairs(packs_off) do sig[#sig + 1] = "\1" .. k end
    table.sort(sig)
    local key = tostring(all) .. "|" .. table.concat(sig, "\0")
    if M._list_cache and M._list_key == key then return M._list_cache end
    local out = {}
    for _i, e in ipairs(all) do
        if not off[e.name] and not (e.pack and packs_off[e.pack]) then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    M._list_cache, M._list_key = out, key
    return out
end

-- delete(entry) -> true on success. Removes the file and forgets its state.
function M.delete(entry)
    if not (entry and entry.path) then return false end
    local ok = os.remove(entry.path)
    if not ok then return false end
    local set = readSet(M.OFF_KEY)
    if set[entry.name] then set[entry.name] = nil; saveSet(M.OFF_KEY, set) end
    M._all_cache, M._all_key, M._list_cache, M._list_key = nil, nil, nil, nil
    return true
end

-- invalidate(): forget the cached lists (the browser, after a change).
function M.invalidate()
    M._all_cache, M._all_key, M._list_cache, M._list_key, M._list_at = nil, nil, nil, nil, nil
end

-- looksLikeWrappedBitmap(head) -> bool
--
-- A photo "converted" to SVG by wrapping it in an <image> element rather than
-- tracing it. The file parses and carries a correct viewBox, so it joins the
-- pool and is given a gap -- and then nothing is drawn, because nanosvg has no
-- <image> handler. Its element table in the shipped library is exactly:
--
--   circle defs ellipse linearGradient path polygon polyline radialGradient rect
--
-- so the element is skipped outright. Resizing the file cannot help, which is
-- what makes this so confusing to hit (issue 404).
--
-- A hint, not a verdict: we see only the first 8KB, and a part-traced drawing
-- could carry its shapes further in. So an <image> ALONGSIDE any drawable
-- element is left alone, and the caller warns rather than rejecting.
local DRAWABLE = { "<path", "<rect", "<circle", "<ellipse", "<polygon",
                   "<polyline", "<line" }
function M.looksLikeWrappedBitmap(head)
    if type(head) ~= "string" then return false end
    if not head:find("<image", 1, true) then return false end
    for i = 1, #DRAWABLE do
        if head:find(DRAWABLE[i], 1, true) then return false end
    end
    return true
end

-- sizeOf(path, head) -> aspect, overhang_share, night_invert  (or nil)
--
-- parseHeader first: a regex over the first 8KB, cheap, and right for every
-- ornament anyone has actually written. When it comes back empty the file is
-- not necessarily unusable -- it may carry percentage sizes, or neither a
-- viewBox nor width/height, both of which nanosvg handles by applying its own
-- defaults. So ask the renderer, which parses the file properly and reports
-- the natural size it will actually draw at.
--
-- Last resort ONLY. A normal folder never reaches it, so no one pays a full
-- SVG parse per file on a folder change; a folder of awkward files pays it
-- once, since M.list is cached until the folder changes.
--
-- The bookshelf:overhang share still works off whatever height won: it is
-- declared in the file's own coordinate units, and nanosvg measures in those
-- same units (the viewBox when there is one, width/height otherwise).
local function defaultSize(path)
    local NnSVG = require("libs/libkoreader-nnsvg")
    local img = NnSVG.new(path)
    if not img then return nil end
    local w, h = img:getSize()
    if img.free then pcall(function() img:free() end) end
    return w, h
end

function M.sizeOf(path, head)
    local aspect, over, night_invert, hang = M.parseHeader(head)
    if aspect then return aspect, over, night_invert, hang end
    local ok, w, h = pcall(M._size or defaultSize, path)
    if not ok or not (w and h) or w <= 0 or h <= 0 then return nil end
    -- Re-read the conventions from the header: only the SIZE was missing.
    local o = tonumber(type(head) == "string"
        and head:match("bookshelf:overhang%s*=%s*([%d%.]+)") or nil) or 0
    if o < 0 then o = 0 end
    if o > h then o = h end
    local inv = type(head) == "string"
        and head:match("bookshelf:night%s*=%s*invert") ~= nil or false
    return w / h, o / h, inv, M.declaresHang(head)
end

-- hash(s) -> non-negative integer, djb2 (LuaJIT-safe arithmetic).
-- Bitwise xor that works on both interpreters: LuaJIT is Lua 5.1, where the
-- binary `~` operator does not exist, and the tests run under 5.4.
local bxor
do
    local ok_bit, bit = pcall(require, "bit")
    if ok_bit and bit and bit.bxor then
        bxor = function(a, b) return bit.bxor(a, b) % 4294967296 end
    else
        bxor = function(a, b)
            local r, m = 0, 1
            for _i = 1, 32 do
                local x, y = a % 2, b % 2
                if x ~= y then r = r + m end
                a, b, m = (a - x) / 2, (b - y) / 2, m * 2
            end
            return r
        end
    end
end

-- djb2, then an avalanche so neighbouring seeds do not give neighbouring
-- answers.
--
-- WHY THE MIX MATTERS. Every seeded decision here is taken modulo something
-- small: the odds are `h % 100`, the per-page promise is `h % period`. Plain
-- djb2 over strings that differ only in their last byte moves the result by
-- exactly that byte's difference, so "page2|rowend|1" and "page2|rowend|2"
-- came out one apart. An on-device probe caught the consequence: `h % 100`
-- ran 23, 24, 25 ... straight up the rows of a page, so whether a row got an
-- ornament was not a per-row coin toss at all -- it was a contiguous run, and
-- a two-row page therefore gave BOTH its rows a piece or neither. Pages
-- arrived in clumps with long deserts between them, which reads as the same
-- few ornaments over and over rather than as "often".
--
-- The finisher is the 32-bit xorshift-multiply from MurmurHash3; two inputs a
-- byte apart now differ across the whole word. Same function of the same
-- seed, so both planning passes still agree -- only the spread changes.
function M.hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    h = bxor(h, math.floor(h / 65536))          -- h ^ (h >> 16)
    h = (h * 2246822507) % 4294967296
    h = bxor(h, math.floor(h / 8192))           -- h ^ (h >> 13)
    h = (h * 3266489909) % 4294967296
    return bxor(h, math.floor(h / 65536))
end


-- THE DECK: which ornament a slot gets.
--
-- Every enabled ornament is a card in a shuffled deck, dealt in order: with
-- ten ornaments, the first ten a reader sees are one of each, then the deck
-- is shuffled again (maintainer: "if you have 10 ornaments and see 10
-- ornaments you must see exactly one of each").
--
-- The rotation this replaces handed each slot a place in a cycle over the
-- pieces that FITTED that slot, so every gap cycled over a different subset
-- and pieces came round again before the rest had been seen. Now a slot does
-- not choose: it takes the top card. A slot that cannot take it (a section
-- gap too narrow for it, the first row of a page for a piece that hangs from
-- the shelf above, packing slack too small) stays plain and the card waits on
-- top for the next slot that can, so the order is never broken. Row ends and
-- bare planks make room: a piece gets its natural width there, up to the
-- whole row, and the books move over (maintainer: "each ornament makes space
-- for itself ... max width for an ornament is a full row, it can even have no
-- books").
--
-- Dealt once per seed and remembered (M._dealt), because pick() runs again on
-- every repaint and in both planning passes, and they must agree. Bounded:
-- page turns mint seeds forever, and on overflow the memory is dropped, which
-- at worst re-deals pieces the reader has paged away from.
M._deck, M._deck_pos, M._deck_key = nil, 1, nil
M._dealt, M._dealt_n = {}, 0
M.DEAL_MAX = 2048
M.PASS_LIMIT = 6
M._passes = 0
-- Shuffled with its own generator, so nothing else that draws math.random is
-- disturbed, and seeded from the clock, so each session starts somewhere new.
M._shuffle_state = nil
local function nextRand(n)
    local s = M._shuffle_state or (os.time() % 2147483647)
    s = (s * 48271) % 2147483647
    M._shuffle_state = s
    return (s % n) + 1
end
local function entryName(e) return e.name or e.path end

-- deck(entries) -> the deck for this pool, rebuilt when the pool changes.
function M.deck(entries)
    local names = {}
    for i = 1, #entries do names[i] = entryName(entries[i]) end
    local key = table.concat(names, "\0")
    if M._deck_key ~= key then
        M._deck, M._deck_pos, M._deck_key = {}, 1, key
        M.reshuffle(entries)
    end
    return M._deck
end

-- reshuffle(entries): a new order for the next round. Pieces already standing
-- on this screen go to the back, so a small deck does not show the same piece
-- twice across the seam.
function M.reshuffle(entries)
    local fresh, standing = {}, {}
    local order = {}
    for i = 1, #entries do order[i] = entries[i] end
    for i = #order, 2, -1 do
        local j = nextRand(i)
        order[i], order[j] = order[j], order[i]
    end
    for i = 1, #order do
        if M._used[entryName(order[i])] then standing[#standing + 1] = order[i]
        else fresh[#fresh + 1] = order[i] end
    end
    for i = 1, #standing do fresh[#fresh + 1] = standing[i] end
    M._deck, M._deck_pos = fresh, 1
end

-- shuffle(): a new layout (the "Bookshelf: shuffle ornaments" action). Every
-- slot forgets what it was dealt and the deck starts a fresh order, so the
-- next paint deals every shelf again.
function M.shuffle()
    M._dealt, M._dealt_n, M._passes = {}, 0, 0
    M._used = {}
    M._deck, M._deck_pos, M._deck_key = nil, 1, nil
end

local function topCard(entries)
    local deck = M.deck(entries)
    if M._deck_pos > #deck then M.reshuffle(entries); deck = M._deck end
    return deck[M._deck_pos]
end

-- pick(seed, gap_px, stand_h, entries, o) -> placement or nil.
--   gap_px  : the width this slot can give, net of margins and padding
--   stand_h : the books' stand height (feet at y = stand_h in row coords)
--   entries : pool (default M.list())
--   o.min_gap, o.min_h : px floors; o.min_h_frac : floor as a share of
--   stand_h (default M.MIN_H_FRAC); o.max_below : how far below the feet the
--   overhang may reach (the plank's surface strip + front face); o.no_hang :
--   a hanging piece cannot go here (no shelf above); o.makes_room : the slot
--   is sized to the piece (a row end, a bare plank), so gap_px is the whole
--   row and a piece wider than that is scaled to it rather than passed over.
function M.pick(seed, gap_px, stand_h, entries, o)
    o = o or {}
    entries = entries or M.list()
    if #entries == 0 then return nil end
    if (gap_px or 0) < (o.min_gap or 0) then return nil end
    local h = M.hash(tostring(seed))
    -- A budgeted channel stops once the screen has its fill. Checked before
    -- the odds so a full screen costs nothing.
    if o.budgeted and M.budgetLeft() <= 0 then return nil end
    -- Scaled here rather than at each call site, so every placement moves
    -- together with one setting; o.level lets a channel use its own curve
    -- (see M.GROUP_LEVEL).
    local level = o.level or M.frequency()
    local chance = (o.chance or M.CHANCE) * level
    if chance <= 0 then return nil end
    if chance < 1 and (h % 100) >= math.floor(chance * 100) then return nil end

    -- sizeFor(entry) -> w, h at this slot, or nil when it cannot stand here.
    local function sizeFor(entry)
        if o.no_hang and entry.hang then return nil end
        local height = math.floor((stand_h or 0) * M.HEIGHT_FRAC)
        local width  = math.floor(height * entry.aspect)
        local shrunk = false
        if width > gap_px then
            -- Only a slot that makes room scales a piece, and only to the
            -- whole row; anywhere else the piece waits for one that can.
            if not o.makes_room then return nil end
            width  = gap_px
            height = math.floor(width / entry.aspect)
            shrunk = true
        end
        if entry.overhang > 0 and o.max_below and not entry.hang then
            -- Shrink so the overhang never reaches past the plank's front.
            local below = height * entry.overhang
            if below > o.max_below then
                height = math.floor(o.max_below / entry.overhang)
                width  = math.floor(height * entry.aspect)
            end
        end
        if width < 1 or height < 1 then return nil end
        -- The height floor guards against a piece shrunk to a speck; a piece
        -- as wide as the whole row is shown however low that makes it.
        if not shrunk or not o.makes_room then
            local frac  = o.min_h_frac or M.MIN_H_FRAC
            local min_h = math.max(o.min_h or 1, math.floor((stand_h or 0) * frac))
            if height < min_h then return nil end
        end
        return width, height
    end

    local byName
    local entry
    local dealt = M._dealt[tostring(seed)]
    if dealt == false then return nil end
    if dealt then
        byName = {}
        for i = 1, #entries do byName[entryName(entries[i])] = entries[i] end
        entry = byName[dealt]
    end
    local width, height
    if entry then
        width, height = sizeFor(entry)
        if not width then return nil end
    else
        -- A seed never dealt (or its piece was switched off): the top card.
        local card = topCard(entries)
        if not card then return nil end
        if M._dealt_n >= M.DEAL_MAX then M._dealt, M._dealt_n = {}, 0 end
        M._dealt_n = M._dealt_n + 1
        width, height = sizeFor(card)
        if not width then
            -- Passed over, remembered as such so a repaint does not deal it
            -- after all; the card stays on top. A card that keeps being
            -- passed over (a hanging piece on a one-row shelf, a piece too
            -- wide for any section gap on a shelf that reserves no row ends)
            -- would block the deck for good, so after PASS_LIMIT slots it goes
            -- to the back of this round.
            M._dealt[tostring(seed)] = false
            M._passes = (M._passes or 0) + 1
            if M._passes >= M.PASS_LIMIT then
                table.insert(M._deck, table.remove(M._deck, M._deck_pos))
                M._passes = 0
            end
            return nil
        end
        entry = card
        M._passes = 0
        M._deck_pos = M._deck_pos + 1
        M._dealt[tostring(seed)] = entryName(card)
    end
    local below = entry.hang and 0 or math.floor(height * entry.overhang)
    M._used[entryName(entry)] = true
    return {
        entry = entry, w = width, h = height,
        above = height - below, below = below,
        side  = (math.floor(h / 10000) % 2 == 0) and "right" or "left",
    }
end

-- render(entry, w, h, night) -> bb or nil. Cached; the cache owns its bbs
-- (widgets blit from it at paint and never keep the reference), so eviction
-- frees for real.
M._cache = {}
M._cache_order = {}
-- unpremultiply(bb) -- straight alpha from premultiplied, in place.
--
-- MuPDF decodes a PNG with every pixel's colour already multiplied by its
-- alpha; KOReader's own ImageWidget knows and blits those with
-- pmulalphablitFrom. Everything here blends as STRAIGHT alpha (alphablitFrom,
-- and the night pre-invert), so a premultiplied bitmap darkened each
-- half-transparent pixel twice: soft edges and baked shadows came out darker
-- than drawn (measured: a white ramp at 50% alpha on grey rendered 127, not
-- 192). Converting once, at render, fixes every blit of the cached bitmap.
--
-- Fast path: walk the bytes of an unrotated RGB32 or grey+alpha (BB8A)
-- bitmap directly, which is what a PNG decodes to. Per-pixel getPixelP calls
-- measured 29 ms for a 250x460 ornament on a PW5, paid on every first render.
function M.unpremultiply(bb)
    local done = pcall(function()
        local ffi = require("ffi")
        local t = bb.getType and bb:getType()
        if not (bb.data and bb.stride and bb.getRotation and bb:getRotation() == 0
                and not (bb.getInverse and bb:getInverse() == 1)) then
            error("slow path")
        end
        local bpp = (t == 5) and 4 or ((t == 2) and 2 or nil)   -- RGB32, BB8A
        if not bpp then error("slow path") end
        local p = ffi.cast("uint8_t*", bb.data)
        local w, h, stride = bb:getWidth(), bb:getHeight(), tonumber(bb.stride)
        local floor = math.floor
        for y = 0, h - 1 do
            local row = p + y * stride
            for x = 0, w - 1 do
                local o = x * bpp
                local a = row[o + bpp - 1]
                if a > 0 and a < 255 then
                    local k = 255 / a
                    for c = 0, bpp - 2 do
                        local v = floor(row[o + c] * k + 0.5)
                        row[o + c] = v > 255 and 255 or v
                    end
                end
            end
        end
    end)
    if done then return end
    pcall(function()
        for yy = 0, bb:getHeight() - 1 do
            for xx = 0, bb:getWidth() - 1 do
                local p = bb:getPixelP(xx, yy)
                local a = p.alpha
                if a and a > 0 and a < 255 then
                    p.r = math.min(255, math.floor(p.r * 255 / a + 0.5))
                    p.g = math.min(255, math.floor(p.g * 255 / a + 0.5))
                    p.b = math.min(255, math.floor(p.b * 255 / a + 0.5))
                end
            end
        end
    end)
end

local function defaultRender(path, w, h)
    local RenderImage = require("ui/renderimage")
    if path:lower():match("%.svg$") then
        -- NanoSVG hands back straight alpha (is_straight true); MuPDF, when it
        -- renders the SVG instead, premultiplied.
        local bb, is_straight = RenderImage:renderSVGImageFile(path, w, h)
        if bb and not is_straight then M.unpremultiply(bb) end
        return bb
    end
    -- A raster. want_frames FALSE: asking for frames hands back a list of
    -- functions instead of a blitbuffer, which is an animation's shape, not an
    -- ornament's. The renderer scales to the size we ask for, so a small PNG
    -- is upscaled to the shelf's standard ornament height exactly as an SVG
    -- would be (maintainer's call: every file a reader drops in shows up).
    local bb = RenderImage:renderImageFile(path, false, w, h)
    if bb then M.unpremultiply(bb) end
    return bb
end
-- render(entry, w, h, inverting) -> a bitmap ready to blit, or nil.
--
-- Two axes, as everywhere else on the shelf. `inverting` is the FRAME: the
-- device's night mode, which flips every pixel after we paint. The LOOK is
-- the theme (CoverProgress.theme), which can be dark with the frame not
-- inverting at all. The pieces:
--   chalk          - should this ornament DISPLAY inverted? Only an
--                    .invert-flagged one, on a grey panel, with no picture
--                    behind it, and only when the look is dark. A colour
--                    panel always gets the colours as drawn (an inverted
--                    green plant is magenta), and over a picture nothing
--                    inverts: the picture is pre-inverted and displays the
--                    same in both modes, so a plant flipping to its negative
--                    in front of it would be the only thing that changed
--                    (maintainer).
--   paint inverted - what has to be in the BUFFER for that to display: the
--                    wanted look, flipped again if the frame will flip it.
-- Reading only the frame here meant that under the shelf's own dark theme
-- by day a chalk ornament painted its authored dark silhouette onto a black
-- plank. The cache is keyed on what was painted, the one thing that
-- distinguishes two renders of one file at one size. RGB32 invert keeps the
-- alpha, so the shelf still shows through.
function M.render(entry, w, h, inverting)
    inverting = inverting and true or false
    local dark = inverting
    pcall(function()
        local CP = require("lib/bookshelf_cover_progress")
        if CP and CP.theme then
            local d = CP.theme()
            if type(d) == "boolean" then dark = d end
        end
    end)
    local picture = false
    pcall(function()
        local W = require("lib/bookshelf_wallpaper")
        picture = W.isShowing and W.isShowing() or false
        -- A picture shown as its negative at night is a dark ground like any
        -- other, so a chalk ornament goes light on it as it would on the page.
        if picture and W.showsNegative then
            local ok_s, Screen = pcall(function() return require("device").screen end)
            local frame = ok_s and Screen and Screen.night_mode and true or false
            if W.showsNegative(frame) then picture = false end
        end
    end)
    local chalk = entry.night_invert and not M.hasColorScreen()
                  and not picture and dark
    local paint_inverted = (chalk and true or false) ~= inverting
    local key = entry.path .. "|" .. w .. "x" .. h .. (paint_inverted and "|i" or "")
    local bb = M._cache[key]
    if bb then return bb end
    local ok, res = pcall(M._render or defaultRender, entry.path, w, h)
    if not ok or not res then
        logger.dbg("[bookshelf] ornament render failed:", entry.path)
        return nil
    end
    bb = res
    if paint_inverted and bb.invertRect then
        pcall(function() bb:invertRect(0, 0, bb:getWidth(), bb:getHeight()) end)
    end
    M._cache[key] = bb
    M._cache_order[#M._cache_order + 1] = key
    while #M._cache_order > M.CACHE_MAX do
        local old = table.remove(M._cache_order, 1)
        local ob = M._cache[old]
        M._cache[old] = nil
        if ob and ob.free then pcall(function() ob:free() end) end
    end
    return bb
end

-- contentBox(entry) -> l, t, r, b as fractions (0..1) of the image, the part
-- that is not transparent; nil when it cannot tell (no alpha, render failed).
-- An ornament's file carries transparent room on purpose (top padding sets
-- its height against the books, side padding keeps it off them), which is
-- right on the shelf and wasted space in the browser's preview. Found from a
-- small render, so it is cheap, and remembered per file for the session.
M.CONTENT_PROBE = 96
M._content = {}
function M.contentBox(entry)
    local key = entry.path .. "|" .. tostring(entry.aspect)
    local hit = M._content[key]
    if hit ~= nil then
        if hit == false then return nil end
        return hit[1], hit[2], hit[3], hit[4]
    end
    local box = false
    local aspect = (entry.aspect and entry.aspect > 0) and entry.aspect or 1
    local h = M.CONTENT_PROBE
    local w = math.max(1, math.floor(h * aspect + 0.5))
    local ok, bb = pcall(M._render or defaultRender, entry.path, w, h)
    if ok and bb then
        pcall(function()
            local bw, bh = bb:getWidth(), bb:getHeight()
            if bb:getPixel(0, 0).alpha == nil then return end
            local l, t, r, b = bw, bh, -1, -1
            for y = 0, bh - 1 do
                for x = 0, bw - 1 do
                    if bb:getPixel(x, y).alpha > 24 then
                        if x < l then l = x end
                        if x > r then r = x end
                        if y < t then t = y end
                        if y > b then b = y end
                    end
                end
            end
            if r >= l and b >= t then
                box = { l / bw, t / bh, (r + 1) / bw, (b + 1) / bh }
            end
        end)
        if bb.free then pcall(function() bb:free() end) end
    end
    M._content[key] = box
    if not box then return nil end
    return box[1], box[2], box[3], box[4]
end

-- The widget: blits the cached render at paint time. Inert to gestures.
M.Ornament = Widget:extend{
    placement = nil,
    night     = false,
}

function M.Ornament:init()
    local p = self.placement
    self.dimen = require("ui/geometry"):new{ w = p.w, h = p.h }
end

function M.Ornament:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local p = self.placement
    local img = M.render(p.entry, p.w, p.h, self.night)
    if not img then return end
    pcall(function()
        bb:alphablitFrom(img, x, y, 0, 0, p.w, p.h)
    end)
end

return M
