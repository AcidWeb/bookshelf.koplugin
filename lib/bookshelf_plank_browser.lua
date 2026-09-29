--[[
The plank picker: the plank the Spines style stands its books on. The plain
colour, the built-in Oak, then each pack's planks, one per row and each shown
as the shelf paints it. Opened from the "Shelf plank" row (Accent colors, and
Wallpaper, ornaments and colors); a tap uses that plank and closes. On the
ornament collection's screen (LibraryModal), like the wallpaper picker.

The plain colour opens the plank colour dialog as well, so the colour can be
changed there and then.
]]
local ok_i, I18n = pcall(require, "lib/bookshelf_i18n")
local _ = (ok_i and I18n and I18n.gettext) or function(s) return s end

local PB = {}
PB.ALL, PB.BUILTIN = "__all", "__builtin"

local function TP() return require("lib/bookshelf_theme_pack") end

-- entries(chip) -> the options on that tab: All, Built-in (the colour and
-- Oak), or one pack's planks.
function PB.entries(chip)
    local out = {}
    for _i, o in ipairs(TP().plankOptions()) do
        local keep = chip == PB.ALL
            or (chip == PB.BUILTIN and o.kind ~= "pack")
            or (o.pack ~= nil and o.pack == chip)
        if keep then out[#out + 1] = o end
    end
    -- Under Oak and the colour, when that is all there is, a quiet line
    -- saying where more come from (a row that does nothing when tapped).
    if chip ~= nil and (chip == PB.ALL or chip == PB.BUILTIN) and PB.showsMoreHint() then
        out[#out + 1] = { kind = "hint" }
    end
    return out
end

-- choiceOf(o) -> the value choosePlank takes for that option.
function PB.choiceOf(o)
    if o.kind == "hint" then return nil end
    if o.kind == "colour" then return "colour" end
    if o.kind == "oak" then return "oak" end
    return o.plank.id
end

function PB.inUse(o)
    local c = PB.choiceOf(o)
    return c ~= nil and TP().plankChoice() == c
end

-- showsMoreHint() -> true when no pack has planks: most readers only ever
-- have Oak and the colour, so they get one quiet line saying where more come
-- from, and nothing else (maintainer).
function PB.showsMoreHint()
    for _i, o in ipairs(TP().plankOptions()) do
        if o.kind == "pack" then return false end
    end
    return true
end

-- Rendered previews, per plank and size: a page is a handful of planks, and
-- flicking between tabs shows the same ones again.
local _previews, _order = {}, {}
local PREVIEW_KEEP = 12
local function preview(o, w, row_h)
    local design = (o.kind ~= "colour") and o.plank or nil
    local key = (design and design.middle or "colour") .. "|" .. w .. "x" .. row_h
    -- The colour follows the setting, so it is never cached.
    if design and _previews[key] then return _previews[key], false end
    local ok, bb = pcall(function()
        return require("lib/bookshelf_spine_shelf").plankPreview(design, w, row_h)
    end)
    if not ok or not bb then return nil end
    if not design then return bb, true end
    _previews[key] = bb
    _order[#_order + 1] = key
    while #_order > PREVIEW_KEEP do
        local old = table.remove(_order, 1)
        if _previews[old] then pcall(function() _previews[old]:free() end) end
        _previews[old] = nil
    end
    return bb, false
end

local function nameOf(o)
    if o.kind == "colour" then return _("Plain color") end
    if o.kind == "oak" then return _("Oak") end
    return (o.plank and o.plank.name) or o.pack
end

local function renderHint(dimen)
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font            = require("ui/font")
    local Geom            = require("ui/geometry")
    local TextBoxWidget   = require("ui/widget/textboxwidget")
    return CenterContainer:new{ dimen = Geom:new{ w = dimen.w, h = dimen.h },
        TextBoxWidget:new{ text = _("More planks come with packs: see Add ornaments in the Ornament collection."),
                           face = Font:getFace("cfont", 16), width = math.floor(dimen.w * 0.8),
                           alignment = "center" } }
end

local function renderCell(o, dimen)
    if o.kind == "hint" then return renderHint(dimen) end
    local Blitbuffer      = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font            = require("ui/font")
    local FrameContainer  = require("ui/widget/container/framecontainer")
    local Geom            = require("ui/geometry")
    local ImageWidget     = require("ui/widget/imagewidget")
    local Screen          = require("device").screen
    local Size            = require("ui/size")
    local Space           = require("lib/bookshelf_space")
    local TextWidget      = require("lib/bookshelf_colour_text")
    local VerticalGroup   = require("ui/widget/verticalgroup")
    local VerticalSpan    = require("ui/widget/verticalspan")
    local T               = require("ffi/util").template
    local pad = Space.padding.default
    local inner_w, inner_h = dimen.w - 2 * pad, dimen.h - 2 * pad
    local name = nameOf(o)
    if o.kind == "pack" then name = T(_("%1 (%2)"), name, o.pack) end
    local status
    if PB.inUse(o) then status = _("In use")
    elseif o.pack_off then status = _("Pack off") end
    local lines = VerticalGroup:new{ align = "center",
        TextWidget:new{ text = name, face = Font:getFace("cfont", 18), bold = true, max_width = inner_w } }
    if status then
        lines[#lines + 1] = TextWidget:new{ text = status, face = Font:getFace("cfont", 14), max_width = inner_w }
    end
    -- A row the height of a four-row shelf: the plank as most shelves show it.
    local row_h = math.floor(Screen:getHeight() / 4)
    local bb, disposable = preview(o, inner_w, row_h)
    local box_h = math.max(1, inner_h - lines:getSize().h - Space.padding.small)
    local pic
    if bb then
        pic = ImageWidget:new{ image = bb, image_disposable = disposable,
                               width = inner_w, height = math.min(box_h, bb:getHeight()) }
    end
    return FrameContainer:new{
        bordersize = 0, padding = pad, margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h },
            VerticalGroup:new{ align = "center",
                CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = box_h },
                    pic or VerticalSpan:new{ width = 1 } },
                VerticalSpan:new{ width = Space.padding.small },
                lines,
            } },
    }
