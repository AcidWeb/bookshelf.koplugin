--[[
KOReader's own gestures under a full-screen view of ours: the edge swipes for
brightness and warmth, the top swipe or tap for KOReader's menu, the diagonal
swipe for a refresh, corner taps. A view covering the screen is the top
widget, so these reach it first; this hands them on. The same walk
BookshelfWidget:handleEvent and the full-screen micro-module view do.

  gesture(ev, fm) -> true when one of the file manager's touch zones took the
      gesture: KOReader's own ("filemanager_*") and the ones the reader set up
      in its gesture manager, nothing else.
  event(event, fm) -> the file manager's answer: a zone's action arrives as a
      SEPARATE event (UIManager:sendEvent reaches only the top widget), which
      has to reach the file manager for its DeviceListener to act on it.
]]
local M = {}

local function fmInstance(fm)
    if fm then return fm end
    local ok, FM = pcall(require, "apps/filemanager/filemanager")
    return ok and FM and FM.instance or nil
end

function M.gesture(ev, fm)
    fm = fmInstance(fm)
    if not (fm and ev) then return false end
    local user = (fm.gestures and fm.gestures.gestures) or {}
    local lists = { fm._ordered_touch_zones }
    for _i, child in ipairs(fm) do
        if child ~= fm.file_chooser and type(child) == "table" and child._ordered_touch_zones then
            lists[#lists + 1] = child._ordered_touch_zones
        end
    end
    for _i, zones in ipairs(lists) do
        for _j, z in ipairs(zones or {}) do
            local id = z.def and z.def.id
            local allowed = id and (id:find("^filemanager_") or user[id])
            if allowed and z.gs_range:match(ev) and z.handler(ev) then return true end
        end
    end
    return false
end

-- Never handed on: our own lifecycle, and broadcasts the shelf re-sends.
local NEVER = { onCloseWidget = true, onFlushSettings = true, onShow = true, onClose = true }

function M.event(event, fm)
    if not event or NEVER[event.handler] or event._bookshelf_from_broadcast then return nil end
    fm = fmInstance(fm)
    if fm then return fm:handleEvent(event) end
    return nil
end

return M
