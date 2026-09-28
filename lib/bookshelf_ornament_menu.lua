-- lib/bookshelf_ornament_menu.lua
-- Long-press an ornament on the shelf: adjust it where it stands. Size,
-- padding and height nudge live (the shelf redraws under the menu); hang,
-- mirror and a tap action; swap it for another piece, or shuffle them all;
-- reset to what its pack says.
--
-- Every change is the READER's (lib/bookshelf_ornaments readerSet), kept in
-- the ornaments folder's own ornaments.json keyed by the piece's relative
-- path, so it follows the piece onto every shelf and survives a pack update.
-- The file is written once, when the menu closes.
--
-- The nudge rows follow the bookends line editor: glyph buttons either side
-- of the value, a tap is a small step and a hold a big one, and tapping the
-- value resets it. Up and down are its Nerd Font chevrons.
local _ = require("lib/bookshelf_i18n").gettext
local T = require("ffi/util").template

local M = {}

local CHEV_UP   = "\xEE\xA1\x82"   -- U+E842 mdi-chevron-up
local CHEV_DOWN = "\xEE\xA0\xBF"   -- U+E83F mdi-chevron-down
local GLYPH_SIZE = 28

-- Steps (small, big). Size in its own multiple; padding in the books' stand
-- height; height (lift) in the piece's own height.
M.STEPS = {
    scale = { 0.05, 0.25 },
    pad   = { 0.02, 0.10 },
    lift  = { 0.02, 0.10 },
}

local function O() return require("lib/bookshelf_ornaments") end
local Deck = require("lib/bookshelf_ornament_deck")

local function pct(v) return string.format("%+d%%", math.floor((v or 0) * 100 + 0.5)) end

-- nudged(entry, field, delta) -> the new value, clamped, rounded to the step
-- grid so repeated taps do not drift (0.1 + 0.2 ~= 0.3).
function M.nudged(entry, field, delta)
    local cur = entry[field] or O().FIELDS[field].default or 0
    local v = O().cleanField(field, cur + delta)
    return math.floor(v * 100 + 0.5) / 100
end

-- offsetFor(piece, screen_h) -> the vertical move that keeps the menu off the
-- piece being adjusted: a quarter screen down for a piece in the top half,
-- up for one in the bottom half, so the live preview stays in sight.
function M.offsetFor(piece, screen_h)
    if not (piece and piece.y and screen_h) then return 0 end
    local mid = piece.y + (piece.h or 0) / 2
    local q = math.floor(screen_h / 4)
    return (mid < screen_h / 2) and q or -q
end

