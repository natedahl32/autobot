-- AutoBot/lib/trade.lua
local mq = require('mq')

local M = {}

local function _bool(v)
  if type(v) == 'function' then v = v() end
  return v ~= nil and v ~= false and v ~= 0
end

function M.open_give_to_target()
  if not mq.TLO.Target() then return false end
  if mq.TLO.Target.Type() ~= 'NPC' then return false end

  -- Open GiveWnd (trade) with target
  mq.cmd('/click right target')
  mq.delay(150)
  return _bool(mq.TLO.Window('GiveWnd').Open)
end

function M.give_item_to_target(itemName, quantity)
  if not itemName or itemName == '' then return false, 'no itemName' end
  if not mq.TLO.Target() then return false, 'no target' end

  -- Ensure GiveWnd is open
  if not _bool(mq.TLO.Window('GiveWnd').Open) then
    if not M.open_give_to_target() then
      return false, 'GiveWnd not open'
    end
  end

  -- Pick up item onto cursor (FindItem exact name works here too, but itemnotify name is fine)
  mq.cmdf('/itemnotify "%s" leftmouseup', itemName)
  mq.delay(150)

  if not mq.TLO.Cursor() then
    return false, 'failed to pick item to cursor'
  end

  -- Drop on first give slot
  -- Common: GiveWnd -> "GVW_ItemSlot1" or "GVW_Item1"
  if _bool(mq.TLO.Window('GiveWnd').Child('GVW_ItemSlot1')) then
    mq.cmd('/notify GiveWnd GVW_ItemSlot1 leftmouseup')
  else
    mq.cmd('/notify GiveWnd GVW_Item1 leftmouseup')
  end
  mq.delay(150)

  -- Click Give
  if _bool(mq.TLO.Window('GiveWnd').Child('GVW_GiveButton')) then
    mq.cmd('/notify GiveWnd GVW_GiveButton leftmouseup')
  else
    mq.cmd('/notify GiveWnd Give_Button leftmouseup')
  end

  mq.delay(300)

  -- If quantity > 1, we’d need to repeat, but epic turn-ins here are 1x.
  return true
end

return M