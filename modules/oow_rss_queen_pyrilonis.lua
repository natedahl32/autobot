local mq = require('mq')

local RaidBoss = require('AutoBot.lib.raidboss')
local BossRoles = require('AutoBot.lib.bossroles')
local Spawn = require('AutoBot.lib.spawn')

local M = {}

M.id = "oow_rss_queen_pyrilonis"

-- Replace these with the real mez/fear buff names you use on this encounter.
local MEZ_BUFF_NAMES = {
  -- ["Your Mez Spell Name"] = true,
}

local FEAR_BUFF_NAMES = {
  -- ["Your Fear Spell Name"] = true,
}

local boss = RaidBoss.new(M.id, "Queen Pyrilonis", {
  opener_mode = 'offtank_first',
  ma_target_source = 'spawns',
  ma_priority = {
    'a fire construct',
    'a raging chimera',
    { 'princess', 'Princess' },
  },
  offtank_ordered_pull = true,
  include_ot = true,
  mez_buff_names = MEZ_BUFF_NAMES,
  fear_buff_names = FEAR_BUFF_NAMES,
})

M.help = boss.standard_help({
  title = 'Omens of War - Riftseekers Sanctum - Queen Pyrilonis',
  include_ot = true,
  extra = {
    'Notes:',
    '  Main Assist priority: a fire construct > a raging chimera > any Princess mob.',
    '  Offtanks should be assigned specific Princess mobs with otsetmobs.',
    '  Offtank logic only picks targets from XTarget and skips mezzed/fear targets.',
  },
})

local function say(msg)
  mq.cmdf('/dga /echo [QueenPyrilonis:%s] %s', mq.TLO.Me.Name() or 'Me', msg)
end

local function norm_name(name)
  name = (name or ''):lower()
  name = name:gsub('_', ' ')
  name = name:gsub('%d+$', '')
  name = name:gsub('%s+', ' ')
  name = name:gsub('^%s+', ''):gsub('%s+$', '')
  return name
end

local function iter_xtarget_spawns()
  local cnt = mq.TLO.Me.XTarget()
  cnt = (type(cnt) == 'function') and cnt() or (cnt or 0)
  if not cnt or cnt <= 0 then
    return function() end
  end

  local i = 0
  return function()
    while true do
      i = i + 1
      if i > cnt then return nil end

      local xt = mq.TLO.Me.XTarget(i)
      if xt and xt() then
        local id = xt.ID()
        if id and id > 0 then
          local s = mq.TLO.Spawn(('id %d'):format(id))
          if s and s() then
            return s
          end
        end
      end
    end
  end
end

local function is_main_assist()
  return BossRoles.is_ma(M.id)
end

local function spawn_is_ccd(spawnObj)
  if not spawnObj or not spawnObj() then return false end

  if next(MEZ_BUFF_NAMES) ~= nil and Spawn.spawn_has_any_buff(spawnObj, MEZ_BUFF_NAMES) then
    return true
  end

  if next(FEAR_BUFF_NAMES) ~= nil and Spawn.spawn_has_any_buff(spawnObj, FEAR_BUFF_NAMES) then
    return true
  end

  return false
end

local function matches_priority(spawnObj, priority)
  if not spawnObj or not spawnObj() then return false end

  local name = norm_name(spawnObj.Name() or '')
  if name == '' then return false end

  if priority == 'fire_construct' then
    return name == 'a fire construct'
  end

  if priority == 'raging_chimera' then
    return name == 'a raging chimera'
  end

  if priority == 'princess' then
    return name:find('princess', 1, true) ~= nil
  end

  return false
end

local function find_ma_target()
  local priorities = { 'fire_construct', 'raging_chimera', 'princess' }

  for _, priority in ipairs(priorities) do
    local best = nil
    local bestDist = 999999

    for s in iter_xtarget_spawns() do
      if matches_priority(s, priority) and not spawn_is_ccd(s) then
        local d = s.Distance() or 999999
        if d < bestDist then
          best = s
          bestDist = d
        end
      end
    end

    if best then
      return best, priority
    end
  end

  return nil, nil
end

local function main_assist_tick()
  if not boss.running then return end
  if not boss.fight_started then return end
  if not is_main_assist() then return end

  local target, priority = find_ma_target()
  if not target then
    return
  end

  local id = target.ID()
  if not id or id <= 0 then
    return
  end

  Spawn.target_id(id)
  mq.cmd('/pet attack')
  mq.cmd('/attack on')
end

function M.start(ctx)
  boss.start()

  local summary = boss.role_summary()
  if summary then
    say("Role loaded: " .. summary)
  end
end

function M.stop(ctx)
  boss.stop()

  local summary = boss.role_summary()
  if summary then
    say("Module stopped. Role=" .. summary)
  end
end

function M.tick(ctx)
  boss.tick()
  main_assist_tick()
end

M.commands = boss.merge_commands(
  boss.standard_commands(M, say),
  boss.standard_role_commands(say, { include_ot = true })
)

return M