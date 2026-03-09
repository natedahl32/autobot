-- AutoBot/modules/EpicSteps/CLR1_1A.lua
local mq = require('mq')

local Items = require('AutoBot.lib.items')
local Nav = require('AutoBot.lib.nav')
local Spawn = require('AutoBot.lib.spawn')

local Step = {}

Step.id = '1A'
Step.name = "Kill Lord Bergurgle for Lord Bergurgle's Crown"
Step.next = '1B' -- placeholder

-- =========================
-- CONSTANTS
-- =========================
local ZONE_LONG  = 'Lake Rathetear'
local ZONE_SHORT = 'lakerathe' -- for /travelto
local MOB_NAME   = 'Lord Bergurgle'
local ITEM_CROWN = "Lord Bergurgle's Crown"

-- Bergurgle camp location (his spawn)
-- NOTE: EQ /loc and /nav loc are typically Y X Z
local CAMP_Y, CAMP_X, CAMP_Z = 2783, 144, -367

-- Placeholder logic
local PH_RADIUS          = 80      -- "small radius" around camp
local PH_ENGAGE_TIMEOUT  = 60000   -- 60s per placeholder fight
local CAMP_ARRIVE_DIST   = 20      -- how close is "at camp"

local NOTIFY_IDLE_MS     = 15000
local COMBAT_TIMEOUT_MS  = 120000

-- step-local throttles
local last_idle_msg_ms = 0
local last_travel_msg_ms = 0
local last_camp_msg_ms = 0

local function now_ms()
  return mq.gettime()
end

local function nav_active()
  local v = mq.TLO.Nav.Active()
  return (type(v) == 'function') and v() == true or v == true
end

local function zone_name()
  local z = mq.TLO.Zone.Name()
  return (type(z) == 'function') and z() or z
end

local function in_zone()
  return zone_name() == ZONE_LONG
end

local function me_xyz()
  local x = mq.TLO.Me.X(); x = (type(x) == 'function') and x() or x or 0
  local y = mq.TLO.Me.Y(); y = (type(y) == 'function') and y() or y or 0
  local z = mq.TLO.Me.Z(); z = (type(z) == 'function') and z() or z or 0
  return x, y, z
end

local function dist_to_camp()
  local x, y, z = me_xyz()
  local dx = x - CAMP_X
  local dy = y - CAMP_Y
  local dz = z - CAMP_Z
  return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function maybe_travel(ctx)
  if in_zone() then return true end

  if nav_active() then
    local t = now_ms()
    if (t - last_travel_msg_ms) > NOTIFY_IDLE_MS then
      last_travel_msg_ms = t
      ctx.say(('Travel in progress... waiting to arrive in %s.'):format(ZONE_LONG))
    end
    return false
  end

  mq.cmdf('/travelto %s', ZONE_SHORT)
  last_travel_msg_ms = now_ms()
  ctx.say(('Not in %s. Starting travel: /travelto %s'):format(ZONE_LONG, ZONE_SHORT))
  return false
end

local function dist2d_to_camp()
  local x, y, z = me_xyz()
  local dx = x - CAMP_X
  local dy = y - CAMP_Y
  return math.sqrt(dx*dx + dy*dy)
end

local function ensure_at_camp(ctx)
  local d = dist2d_to_camp()

  local arrived, status = Nav.ensure_loc(CAMP_Y, CAMP_X, CAMP_Z, function()
    return dist2d_to_camp() <= CAMP_ARRIVE_DIST
  end, 1500)

  if arrived then
    return true
  end

  if status == 'started' then
    ctx.say(('Bergurgle not up. Moving to camp loc: %d, %d, %d'):format(CAMP_Y, CAMP_X, CAMP_Z))
    return false
  end

  if status == 'failed' then
    ctx.say(('Could not find path to Bergurgle camp. Please navigate there manually, then /autobot epic_cleric_1 resume'))
    ctx.hard_pause('nav failed to Bergurgle camp')
    return false
  end

  -- status == 'navigating'
  return false
