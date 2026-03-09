-- AutoBot/lib/items.lua
local mq = require('mq')

local M = {}

local function _to_bool(v)
  if v == nil then return false end

  -- Try to call it (works for MQ TLO handles which are userdata with __call)
  local ok, res = pcall(function()
    return v()
  end)

  if ok then
    return res ~= nil and res ~= false and res ~= 0
  end

  -- If it isn't callable, fall back to "exists"
  return v ~= nil and v ~= false and v ~= 0
end

function M.cursor_name()
  local c = mq.TLO.Cursor
  if _to_bool(c) then
    local n = c.Name()
    if n and n ~= '' then return n end
  end
  return nil
end

-- Exact item name check (bags/equipped/etc). Returns bool.
function M.have_item(name)
  if not name or name == '' then return false end
  local fi = mq.TLO.FindItem(name)
  return _to_bool(fi)
end

function M.wait_for_item(itemName, timeoutMs, pollMs)
  if not itemName or itemName == '' then return false end
  timeoutMs = timeoutMs or 15000
  pollMs = pollMs or 200

  local start = mq.gettime()
  while mq.gettime() - start < timeoutMs do
    if M.have_item(itemName) then
      return true
    end
    mq.delay(pollMs)
  end
  return false
end

-- Substring search (like FindItem("Suffusive")). Returns item TLO or nil.
function M.find_item(substr)
  if not substr or substr == '' then return nil end
  local fi = mq.TLO.FindItem(substr)
  if _to_bool(fi) then return fi end
  return nil
end

local function safe_name(itemObj)
  if not itemObj or not itemObj() then return nil end
  local n = itemObj.Name()
  return (n and n ~= '') and n or nil
end

function M.inv_item(slotName)
  local inv = mq.TLO.Me.Inventory(slotName)
  if inv and inv() then return inv end
  return nil
end

function M.equipped_name(slotName)
  return safe_name(M.inv_item(slotName))
end

function M.contains_ci(hay, needle)
  if not hay or not needle then return false end
  return string.find(string.lower(hay), string.lower(needle), 1, true) ~= nil
end

function M.cursor_item_name_if_contains(substr)
  local cur = mq.TLO.Cursor
  if cur and cur() then
    local cn = cur.Name()
    if M.contains_ci(cn, substr) then
      return cn
    end
  end
  return nil
end

function M.find_item_name_by_substring(substr)
  -- cursor first (loot often lands here)
  local cn = M.cursor_item_name_if_contains(substr)
  if cn then return cn, 'cursor' end

  -- bags search by substring
  local fi = mq.TLO.FindItem(substr)
  if fi and fi() then
    local n = fi.Name()
    if M.contains_ci(n, substr) then
      return n, 'bags'
    end
  end

  return nil, nil
end

function M.equip_item_by_name(itemName, verify_fn, timeoutMs)
  if not itemName or itemName == '' then return false end
  timeoutMs = timeoutMs or 2500

  -- If it's on cursor, move to inventory first
  if mq.TLO.Cursor() and mq.TLO.Cursor.Name() == itemName then
    mq.cmd('/autoinventory')
    mq.delay(250)
  end

  mq.cmdf('/itemnotify "%s" leftmouseup', itemName)
  mq.delay(350)

  if not verify_fn then return true end

  local start = mq.gettime()
  while mq.gettime() - start < timeoutMs do
    if verify_fn() then return true end
    mq.delay(100)
  end
  return false
end

function M.item_has_clicky(itemObj)
  if not itemObj or not itemObj() then return false end
  local ok, res = pcall(function()
    local c = itemObj.Clicky
    return c and c() ~= nil and c() ~= false and c() ~= 0
  end)
  return ok and res or false
end

function M.item_clicky_ready(itemObj)
  if not itemObj or not itemObj() then return false end
  local ok, res = pcall(function()
    local t = itemObj.TimerReady
    if t then return t() == true end
    return false
  end)
  if ok and res ~= nil then return res end
  -- fallback: if we can't query, treat as ready (caller should throttle)
  return true
end

function M.use_item_by_name(itemName)
  if not itemName or itemName == '' then return false end
  mq.cmdf('/useitem "%s"', itemName)
  return true
end

-- Save current MH/OH names (for restoring after bane expires / on stop)
function M.save_weapons()
  return {
    main = M.equipped_name('Mainhand'),
    off  = M.equipped_name('Offhand'),
  }
end

function M.restore_weapons(saved)
  if not saved then return end
  mq.cmd('/attack off')
  mq.delay(100)

  if saved.main and saved.main ~= '' then
    mq.cmdf('/itemnotify "%s" leftmouseup', saved.main)
    mq.delay(250)
  end
  if saved.off and saved.off ~= '' then
    mq.cmdf('/itemnotify "%s" leftmouseup', saved.off)
    mq.delay(250)
  end
end

function M.set_lootly_keep(itemName, count)
    if count then
        mq.cmdf('/setitem Keep|%s "%s"', count, itemName)
    else
        mq.cmdf('/setitem Keep "%s"', itemName)
    end
end

-- If bane expired and hands are empty, re-equip saved MH/OH for add DPS
function M.equip_saved_weapons_if_empty(saved)
  if not saved then return false end

  local mh = M.equipped_name('Mainhand')
  local oh = M.equipped_name('Offhand')

  local did = false

  if (not mh or mh == '') and saved.main and saved.main ~= '' then
    mq.cmdf('/itemnotify "%s" leftmouseup', saved.main)
    mq.delay(250)
    did = true
  end

  if (not oh or oh == '') and saved.off and saved.off ~= '' then
    mq.cmdf('/itemnotify "%s" leftmouseup', saved.off)
    mq.delay(250)
    did = true
  end

  return did
end

return M