-- show(entry, bw, piece): the menu for one piece; piece is where it stands
-- on screen (its dimen), for keeping the menu clear of it.
function M.show(entry, bw, piece)
    local UIManager    = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Orn = O()
    -- The LIVE entry for this piece: the shelf's own may be older than the
    -- last rescan (see Orn.current). Every label below reads this upvalue.
    entry = Orn.current(entry)
    local dialog

    local Screen = require("device").screen
    local dy = M.offsetFor(piece, Screen:getHeight())
    local function place()
        if dialog and dialog.movable and dy ~= 0 then
            dialog.movable:setMovedOffset({ x = 0, y = dy })
        end
    end
    local function redraw()
        if bw and bw._rebuild then
            -- The piece's size moves where rows, and so pages, break later
            -- on: those are re-learnt, and this page keeps its start.
            if bw._dropOrnPages then bw:_dropOrnPages(true) end
            bw:_rebuild()
            UIManager:setDirty(bw, "ui")
        end
        -- reinit builds a new MovableContainer: put the offset back.
        if dialog then dialog:reinit(); place() end
    end
    local function set(field, value)
        Orn.readerSet(entry, field, value)
        entry = Orn.current(entry)
        redraw()
    end
    local function nudge(field, sign, big)
        local step = M.STEPS[field][big and 2 or 1]
        set(field, M.nudged(entry, field, sign * step))
    end
    local function glyph(text, field, sign)
        return {
            text = text, font_face = "symbols", font_size = GLYPH_SIZE,
            callback      = function() nudge(field, sign, false) end,
            hold_callback = function() nudge(field, sign, true) end,
        }
    end
    local function plusMinus(field, label_func)
        return {
            { text = "\xE2\x88\x92", callback = function() nudge(field, -1, false) end,   -- U+2212 minus
              hold_callback = function() nudge(field, -1, true) end },
            { text_func = label_func, callback = function() set(field, nil) end },
            { text = "+", callback = function() nudge(field, 1, false) end,
              hold_callback = function() nudge(field, 1, true) end },
        }
    end

    local MIRROR_NEXT = { off = "always", always = "alternate", alternate = "off" }
    local MIRROR_LABEL = {
        off       = _("Mirror: off"),
        always    = _("Mirror: always"),
        alternate = _("Mirror: every other time"),
    }

    local function closeAnd(fn)
        return function()
            UIManager:close(dialog)
            if fn then fn() end
        end
    end

    local buttons = {
        plusMinus("scale", function()
            return T(_("Size: %1"), string.format("%d%%", math.floor((entry.scale or 1) * 100 + 0.5)))
        end),
        plusMinus("pad", function()
            return T(_("Padding: %1"), pct(entry.pad))
        end),
        {
            glyph(CHEV_UP, "lift", 1),
            { text_func = function() return T(_("Height: %1"), pct(entry.lift)) end,
              callback = function() set("lift", nil) end },
            glyph(CHEV_DOWN, "lift", -1),
        },
        {{
            text_func = function()
                return entry.hang and _("Hang from the shelf above: on")
                                   or _("Hang from the shelf above: off")
            end,
            callback = function() set("hang", not entry.hang) end,
        }},
        {{
            text_func = function() return MIRROR_LABEL[entry.mirror or "off"] end,
            callback = function() set("mirror", MIRROR_NEXT[entry.mirror or "off"]) end,
        }},
        {{
            text_func = function()
                local tap = entry.tap
                return tap and T(_("Tap action: %1"), tap.label or _("set"))
                            or _("Tap action: none")
            end,
            callback = function() M.chooseTap(entry, redraw) end,
        }},
        {{
            -- A new order for every piece on every shelf (the "Bookshelf:
            -- shuffle ornaments" action), which also clears every swap.
            text = _("Shuffle all"),
            callback = closeAnd(function()
                if bw and bw.onBookshelfShuffleOrnaments then bw:onBookshelfShuffleOrnaments() end
            end),
        }},
        {
            { text = _("Swap"), callback = closeAnd(function()
                -- The browser in pick mode: the chosen piece takes this one's
                -- place in the order, and this one takes the chosen piece's.
                require("lib/bookshelf_ornament_browser").show(function()
                    if bw and bw._rebuild then bw:_rebuild(); UIManager:setDirty(bw, "ui") end
                end, { pick = function(chosen)
                    Deck.swap(entry.name, chosen.name)
                end })
            end) },
            { text = _("Reset"), callback = function()
                Orn.readerReset(entry)
                entry = Orn.current(entry)
                redraw()
            end },
            { text = _("Done"), callback = closeAnd() },
        },
    }
    dialog = ButtonDialog:new{
        title = Orn.displayName(entry) .. (entry.pack and (" (" .. entry.pack .. ")") or ""),
        title_align = "center",
        buttons = buttons,
        -- Rapid nudges land outside now and then; a tap there must not close
        -- it (as every nudge dialog). Done or Back closes.
        dismissable = false,
    }
    -- However it closes (Done, a tap outside, Back): write the reader's file
    -- once. ButtonDialog has no close callback of its own for all three.
    place()
    local closeWidget = dialog.onCloseWidget
    function dialog:onCloseWidget(...)
        Orn.saveReader()
        if closeWidget then return closeWidget(self, ...) end
    end
    UIManager:show(dialog)
    return dialog
end

-- chooseTap(entry, done): the Action module's chooser, plus "no action".
function M.chooseTap(entry, done)
    local UIManager    = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Chooser      = require("lib/bookshelf_action_chooser")
    local d
    local function close(fn)
        return function() UIManager:close(d); if fn then fn() end end
    end
    local rows = Chooser.actionRows(close, function(fields)
        O().readerSet(entry, "tap", {
            action = fields.action, plugin = fields.plugin,
            internal = fields.internal, label = fields.label,
        })
        if done then done() end
    end)
    table.insert(rows, 1, {{
        text = _("No action"),
        callback = close(function()
            O().readerSet(entry, "tap", nil)
            if done then done() end
        end),
    }})
    d = ButtonDialog:new{ title = _("Tap action"), title_align = "center",
                          width_factor = 0.65, buttons = rows }
    UIManager:show(d)
end

return M
