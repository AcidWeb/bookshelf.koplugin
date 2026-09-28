-- bookshelf_ornament_browser.lua
-- Browse the ornaments folder: see every ornament, switch any of them (or a
-- whole pack) off and on, and delete them. On the shared LibraryModal chrome,
-- like the micro-module picker.
--
-- A pack is a subfolder of the ornaments folder (lib/bookshelf_ornaments);
-- the chips across the top are All (every ornament) and one per pack.
-- With a pack's chip selected the footer switches the whole pack off or on.
--
--   tap        switch that ornament off / on
--   long-press switch it, or delete it
--
-- Switching off leaves the file where it is, so it can come back; deleting
-- removes it. Seeds that are deleted stay deleted (the folder is only seeded
-- when it does not exist).

local Blitbuffer      = require("ffi/blitbuffer")
local ButtonDialog    = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox      = require("ui/widget/confirmbox")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local InfoMessage     = require("ui/widget/infomessage")
local LibraryModal    = require("lib/bookshelf_library_modal")
local Size            = require("ui/size")
local Space           = require("lib/bookshelf_space")
local TextWidget      = require("lib/bookshelf_colour_text")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")
local T               = require("ffi/util").template
local _               = require("lib/bookshelf_i18n").gettext
local Screen          = Device.screen

local Browser = {}

local ALL = "__all"

local function O() return require("lib/bookshelf_ornaments") end

-- An ornament's PICTURE is faded while it will not be placed, whether switched
-- off itself or through its pack: the grid reads as "what the shelf uses".
-- Only the picture: the "Off" / "Pack off" label under it is what says why,
-- so it stays at full strength (maintainer).
local Faded = Widget:extend{ child = nil, fade = 0.6 }
function Faded:getSize() return self.child:getSize() end
function Faded:paintTo(bb, x, y)
    self.child:paintTo(bb, x, y)
    local s = self.child:getSize()
    pcall(function() bb:lightenRect(x, y, s.w, s.h, self.fade) end)
    self.dimen = Geom:new{ x = x, y = y, w = s.w, h = s.h }
end

-- A preview: renders the ornament at the size that makes its picture fill
-- w x h, and blits just that part (src_x, src_y) of the render.
local Cropped = Widget:extend{ placement = nil, night = false, src_x = 0, src_y = 0, w = 1, h = 1 }
function Cropped:getSize() return Geom:new{ w = self.w, h = self.h } end
function Cropped:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local p = self.placement
    local img = O().render(p.entry, p.w, p.h, self.night)
    if not img then return end
    pcall(function() bb:alphablitFrom(img, x, y, self.src_x, self.src_y, self.w, self.h) end)
end

function Browser._renderCell(item, dimen)
    local e = item.entry
    local border = Size.border.default
    local pad = Space.padding.default
    local label_face = Font:getFace("cfont", 16)
    local state_face = Font:getFace("cfont", 13)
    local inner_w = dimen.w - 2 * (border + pad)
    local label = TextWidget:new{ text = O().displayName(e), face = label_face, max_width = inner_w }
    -- The state line is there only on a card that is off (its picture is
    -- faded too); a card that is on gives its picture that room.
    local state = (item.off or item.pack_off) and TextWidget:new{
        text = item.off and _("Off") or _("Pack off"),
        face = state_face, fgcolor = Blitbuffer.COLOR_BLACK, max_width = inner_w,
    } or nil
    local text_h = label:getSize().h + (state and state:getSize().h or 0)
    local box_h = math.max(1, dimen.h - 2 * (border + pad) - text_h - Space.padding.small)
    -- Preview the picture, not the file: the transparent room an ornament
    -- carries for the shelf is cropped off, and what is left fits the box.
    local aspect = (e.aspect and e.aspect > 0) and e.aspect or 1
    local l, t, r, b = O().contentBox(e)
    if not l then l, t, r, b = 0, 0, 1, 1 end
    local cut_aspect = aspect * (r - l) / (b - t)
    local cw, ch = inner_w, math.floor(inner_w / cut_aspect)
    if ch > box_h then ch = box_h; cw = math.floor(box_h * cut_aspect) end
    cw, ch = math.max(1, cw), math.max(1, ch)
    local preview = Cropped:new{
        placement = { entry = e, w = math.max(1, math.floor(cw / (r - l) + 0.5)),
                      h = math.max(1, math.floor(ch / (b - t) + 0.5)) },
        night = Screen.night_mode and true or false,
        src_x = 0, src_y = 0, w = cw, h = ch,
    }
    preview.src_x = math.floor(l * preview.placement.w + 0.5)
    preview.src_y = math.floor(t * preview.placement.h + 0.5)
    if item.off or item.pack_off then preview = Faded:new{ child = preview } end
    local inner_h = dimen.h - 2 * (border + pad)
    local body = VerticalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = box_h }, preview },
        VerticalSpan:new{ width = Space.padding.small },
        label,
        state,
    }
    -- Sized by its content, not FrameContainer's width/height (its getSize
    -- ignores them), so every card fills its grid slot exactly.
    local card = FrameContainer:new{
        bordersize = border,
        radius = Space.radius.default,
        padding = pad,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, body },
    }
    return card