end

local function me_in_combat()
  local c = mq.TLO.Me.Combat()
  return (type(c) == 'function') and c() == true or c == true
end

local function find_placeholder()
  -- Exact placeholder name, NPC-only, no corpses
  local s = mq.TLO.Spawn(('npc "%s" radius %d nocorpse'):format('a deepwater goblin', PH_RADIUS))
  if Spawn.is_alive_npc(s) then return s end

  -- Anything with "Deep" in name, NPC-only, no corpses
  s = mq.TLO.Spawn(('npc Deep radius %d nocorpse'):format(PH_RADIUS))
  if Spawn.is_alive_npc(s) then return s end

  return nil
end

function Step.on_enter(ctx, state)
  last_idle_msg_ms = 0
  last_travel_msg_ms = 0
  last_camp_msg_ms = 0
  ctx.say(('Step %s started: %s'):format(Step.id, Step.name))
  Items.set_lootly_keep(ITEM_CROWN, 1)
end

-- tick() returns (done:boolean, nextStepId:string|nil)
function Step.tick(ctx, state)
  -- If crown already in inventory, complete immediately.
  if Items.have_item(ITEM_CROWN) then
    state.done = state.done or {}
    if not state.done['1A'] then
      state.done['1A'] = true
      ctx.save()
      ctx.say(('Step 1A complete: found "%s" in inventory.'):format(ITEM_CROWN))
    end
    return true, Step.next
  end

  -- Auto travel to Lake Rathetear
  if not maybe_travel(ctx) then
    return false
  end

  -- If Bergurgle is up, go to him and kill him
  local boss = Spawn.spawn_by_name(MOB_NAME)
  if boss then
    local id = boss.ID()
    if id and id > 0 then
      ctx.say(('Found %s (id=%d). Navigating + engaging...'):format(MOB_NAME, id))

      local cur = mq.TLO.Spawn(('id %d'):format(phID))
      if not Spawn.is_alive_npc(cur) then
        return false
      end

      local died = Spawn.engage_and_kill_id(id, MOB_NAME, COMBAT_TIMEOUT_MS, 18)
      if not died then
        ctx.say(('Combat/nav timeout waiting for %s. Pausing for safety.'):format(MOB_NAME))
        ctx.hard_pause('combat/nav timeout')
        return false
      end

      ctx.say(('%s dead. Waiting for Lootly to deliver "%s"...'):format(MOB_NAME, ITEM_CROWN))

      local got = Items.wait_for_item(ITEM_CROWN, 20000, 250) -- 20s max; tweak if you want
      if got then
        state.done = state.done or {}
        state.done['1A'] = true
        ctx.save()
        ctx.say(('Received "%s". Step 1A complete.'):format(ITEM_CROWN))
        return true, Step.next
      end

      ctx.say(('Still do not have "%s" yet. (Loot delay / settings?) Will keep camping.'):format(ITEM_CROWN))
      return false
    end
  end

  -- Bergurgle not up: go to camp loc and kill placeholders
  if not ensure_at_camp(ctx) then
    return false
  end

  -- If we're already fighting something, let it resolve naturally
  if me_in_combat() then
    return false
  end

  local ph = find_placeholder()
  if not ph then
    local t = now_ms()
    if (t - last_idle_msg_ms) > NOTIFY_IDLE_MS then
      last_idle_msg_ms = t
      ctx.say(('At camp. No placeholders found in radius %d. Waiting...'):format(PH_RADIUS))
    end
    return false
  end

  local phID = ph.ID()
  local phName = ph.Name() or 'placeholder'
  local cur = mq.TLO.Spawn(('id %d'):format(phID))
  if not Spawn.is_alive_npc(cur) then
    return false
  end

  ctx.say(('Placeholder found: %s (id=%s). Navigating + killing...'):format(phName, tostring(phID)))
  Spawn.engage_and_kill_id(phID, phName, PH_ENGAGE_TIMEOUT, 18)
  return false
end

return Step