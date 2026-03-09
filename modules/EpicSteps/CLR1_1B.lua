-- AutoBot/modules/EpicSteps/CLR1_1B.lua
local mq = require('mq')

local Spawn = require('AutoBot.lib.spawn')
local Items = require('AutoBot.lib.items')
local Trade = require('AutoBot.lib.trade')

local Step = {}

Step.id = '1B'
Step.name = "Turn in Bergurgle's Crown to Shmendrik, wait for Natasha to attack, kill Shmendrik + spirit, turn in Damaged Goblin Crown"
Step.next = '1C' -- placeholder

-- =========================
-- CONSTANTS
-- =========================
local ZONE_LONG = 'Lake Rathetear'
local ZONE_SHORT = 'lakerathe' -- if you want travel-to here later

local NPC_SHMENDRIK = 'Shmendrik Lavawalker'
local NPC_NATASHA   = 'Natasha Whitewater'
local MOB_SPIRIT    = 'a spirit of flame'

local ITEM_CROWN        = "Lord Bergurgle's Crown"
local ITEM_DAMAGED_CROWN = "Damaged Goblin Crown"

local NOTIFY_IDLE_MS        = 15000
local NAV_TIMEOUT_MS        = 60000
local KILL_TIMEOUT_MS       = 120000
local WAIT_NATASHA_MS       = 90000
local WAIT_ATTACK_START_MS  = 60000

local INTERACT_DIST = 20
local ATTACK_DIST   = 18

-- throttles
local last_idle_msg_ms = 0

local function now_ms() return mq.gettime() end

local function zone_name()
  local z = mq.TLO.Zone.Name()
  return (type(z) == 'function') and z() or z
end

local function in_zone()
  return zone_name() == ZONE_LONG
end

local function nav_active()
  local v = mq.TLO.Nav.Active()
  return (type(v) == 'function') and v() == true or v == true
end

local function me_in_combat()
  local c = mq.TLO.Me.Combat()
  return (type(c) == 'function') and c() == true or c == true
end

local function say_throttled(ctx, msg)
  local t = now_ms()
  if (t - last_idle_msg_ms) > NOTIFY_IDLE_MS then
    last_idle_msg_ms = t
    ctx.say(msg)
  end
end

local function wait_until_target_in_range(maxDist, timeoutMs)
  local start = now_ms()
  while now_ms() - start < timeoutMs do
    if not mq.TLO.Target() then return false end
    local d = mq.TLO.Target.Distance() or 9999
    if d <= maxDist then return true end
    mq.delay(100)
  end
  return false
end

local function spawn_by_exact_name(name)
  local s = mq.TLO.Spawn(name)
  if s and s() then return s end
  return nil
end

local function wait_for_spawn(name, timeoutMs)
  local start = now_ms()
  while now_ms() - start < timeoutMs do
    local s = spawn_by_exact_name(name)
    if s then return s end
    mq.delay(250)
  end
  return nil
end

local function wait_for_npc_attack(shmID, natID, timeoutMs)
  local start = now_ms()
  while now_ms() - start < timeoutMs do
    local shm = mq.TLO.Spawn(('id %d'):format(shmID))
    local nat = mq.TLO.Spawn(('id %d'):format(natID))
    if shm and shm() and nat and nat() then
      -- Heuristic: either is in combat AND their targets point at each other.
      local shmCombat = (shm.Combat and shm.Combat() == true) or false
      local natCombat = (nat.Combat and nat.Combat() == true) or false

      local shmTarID = (shm.Target and shm.Target.ID and shm.Target.ID()) or 0
      local natTarID = (nat.Target and nat.Target.ID and nat.Target.ID()) or 0

      if (shmCombat or natCombat) and ((shmTarID == natID) or (natTarID == shmID)) then
        return true
      end
    end
    mq.delay(250)
  end
  return false
end

function Step.on_enter(ctx, state)
  last_idle_msg_ms = 0
  ctx.say(('Step %s started: %s'):format(Step.id, Step.name))

  -- Make sure Lootly keeps what we need
  Items.set_lootly_keep(ITEM_DAMAGED_CROWN, 1)
end

