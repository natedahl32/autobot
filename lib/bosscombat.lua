local mq = require('mq')
local Spawn = require('AutoBot.lib.spawn')

local M = {}

function M.boss_targeted(bossName)
  if not mq.TLO.Target() then return false end
  local n = mq.TLO.Target.Name()
  return n == bossName
end

function M.target_boss(bossName)
  local boss = Spawn.spawn_by_name(bossName)
  if not boss or not boss() then return nil end
  local id = boss.ID()
  if not id or id <= 0 then return nil end
  Spawn.target_id(id)
  return boss
end

function M.boss_distance()
  if not mq.TLO.Target() then return 9999 end
  local d = mq.TLO.Target.Distance()
  return d or 9999
end

function M.keep_on_boss(bossName, attackDistance, navTimeoutMs)
  local boss = Spawn.spawn_by_name(bossName)
  if not boss then
    mq.cmd('/attack off')
    return false, 'boss not found'
  end

  local id = boss.ID()
  if not id or id <= 0 then
    mq.cmd('/attack off')
    return false, 'invalid boss id'
  end

  local dist = boss.Distance() or 999999
  if dist > (attackDistance or 18) then
    mq.cmdf('/nav id %d', id)
    local reached = Spawn.wait_until_close(id, attackDistance or 18, navTimeoutMs or 30000)
    if not reached then
      mq.cmd('/attack off')
      return false, 'nav timeout'
    end
    mq.delay(150)
  end

  Spawn.target_id(id)
  mq.cmd('/pet attack')

  if (mq.TLO.Target.Distance() or 9999) <= (attackDistance or 18) then
    mq.cmd('/attack on')
  else
    mq.cmd('/attack off')
  end

  return true
end

-- Fire one ranged attack to get on the hate/rampage list.
-- You can swap this later to the best command for each class.
function M.ranged_tag_boss(bossName)
  local boss = M.target_boss(bossName)
  if not boss then return false, 'boss not found' end

  mq.cmd('/attack off')
  mq.delay(100)

  -- Minimal first pass: use ranged attack keybind/command.
  -- Replace later with class-specific better options if needed.
  mq.cmd('/doability Ranged Attack')
  mq.delay(500)

  return true
end

return M