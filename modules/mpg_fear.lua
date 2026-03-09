-- AutoBot/modules/mpg_fear.lua
local mq = require('mq')
local CWTN = require('AutoBot.lib.cwtn')
local Spawn = require('AutoBot.lib.spawn')
local Spells = require('AutoBot.lib.spells')
local XTarget = require('AutoBot.lib.xtarget')

local M = {}

M.id = 'mpg_fear'
M.help = {
  'MPG: Mastery of Fear',
  'Keeps non-"fearless" versions of: a cackling skeleton, a dire wolf, a dragorn, an elemental feared.',
  '',
  'Commands:',
  '  /autobot mpg_fear start',
  '  /autobot mpg_fear stop',
  '  /autobot mpg_fear status',
}

-- =========================
-- CONFIG
-- =========================

local DEBUG = false
local HEARTBEAT_MS = 3000
local FEAR_RANGE = 120
local USE_LOS = true
local LOOP_DELAY_MS = 50

local FEAR_GEM = 9
local ATTEMPT_COOLDOWN_MS = 800

local FEAR_MOBS = {
  ["a cackling skeleton"] = true,
  ["a dire wolf"] = true,
  ["a dragorn"] = true,
  ["an elemental"] = true,
}

local FEAR_BY_CLASS = {
  SHD = { type="spell", name="Shadow Howl" },
  ENC = { type="spell", name="Anxiety Attack" },
}

local FEAR_BUFF_NAMES = {
  ["Shadow Howl"] = true,
  ["Anxiety Attack"] = true,
}

-- =========================
-- INTERNAL STATE
-- =========================

local running = false
local fearCfg = nil
local lastBeat = 0
local lastAttempt = 0

-- =========================
-- Helpers
-- =========================

local function norm_name(name)
  name = (name or ""):lower()
  name = name:gsub("_", " ")
  name = name:gsub("%d+$", "")
  name = name:gsub("%s+", " ")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  return name
end

local function is_fearless(name)
  name = (name or ""):lower()
  return name:find("fearless", 1, true) ~= nil
end

-- =========================
-- Target selection
-- =========================

local function find_fear_target()

  local best = nil
  local bestDist = 999999

  for s in XTarget.iter_spawns() do

    local raw = s.Name() or ""
    local name = norm_name(raw)

    if FEAR_MOBS[name] and not is_fearless(name) then

      local dist = s.Distance() or 999999

      if dist <= FEAR_RANGE then

        if (not USE_LOS) or s.LineOfSight() then

          if not Spawn.spawn_has_any_buff(s, FEAR_BUFF_NAMES) then

            if dist < bestDist then
              best = s
              bestDist = dist
            end

          end
        end
      end
    end
  end

  return best
end

local function heartbeat(ctx)

  if not DEBUG then return end

  local t = find_fear_target()

  ctx.dbg(
    ("[MPG_Fear:%s] casting=%s target=%s nextFearTarget=%s")
    :format(
      mq.TLO.Me.Name() or "Me",
      tostring(mq.TLO.Me.Casting()),
      tostring(mq.TLO.Target.Name() or "nil"),
      tostring(t and (t.Name() or "nil") or "nil")
    )
  )

end

-- =========================
-- Module lifecycle
-- =========================

function M.can_start(ctx)

  local short = CWTN.class_short()
  local cfg = FEAR_BY_CLASS[short]

  if not cfg then
    ctx.log(("[mpg_fear] No fear configured for %s. Not starting."):format(tostring(short)))
    return false
  end

  if cfg.type ~= "spell" then
    ctx.log(("[mpg_fear] %s fear type '%s' not implemented."):format(short, cfg.type))
    return false
  end

  return true
end

function M.start(ctx, reason)

  local short = CWTN.class_short()
  fearCfg = FEAR_BY_CLASS[short]

  running = true
  lastBeat = 0
  lastAttempt = 0

  CWTN.byos_on()

  if not Spells.memorize_spell_to_gem(fearCfg.name, FEAR_GEM) then
    ctx.log(("[mpg_fear] FAILED to mem '%s' in gem %d"):format(fearCfg.name, FEAR_GEM))
    running = false
    return
  end

  ctx.log(
    ("[mpg_fear] Started (%s). Using '%s' (gem %d)")
    :format(reason or "start", fearCfg.name, FEAR_GEM)
  )

end

function M.stop(ctx, reason)

  running = false
  CWTN.manual_off()
  CWTN.byos_off()

  ctx.log(("[mpg_fear] Stopped (%s)"):format(reason or "stop"))

end

-- =========================
-- Main tick loop
-- =========================

function M.tick(ctx)

  if not running then return end
  if mq.TLO.Me.Dead() then return end

  local now = mq.gettime()

  if (now - lastBeat) > HEARTBEAT_MS then
    lastBeat = now
    heartbeat(ctx)
  end

  if (now - lastAttempt) < ATTEMPT_COOLDOWN_MS then
    return
  end

  local s = find_fear_target()
  if not s then return end

  lastAttempt = now

  CWTN.manual_on()

  local sid = s.ID()

  if sid then

    Spawn.target_id(sid)

    local cur = mq.TLO.Spawn(("id %d"):format(sid))

    if cur and cur() and Spawn.spawn_has_any_buff(cur, FEAR_BUFF_NAMES) then
      CWTN.manual_off()
      return
    end

    local ok, why = Spells.cast_spell(fearCfg.name)

    CWTN.manual_off()

    if DEBUG then
      if not ok then
        ctx.dbg("[mpg_fear] fear attempt failed: " .. tostring(why))
      else
        ctx.dbg("[mpg_fear] fear cast succeeded on " .. tostring(s.Name()))
      end
    end

  else
    CWTN.manual_off()
  end

end

-- =========================
-- Commands
-- =========================

M.commands = {}

M.commands.start = function(ctx)
  if M.can_start(ctx) then
    M.start(ctx, 'manual start')
  end
end

M.commands.stop = function(ctx)
  M.stop(ctx, 'manual stop')
end

M.commands.status = function(ctx)

  ctx.log(
    ("[mpg_fear] running=%s spell=%s gem=%d")
    :format(
      tostring(running),
      tostring(fearCfg and fearCfg.name or "nil"),
      FEAR_GEM
    )
  )

end

return M