end

function Browser:_items()
    local Orn = O()
    local all = Orn.listAll()
    local out = {}
    for _i, e in ipairs(all) do
        local keep = self.chip == ALL
                     or (e.pack ~= nil and e.pack == self.chip)
        if keep then
            out[#out + 1] = { entry = e, off = Orn.isOff(e.name),
                              pack_off = Orn.isPackOff(e.pack) }
        end
    end
    -- A pack's plank design (theme/plank.*.png) as one more item, so it is
    -- seen and switched like an ornament. One shows at a time: the item is
    -- "on" only for the pack whose plank is on the shelf.
    local ok_t, TP = pcall(require, "lib/bookshelf_theme_pack")
    if ok_t and TP then
        local _all, packs = Orn.listAll()
        local shown = TP.activePlank()
        for _i, pack in ipairs(packs or {}) do
            if self.chip == ALL or self.chip == pack then
                for _j, e in ipairs(TP.plankEntries(pack)) do
                    out[#out + 1] = { entry = e, off = not (shown and shown.id == e.name),
                                      pack = pack, pack_off = Orn.isPackOff(pack) }
                end
            end
        end
    end
    return out
end

-- _toggle(item): switch an ornament, or a pack's plank design, on or off.
-- A plank in a switched-off pack switches the pack on too: otherwise the tap
-- changed nothing anyone could see (maintainer).
function Browser:_toggle(item)
    if item.entry.is_plank then
        if item.off and item.pack_off then O().setPackOff(item.pack, false) end
        require("lib/bookshelf_theme_pack").setPlankOn(item.entry.name, item.off)
    else
        O().setOff(item.entry.name, not item.off)
    end
    self:_changed()
end

