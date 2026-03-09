-- AutoBot/lib/spawn.lua
local mq = require('mq')

local M = {}

function M.spawn_by_name(name)
  local s = mq.TLO.Spawn(name)
  if s and s() then return s end
  return nil
end

function M.nav_to_id(spawnID)
  mq.cmdf('/nav id %d', spawnID)
end

function M.wait_until_close(spawnID, useDistance, timeoutMs)
  useDistance = useDistance or 12
  timeoutMs = timeoutMs or 8000
  local start = mq.gettime()

  while mq.gettime() - start < timeoutMs do
    local s = mq.TLO.Spawn(('id %d'):format(spawnID))
    if not s() then return false end
    if (s.Distance() or 9999) <= useDistance then return true end
    mq.delay(100)
  end
  return false
end

function M.wait_until_spawn_gone(spawnID, timeoutMs)
  timeoutMs = timeoutMs or 60000
  local start = mq.gettime()
  while mq.gettime() - start < timeoutMs do
    local s = mq.TLO.Spawn(('id %d'):format(spawnID))
    if not s or not s() then return true end
    mq.delay(100)
  end
  return false
end

function M.target_id(id)
  mq.cmdf('/target id %d', id)
  mq.delay(150)
end

function M.face_target()
  mq.cmd('/face fast')
  mq.delay(100)
  mq.cmd('/stop')
  mq.delay(100)
end

function M.open_and_verify_despawn(chestID, verifyMs)
  verifyMs = verifyMs or 2500
  mq.cmd('/open')
  mq.delay(300)

  local start = mq.gettime()
  while mq.gettime() - start < verifyMs do
    local s = mq.TLO.Spawn(('id %d'):format(chestID))
    if not s() then return true end
    mq.delay(100)
  end
  return false
end

function M.spawn_has_buff(spawn, buffName)
  if not spawn or not spawn() then return false end
  local b = spawn.Buff(buffName)
  return b and b() or false
end

function M.spawn_has_any_buff(spawn, buffMap)
  if not spawn or not spawn() then return false end
  for buffName,_ in pairs(buffMap) do
    if M.spawn_has_buff(spawn, buffName) then
      return true
    end
  end
  return false
end

-- Engage a spawn by ID:
-- - nav to it (optional)
-- - target it
-- - /pet attack, /attack on
-- - wait until it despawns
-- Returns: true if spawn despawned, false if timeout/failure
function M.engage_and_kill_id(spawnID, label, timeoutMs, engageDistance)
  if not spawnID or spawnID <= 0 then return false end
  label = label or ("id " .. tostring(spawnID))
  timeoutMs = timeoutMs or 120000
  engageDistance = engageDistance or 18

  local s = mq.TLO.Spawn(('id %d'):format(spawnID))
  if not s or not s() then return false end

  -- Navigate in if needed
  local dist = s.Distance() or 999999
  if dist > engageDistance then
    mq.cmdf('/nav id %d', spawnID)
    local reached = M.wait_until_close(spawnID, engageDistance, 30000)
    if not reached then
      mq.cmd('/attack off')
      return false
    end
    mq.delay(150)
  end

  -- Engage
  M.target_id(spawnID)
  mq.cmd('/pet attack')
  mq.cmd('/attack on')

  local died = M.wait_until_spawn_gone(spawnID, timeoutMs)

  mq.cmd('/attack off')
  return died
end

function M.is_alive_npc(s)
  if not s or not s() then return false end

  -- Prefer explicit checks if available
  local okDead, dead = pcall(function()
    local d = s.Dead
    return d and d() == true
  end)
  if okDead and dead then return false end

  local okType, typ = pcall(function()
    local t = s.Type
    return t and t() or nil
  end)
  if okType and typ and tostring(typ):lower():find('corpse', 1, true) then
    return false
  end

  return true
end

return M