-- tick() returns (done:boolean, nextStepId:string|nil)
function Step.tick(ctx, state)
  -- Require crown from step 1A
  if not Items.have_item(ITEM_CROWN) then
    ctx.say(('Missing required item "%s". Did step 1A complete properly? Pausing.'):format(ITEM_CROWN))
    ctx.hard_pause('missing required item for 1B')
    return false
  end

  -- (Optional) zone guard (you can add /travelto later, like step 1A)
  if not in_zone() then
    say_throttled(ctx, ('Need zone: %s to continue step 1B.'):format(ZONE_LONG))
    return false
  end

  -- Find Shmendrik
  local shm = spawn_by_exact_name(NPC_SHMENDRIK)
  if not shm then
    say_throttled(ctx, ('Waiting for %s to be available...'):format(NPC_SHMENDRIK))
    return false
  end
  local shmID = shm.ID()
  if not shmID or shmID <= 0 then return false end

  -- Nav to Shmendrik if not in range
  local shmDist = shm.Distance() or 9999
  if shmDist > INTERACT_DIST then
    if not nav_active() then
      ctx.say(('Navigating to %s (id=%d)...'):format(NPC_SHMENDRIK, shmID))
      mq.cmdf('/nav id %d', shmID)
    else
      say_throttled(ctx, ('Navigating to %s...'):format(NPC_SHMENDRIK))
    end
    return false
  end

  -- Turn in Bergurgle's Crown
  if Items.have_item(ITEM_CROWN) then
    ctx.say(('Turning in "%s" to %s...'):format(ITEM_CROWN, NPC_SHMENDRIK))

    Spawn.target_id(shmID)
    if not wait_until_target_in_range(INTERACT_DIST, 3000) then
      ctx.say('Target not in range for turn-in yet. Waiting...')
      return false
    end

    local ok, why = Trade.give_item_to_target(ITEM_CROWN)
    if not ok then
      ctx.say(('Turn-in failed: %s'):format(tostring(why)))
      return false
    end

    -- Whatever we get back: ensure it goes into bags
    mq.delay(300)
    mq.cmd('/autoinventory')
    mq.delay(300)
  end

  -- Wait for Natasha to spawn
  local nat = spawn_by_exact_name(NPC_NATASHA)
  if not nat then
    nat = wait_for_spawn(NPC_NATASHA, 500) -- quick recheck
  end
  if not nat then
    say_throttled(ctx, ('Waiting for %s to spawn...'):format(NPC_NATASHA))
    return false
  end
  local natID = nat.ID()
  if not natID or natID <= 0 then return false end

  -- Wait for Natasha to attack Shmendrik (critical mechanic)
  ctx.say('Natasha spawned. Waiting for Natasha to attack Shmendrik before killing him...')
  local attacked = wait_for_npc_attack(shmID, natID, WAIT_ATTACK_START_MS)
  if not attacked then
    ctx.say('Did not detect Natasha attacking Shmendrik yet. Continuing to wait...')
    return false
  end

  -- Kill Shmendrik
  ctx.say(('Detected attack. Killing %s (id=%d)...'):format(NPC_SHMENDRIK, shmID))
  local shmDied = Spawn.engage_and_kill_id(shmID, NPC_SHMENDRIK, KILL_TIMEOUT_MS, ATTACK_DIST)
  if not shmDied then
    ctx.say(('Timeout killing %s. Pausing.'):format(NPC_SHMENDRIK))
    ctx.hard_pause('kill timeout shmendrik')
    return false
  end

  -- Kill spirit of flame
  local spirit = wait_for_spawn(MOB_SPIRIT, 15000)
  if not spirit then
    ctx.say(('Expected spawn "%s" but did not see it. Waiting...'):format(MOB_SPIRIT))
    return false
  end
  local spiritID = spirit.ID()
  if not spiritID or spiritID <= 0 then return false end

  ctx.say(('Killing %s (id=%d)...'):format(MOB_SPIRIT, spiritID))
  local spiritDied = Spawn.engage_and_kill_id(spiritID, MOB_SPIRIT, KILL_TIMEOUT_MS, ATTACK_DIST)
  if not spiritDied then
    ctx.say(('Timeout killing %s. Pausing.'):format(MOB_SPIRIT))
    ctx.hard_pause('kill timeout spirit')
    return false
  end

  -- Wait for Lootly to deliver Damaged Goblin Crown
  ctx.say(('Waiting for Lootly to deliver "%s"...'):format(ITEM_DAMAGED_CROWN))
  local got = Items.wait_for_item(ITEM_DAMAGED_CROWN, 30000, 250)
  if not got then
    ctx.say(('Still do not have "%s". Check Lootly rules / assignment.'):format(ITEM_DAMAGED_CROWN))
    return false
  end

  -- Turn in Damaged Goblin Crown to Natasha
  ctx.say(('Turning in "%s" to %s...'):format(ITEM_DAMAGED_CROWN, NPC_NATASHA))
  Spawn.target_id(natID)

  if not wait_until_target_in_range(INTERACT_DIST, 3000) then
    ctx.say('Natasha not in range for turn-in yet. Waiting...')
    return false
  end

  local ok2, why2 = Trade.give_item_to_target(ITEM_DAMAGED_CROWN)
  if not ok2 then
    ctx.say(('Turn-in to Natasha failed: %s'):format(tostring(why2)))
    return false
  end

  mq.delay(300)
  mq.cmd('/autoinventory')
  mq.delay(300)

  -- Mark done
  state.done = state.done or {}
  state.done['1B'] = true
  ctx.save()
  ctx.say('Step 1B complete.')
  return true, Step.next
end

return Step