-- _pick(item): pick mode (the long-press menu's Swap). The chosen piece
-- takes the slot; a switched-off one, or one in a switched-off pack, is
-- switched on, or the swap would put nothing there.
function Browser:_pick(item)
    if item.entry.is_plank then return end
    if item.off then O().setOff(item.entry.name, false) end
    if item.pack_off and item.entry.pack then O().setPackOff(item.entry.pack, false) end
    self.opts.pick(item.entry)
    self._dirty = true
    self._close()
end

-- _changed(rescan): redraw the browser after a switch. The shelf behind is
-- rebuilt once, when the browser closes (see show): it is almost all covered,
-- and rebuilding it per tap made tapping through a pack slow. rescan (after a
-- delete) re-lists the folders; a switch only changes what is filtered out.
function Browser:_changed(rescan)
    local ok_t, TP = pcall(require, "lib/bookshelf_theme_pack")
    if rescan then
        O().invalidate()
        if ok_t and TP then TP.invalidate() end
    elseif ok_t and TP then
        -- Which plank shows is memoised; a switch must be seen at once.
        TP.forgetChoice()
    end
    self._dirty = true
    self.items = self:_items()
    if self._config then self._config.footer_rows = self:_footerRows() end
    if self.modal then self.modal:refresh() end
end

function Browser:_chips()
    local Orn = O()
    local _all, packs = Orn.listAll()
    -- All, then one per pack. No tab for the loose ornaments on their own:
    -- All already shows them, and a tab is for something you switch as one
    -- (maintainer).
    local chips = { { key = ALL, label = _("All"), is_active = self.chip == ALL } }
    for _i, pack in ipairs(packs) do
        chips[#chips + 1] = {
            key = pack,
            label = Orn.isPackOff(pack) and T(_("%1 (off)"), pack) or pack,
            is_active = self.chip == pack,
        }
    end
    return chips
end

function Browser:_isPack(key)
    return key ~= nil and key ~= ALL
end

function Browser:_confirmDelete(item)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete %1?\n\nThe file is removed from the ornaments folder."), item.entry.name),
        ok_text = _("Delete"),
        ok_callback = function()
            if not O().delete(item.entry) then
                UIManager:show(InfoMessage:new{ text = _("Could not delete the file."), timeout = 3 })
            end
            self:_changed(true)
        end,
    })
end

function Browser:_longTap(item)
    local d
    local buttons = {
        {{
            text = item.off and _("Switch on") or _("Switch off"),
            callback = function()
                UIManager:close(d)
                self:_toggle(item)
            end,
        }},
    }
    -- The plank design is part of the pack's theme folder, not a loose file.
    if not item.entry.is_plank then
        buttons[#buttons + 1] = {{
            text = _("Delete\xe2\x80\xa6"),
            callback = function()
                UIManager:close(d)
                self:_confirmDelete(item)
            end,
        }}
    end
    d = ButtonDialog:new{ title = item.entry.name, buttons = buttons }
    UIManager:show(d)
end

-- _packAction() -> the footer's pack button: on a pack's chip it switches the
-- whole pack; anywhere else it says how to add ornaments and make packs.
function Browser:_packAction()
    return {
        -- On a pack's chip: switch the whole pack. Anywhere else it
        -- says how to add ornaments and make packs. It was a greyed
        -- "Pack" there, which said nothing about what it was for, and
        -- with no packs yet could never be used (maintainer).
        key = "pack",
        label_func = function()
            if not self:_isPack(self.chip) then return _("Add ornaments\xe2\x80\xa6") end
            return O().isPackOff(self.chip) and _("Switch pack on") or _("Switch pack off")
        end,
        on_tap = function()
            if not self:_isPack(self.chip) then
                UIManager:show(InfoMessage:new{
                    -- The shop URL is a parameter, not part of the
                    -- msgid, so a translation cannot break it.
                    text = T(_("Put PNG or SVG files in\n%1\n\nA folder of them inside it becomes a pack: it gets its own tab here, and can be switched on or off as a whole.\n\nReady-made packs:\n%2"),
                        (function()
                            -- A findable path: the settings dir can be relative.
                            local d = O().dir() or "?"
                            local ok, util = pcall(require, "ffi/util")
                            local real = ok and util.realpath and util.realpath(d)
                            return real or d
                        end)(),
                        "ko-fi.com/andyhazz/shop"),
                })
                return
            end
            O().setPackOff(self.chip, not O().isPackOff(self.chip))
            self:_changed()
        end,
    }
end