end

-- show(opts): the picker.
--   opts.chip        the tab to open on (a pack's name), else All
--   opts.on_change   after a choice, so the menu row and the shelf catch up
--   opts.pick_colour function(before): the plank colour dialog, after the
--                    plain colour is chosen; before is the choice it replaced
--                    (the dialog's Revert puts it back)
function PB.show(opts)
    opts = opts or {}
    local LibraryModal = require("lib/bookshelf_library_modal")
    local UIManager    = require("ui/uimanager")
    local Screen       = require("device").screen
    local T            = require("ffi/util").template
    local self = { chip = opts.chip or PB.ALL }
    local function items() return PB.entries(self.chip) end
    self.items = items()
    local modal
    local function close() if modal then UIManager:close(modal); modal = nil end end
    local function landscape() return Screen:getWidth() > Screen:getHeight() end
    local function chips()
        local out = {
            { key = PB.ALL, label = _("All"), is_active = self.chip == PB.ALL },
            { key = PB.BUILTIN, label = _("Built-in"), is_active = self.chip == PB.BUILTIN },
        }
        local seen = {}
        for _i, o in ipairs(TP().plankOptions()) do
            if o.kind == "pack" and not seen[o.pack] then
                seen[o.pack] = true
                out[#out + 1] = { key = o.pack, label = o.pack_off and T(_("%1 (off)"), o.pack) or o.pack,
                                  is_active = self.chip == o.pack }
            end
        end
        return out
    end
    local config = {
        title = _("Shelf plank"),
        no_search = true,
        grid_cols = function() return 1 end,
        cells_per_page = function() return landscape() and 3 or 4 end,
        -- The grid's height is rows_per_page cards of 64dp (LibraryModal).
        rows_per_page = function()
            return math.max(3, math.floor(Screen:getHeight() * 0.6 / Screen:scaleBySize(64)))
        end,
        chip_strip = chips,
        on_chip_tap = function(k) self.chip = k; self.items = items() end,
        cell_renderer = renderCell,
        on_cell_tap = function(o)
            if o.kind == "hint" then return end
            local before = TP().plankChoice()
            if o.pack_off and o.pack then require("lib/bookshelf_ornaments").setPackOff(o.pack, false) end
            TP().choosePlank(PB.choiceOf(o))
            close()
            if opts.on_change then pcall(opts.on_change) end
            UIManager:setDirty("all", "full")   -- the band under the last row
            if o.kind == "colour" and opts.pick_colour then opts.pick_colour(before) end
        end,
        item_count = function() return #self.items end,
        item_at = function(i) return self.items[i] end,
        footer_rows = { { { key = "close", label = _("Close"), on_tap = close } } },
    }
    modal = LibraryModal:new{ config = config }
    UIManager:show(modal)
    return modal
end

return PB
