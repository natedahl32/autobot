local mq = require('mq')

local BossRoles = require('AutoBot.lib.bossroles')
local CWTN = require('AutoBot.lib.cwtn')
local RaidBoss = require('AutoBot.lib.raidboss')
local Spawn = require('AutoBot.lib.spawn')

local M = {}

M.id = "oow_coa_jelvan"

local TORMENTOR_NAMES = {
  "Tanthi the Tormentor",
  "Tantho the Tormentor",
  "Tanthu the Tormentor",
}

local TORMENTOR_NAME_MAP = {
  ["tanthi the tormentor"] = true,
  ["tantho the tormentor"] = true,
  ["tanthu the tormentor"] = true,
}

local HEALER_CLASS_MAP = {
  CLR = true,
  DRU = true,
  SHM = true,
}

local boss = RaidBoss.new(M.id, "Tanthi the Tormentor", {
  opener_mode = 'offtank_first',
  ma_target_source = 'xtarget',
  ma_priority = {},
  offtank_ordered_pull = true,
})

M.help = boss.standard_help({
  title = 'Omens of War - Citadel of Anguish - Jelvan',
  include_ot = true,
  extra = {
    'Notes:',
    '  Put 1 group in each of the spawn locations for the bosses (NE, NW, S)',
    '  Tanks in group put on Tank mode (CWTN Mode 4) and group members put in mode 2',
    '  DPS pauses automatically at each new 5% HP bucket on the tormentor they are attacking.',
    '  Healers (CLR/DRU/SHM) are excluded from DPS pause/resume behavior.',
    '  Use /autobot oow_coa_jelvan attackresume to resume DPS manually.',
  },
})

local last_pause_bucket = nil
local dps_paused = false

local function say(msg)
  mq.cmdf('/dga /echo [Jelvan:%s] %s', mq.TLO.Me.Name() or 'Me', msg)
end

local function class_short()
  return CWTN.class_short()
end

local function is_healer()
  local short = class_short()
  return short and HEALER_CLASS_MAP[short] == true or false
end

local function norm_name(name)
  name = (name or ''):lower()
  name = name:gsub('_', ' ')
  name = name:gsub('%d+$', '')
  name = name:gsub('%s+', ' ')
  name = name:gsub('^%s+', ''):gsub('%s+$', '')
  return name
end

local function target_is_tormentor()
  local t = mq.TLO.Target
  if not t or not t() then return false end

  local name = t.CleanName and t.CleanName() or t.Name()
  name = norm_name(name)

  return TORMENTOR_NAME_MAP[name] == true
end

local function target_hp()
  local t = mq.TLO.Target
  if not t or not t() then return nil end

  local hp = t.PctHPs and t.PctHPs() or nil
  if hp == nil then
    hp = t.PctHP and t.PctHP() or nil
  end

  return hp
end

local function hp_bucket_5(hp)
  if not hp then return nil end
  hp = tonumber(hp)
  if not hp then return nil end
  if hp < 0 then hp = 0 end
  if hp > 100 then hp = 100 end

  return math.floor(hp / 5)
end

local function pause_dps(reason)
  if is_healer() then
    return
  end

  CWTN.pause_on()
  mq.cmd('/attack off')
  mq.cmd('/pet back off')
  dps_paused = true

  if reason and reason ~= '' then
    say(reason)
  end
end

local function resume_dps(reason)
  if is_healer() then
    return
  end

  CWTN.pause_off()
  mq.cmd('/attack on')
  mq.cmd('/pet attack')
  dps_paused = false

  if reason and reason ~= '' then
    say(reason)
  end
end

local function maybe_pause_for_bucket()
  if is_healer() then
    return
  end

  if dps_paused then
    return
  end

  if not target_is_tormentor() then
    return
  end

  local hp = target_hp()
  local bucket = hp_bucket_5(hp)
  if bucket == nil then
    return
  end

  if last_pause_bucket == nil then
    last_pause_bucket = bucket
    return
  end

  if bucket < last_pause_bucket then
    last_pause_bucket = bucket
    pause_dps(string.format(
      'Reached new 5%% HP bucket on %s at %s%%. DPS paused. Use /autobot %s attackresume to continue.',
      tostring(mq.TLO.Target.CleanName and mq.TLO.Target.CleanName() or mq.TLO.Target.Name() or 'target'),
      tostring(hp),
      M.id
    ))
  end
end

local function find_assigned_tormentor()
  local mobs = BossRoles.get_offtank_mobs(M.id, mq.TLO.Me.Name() or '')
  if not mobs or #mobs == 0 then
    return nil
  end

  for _, mobName in ipairs(mobs) do
    local s = Spawn.spawn_by_name(mobName)
    if s and s() then
      return s
    end
  end

  return nil
end

local function proactive_offtank_tick()
  if not boss.running then return end
  if not boss.is_ot() then return end

  local s = find_assigned_tormentor()
  if not s or not s() then
    return
  end

  local id = s.ID()
  if not id or id <= 0 then
    return
  end

  local currentTarget = mq.TLO.Target
  local currentId = currentTarget and currentTarget() and currentTarget.ID() or nil

  if currentId ~= id then
    Spawn.target_id(id)
  end

  mq.cmd('/pet attack')
  mq.cmd('/attack on')
end

function M.start(ctx)
  boss.start()
  last_pause_bucket = nil
  dps_paused = false

  local summary = boss.role_summary()
  if summary then
    say("Role loaded: " .. summary)
  end
end

function M.stop(ctx)
  boss.stop()
  last_pause_bucket = nil
  dps_paused = false

  local summary = boss.role_summary()
  if summary then
    say("Module stopped. Role=" .. summary)
  end
end

function M.tick(ctx)
  -- Proactive OT pickup for Jelvan: do this whenever the module is running,
  -- even before startfight.
  proactive_offtank_tick()

  -- Normal shared boss logic
  boss.tick()

  -- 5% pause logic
  maybe_pause_for_bucket()
end

M.commands = boss.merge_commands(
  boss.standard_commands(M, say),
  boss.standard_role_commands(say, { include_ot = true }),
  {
    attackresume = function(ctx, args)
      if is_healer() then
        return
      end

      local hp = target_hp()
      last_pause_bucket = hp_bucket_5(hp)
      resume_dps('DPS resumed manually.')
    end,
  }
)

return M