-- _footerRows() -> the footer: the pack's theme switches in their own row, only
-- for the parts this pack actually has (theme/ wallpaper, colours.json), above
-- the pack button and Close. A wallpaper or colours switch changes the whole
-- screen, so it asks for a full repaint.
function Browser:_footerRows()
    local rows = {}
    local close = { key = "close", label = self.opts.pick and _("Cancel") or _("Apply"), on_tap = self._close }
    -- Choosing a replacement: nothing to switch here, only a way out.
    if self.opts.pick then return { { close } } end
    local ok_t, TP = pcall(require, "lib/bookshelf_theme_pack")
    if ok_t and TP and self:_isPack(self.chip) then
        local th, pack, row = TP.theme(self.chip), self.chip, {}
        if th.wallpaper then
            row[#row + 1] = { key = "wallpaper",
                label_func = function()
                    return TP.activeWallpaperPack() == pack and _("Wallpaper: on") or _("Wallpaper: off")
                end,
                on_tap = function()
                    TP.setWallpaperPack(TP.activeWallpaperPack() ~= pack and pack or nil)
                    self._full = true
                    self:_changed()
                end }
        end
        if th.colours then
            row[#row + 1] = { key = "colours",
                label_func = function()
                    return TP.activeColoursPack() == pack and _("Colors: on") or _("Colors: off")
                end,
                on_tap = function()
                    TP.setColoursPack(TP.activeColoursPack() ~= pack and pack or nil)
                    self._full = true
                    self:_changed()
                end }
        end
        if #row > 0 then rows[#rows + 1] = row end
    end
    rows[#rows + 1] = { self:_packAction(), close }
    return rows
end

-- show(on_change, opts): on_change() runs once when the browser closes, if
-- anything changed, so the caller can redraw the shelf. opts.pick(entry)
-- turns it into a chooser (the long-press menu's Swap): tapping a piece
-- picks it and closes.
function Browser.show(on_change, opts)
    local self = setmetatable({ chip = ALL, on_change = on_change, opts = opts or {} },
                              { __index = Browser })
    local ok_t, TP = pcall(require, "lib/bookshelf_theme_pack")
    local function plankId()
        local pl = ok_t and TP and TP.activePlank()
        return pl and pl.id or nil
    end
    local plank_before = plankId()
    O().beginDeferred()
    self.items = self:_items()
    local function cols() return Screen:getWidth() > Screen:getHeight() and 4 or 3 end
    local function close()
        if self.modal then UIManager:close(self.modal); self.modal = nil end
    end
    -- However it closes (Close, the title's X, Back): write the switches,
    -- rebuild the shelf once, and repaint the whole screen only if what shows
    -- changed there: a plank design's lower band hangs below the last row,
    -- into the strip a shelf refresh stops short of, and a wallpaper or a
    -- colour theme is the whole screen.
    local function closed()
        O().endDeferred()
        if not self._dirty then return end
        if self.on_change then pcall(self.on_change) end
        if self._full or plankId() ~= plank_before then
            UIManager:setDirty("all", "full")
        end
    end
    local config = {
        title = self.opts.pick and _("Swap for") or _("Ornaments"),
        no_search = true,
        grid_cols = cols,
        cells_per_page = function() return cols() * 3 end,
        rows_per_page = 6,
        chip_strip = function() return self:_chips() end,
        on_chip_tap = function(key)
            self.chip = key
            self.items = self:_items()
            if self._config then self._config.footer_rows = self:_footerRows() end
        end,
        cell_renderer = Browser._renderCell,
        on_cell_tap = function(item)
            if self.opts.pick then self:_pick(item) else self:_toggle(item) end
        end,
        cell_long_tap = function(item) self:_longTap(item) end,
        item_count = function() return #self.items end,
        item_at = function(idx) return self.items[idx] end,
        empty_state = function(w, _h)
            local dir = O().dir() or "?"
            return CenterContainer:new{
                dimen = Geom:new{ w = w, h = _h },
                TextBoxWidget:new{
                    text = T(_("No ornaments here.\n\nDrop PNG or SVG files into\n%1\nor a folder of them, which becomes a pack."), dir),
                    face = Font:getFace("cfont", 16),
                    width = math.floor(w * 0.9),
                    alignment = "center",
                },
            }
        end,
        footer_rows = {},
        on_closed = closed,
    }
    self._close, self._config = close, config
    config.footer_rows = self:_footerRows()
    self.modal = LibraryModal:new{ config = config }
    UIManager:show(self.modal)
    return self
end

return Browser
