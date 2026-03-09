-- AutoBot/modules/mpg_subversion.lua
local DanNet = require('AutoBot.lib.dannet')
local CWTN   = require('AutoBot.lib.cwtn')
local Spells = require('AutoBot.lib.spells')
local Spawn  = require('AutoBot.lib.spawn')
local State  = require('AutoBot.lib.state')
local Config = require('AutoBot.lib.config')

local M = {
  id = 'mpg_subversion',
  version = '1.0.0',

  help = {
    'Subversion chest helper.',
    'Usage:',
    '  /autobot start mpg_subversion',
    '  /autobot mpg_subversion status',
    '  /autobot mpg_subversion debug on|off',
    '  /autobot mpg_subversion group <name>   (set + save DanNet group)',
    '  /autobot mpg_subversion group          (show current)',
  },

  triggers = {
    { type='zone', name='Proving Grounds: The Mastery of Subversion', reason='Entered Subversion' },
    { type='chat', pattern='You have entered Proving Grounds: The Mastery of Subversion', reason='Entered Subversion (chat)' },
  },
}

-- =========================
-- CONFIG (module-local)
-- =========================
local DEFAULTS = {
  dannet_group = 'subversionchest',
}

local cfg = nil -- loaded on start

local CHESTS = {
  hexed      = 'hexed',
  spellbound = 'spellbound',
  ironbound  = 'ironbound',
}

local USE_DISTANCE = 12
local NAV_TIMEOUT_MS = 8000

local ATTEMPT_COOLDOWN_MS = 1500
local CHEST_LOCK_MS = 20000

local CHEST_STATE_TTL_MS = 600000 -- 10 minutes

local CHEST_GEM_DISARM = 9
local CHEST_GEM_UNLOCK = 10

local CHEST_SPELLS = {
  ENC = { disarm = "Wuggan's Greater Discombobulation", unlock = "Wuggan's Greater Extrication" },
  MAG = { disarm = "Wuggan's Greater Discombobulation", unlock = "Wuggan's Greater Extrication" },
  NEC = { disarm = "Wuggan's Greater Discombobulation", unlock = "Wuggan's Greater Extrication" },
  WIZ = { disarm = "Xalirilan's Greater Discombobulation", unlock = "Xalirilan's Greater Extrication" },
  CLR = { disarm = "Iony's Greater Exorcism", unlock = "Iony's Greater Cleansing" },
  DRU = { disarm = "Reebo's Greater Exorcism", unlock = "Reebo's Greater Cleansing" },
  SHM = { disarm = "Reebo's Greater Exorcism", unlock = "Reebo's Greater Cleansing" },
}

local CLASS_TO_TYPES = {
  CLR = { hexed = true }, DRU = { hexed = true }, SHM = { hexed = true },
  ENC = { spellbound = true }, MAG = { spellbound = true }, NEC = { spellbound = true }, WIZ = { spellbound = true },
  ROG = { ironbound = true }, BRD = { ironbound = true },
}

-- =========================
-- RUNTIME STATE (reset per start)
-- =========================
local running = false
local debug = false
local validated_once = false
local last_attempt_ms = 0
local last_heartbeat_ms = 0

local chest_state_map = nil -- ttl map
local chest_locks_map = nil -- lock map

local missing_book_reported = {}
local missing_mem_reported  = {}

local function tag(ctx)
  return string.format("[MPG_Subversion:%s]", ctx.mq.TLO.Me.Name() or "Me")
end

local function gsay(msg)
  DanNet.dga_echo(msg)
end

local function class_can_handle(ctx, chestType)
  local short = ctx.mq.TLO.Me.Class.ShortName()
  local allowed = CLASS_TO_TYPES[short]
  return allowed and allowed[chestType] == true
end

local function spawn_for_type(ctx, chestType)
  local name = CHESTS[chestType]
  if not name then return nil end
  return Spawn.spawn_by_name(name)
end

local function report_once(ctx, tbl, key, msg)
  if tbl[key] then return end
  tbl[key] = true
  gsay(msg)
end

local function validate_required_spells_and_announce(ctx)
  local mq = ctx.mq
  local short = mq.TLO.Me.Class.ShortName()
  local req = CHEST_SPELLS[short]
  if not req then return true end

  local ok = true

  if not Spells.has_spell_in_book(req.disarm) then
    report_once(ctx, missing_book_reported, req.disarm,
      string.format("%s %s Missing spell in book: %s", tag(ctx), short, req.disarm))
    ok = false
  end
  if not Spells.has_spell_in_book(req.unlock) then
    report_once(ctx, missing_book_reported, req.unlock,
      string.format("%s %s Missing spell in book: %s", tag(ctx), short, req.unlock))
    ok = false
  end

  if not Spells.is_memmed_in_slot(req.disarm, CHEST_GEM_DISARM) then
    report_once(ctx, missing_mem_reported, req.disarm,
      string.format("%s %s Spell NOT memorized in gem %d: %s", tag(ctx), short, CHEST_GEM_DISARM, req.disarm))
    ok = false
  end
  if not Spells.is_memmed_in_slot(req.unlock, CHEST_GEM_UNLOCK) then
    report_once(ctx, missing_mem_reported, req.unlock,
      string.format("%s %s Spell NOT memorized in gem %d: %s", tag(ctx), short, CHEST_GEM_UNLOCK, req.unlock))
    ok = false
  end

  return ok
end

local function ensure_chest_spells_memmed_in_last_gems(ctx)
  local mq = ctx.mq
  local short = mq.TLO.Me.Class.ShortName()
  local req = CHEST_SPELLS[short]
  if not req then return true end

  if not Spells.has_spell_in_book(req.disarm) or not Spells.has_spell_in_book(req.unlock) then
    validate_required_spells_and_announce(ctx)
    return false
  end

  if Spells.is_memmed_in_slot(req.disarm, CHEST_GEM_DISARM) and Spells.is_memmed_in_slot(req.unlock, CHEST_GEM_UNLOCK) then
    return true
  end

  local ok, err = pcall(function()
    CWTN.byos_on(); mq.delay(300)
    CWTN.byos_on(); mq.delay(300)

    gsay(string.format("%s BYOS on + mem chest spells: Gem%d=%s, Gem%d=%s",
      tag(ctx), CHEST_GEM_DISARM, req.disarm, CHEST_GEM_UNLOCK, req.unlock))

    local function on_timeout(spellName, gem, cur)
      gsay(string.format("%s Timeout memming %s into gem %d (current=%s)",
        tag(ctx), spellName, gem, tostring(cur)))
    end

    if not Spells.memorize_spell_to_gem(req.disarm, CHEST_GEM_DISARM, on_timeout) then return end
    if not Spells.memorize_spell_to_gem(req.unlock, CHEST_GEM_UNLOCK, on_timeout) then return end
  end)

  if not ok then
    gsay(string.format("%s ERROR while memming chest spells: %s", tag(ctx), tostring(err)))
    return false
  end

  return validate_required_spells_and_announce(ctx)
end

local function should_attempt_chest_now(ctx, chestType, st)
  local mq = ctx.mq
  local short = mq.TLO.Me.Class.ShortName()

  if chestType == 'ironbound' and (short == 'ROG' or short == 'BRD') then
    if not st.disarmed and not Spells.ability_ready("Disarm Traps") then
      return false, "Disarm Traps not ready"
    end
    if st.disarmed and not st.unlocked and not Spells.ability_ready("Pick Lock") then
      return false, "Pick Lock not ready"
    end
    return true
  end

  if chestType == 'spellbound' or chestType == 'hexed' then
    local req = CHEST_SPELLS[short]
    if not req then return false, "no mapping" end

    if not st.disarmed and not Spells.spell_ready(req.disarm) then
      return false, "disarm spell not ready"
    end
    if st.disarmed and not st.unlocked and not Spells.spell_ready(req.unlock) then
      return false, "unlock spell not ready"
    end
    return true
  end

  return true
end

local function handle_chest(ctx, spawnObj, chestType)
  local mq = ctx.mq
  if mq.TLO.Me.Dead() then return end

  local id = spawnObj.ID()
  if not id then return end

  local now = mq.gettime()
  if State.locked(chest_locks_map, id, now) then return end
  State.lock(chest_locks_map, id, now)

  local st = State.ttl_get(chest_state_map, id, function()
    return { disarmed=false, unlocked=false, opened=false, last=now }
  end, now)

  if debug then
    ctx.dbg(string.format("[mpg_subversion] chest id=%d type=%s D=%s U=%s O=%s",
      id, chestType, tostring(st.disarmed), tostring(st.unlocked), tostring(st.opened)))
  end

  local okGo, whyGo = should_attempt_chest_now(ctx, chestType, st)
  if not okGo then
    if debug then ctx.dbg(string.format("[mpg_subversion] skip chest id=%d (%s): %s", id, chestType, tostring(whyGo))) end
    return
  end

  local ok, err = CWTN.with_manual_mode(function()
    -- move in
    Spawn.target_id(id)

    local dist = spawnObj.Distance() or 9999
    local reached = true
    if dist > USE_DISTANCE then
      Spawn.nav_to_id(id)
      reached = Spawn.wait_until_close(id, USE_DISTANCE, NAV_TIMEOUT_MS)
      mq.delay(250)
    end
    if not reached then
      gsay(string.format("%s Could not reach chest (nav timeout).", tag(ctx)))
      return
    end

    Spawn.target_id(id)
    Spawn.face_target()

    local short = mq.TLO.Me.Class.ShortName()

    -- ===== IRONBOUND: ROG/BRD =====
    if chestType == 'ironbound' and (short == 'ROG' or short == 'BRD') then
      if not st.disarmed then
        gsay(string.format("%s IRONBOUND: Disarm Traps", tag(ctx)))
        mq.cmd('/doability "Disarm Traps"')
        mq.delay(500)
        st.disarmed = true
      end

      if not st.unlocked then
        gsay(string.format("%s IRONBOUND: Pick Lock", tag(ctx)))
        mq.cmd('/doability "Pick Lock"')
        mq.delay(500)
        st.unlocked = true
      end

      if not st.opened then
        gsay(string.format("%s IRONBOUND: /open", tag(ctx)))
        local opened = Spawn.open_and_verify_despawn(id, 2500)
        if opened then
          st.opened = true
        else
          -- rollback so we re-pick next time
          st.opened = false
          st.unlocked = false
          if debug then ctx.dbg("[mpg_subversion] IRONBOUND open failed -> rollback unlocked=false") end
          return
        end
      end

      mq.cmd('/target clear')
      return
    end

    -- ===== SPELLBOUND/HEXED: CASTERS =====
    if chestType == 'spellbound' or chestType == 'hexed' then
      local req = CHEST_SPELLS[short]
      if not req then
        gsay(string.format("%s No spell mapping for %s; cannot handle %s chest.", tag(ctx), short, chestType))
        return
      end

      if not ensure_chest_spells_memmed_in_last_gems(ctx) then
        return
      end

      local label = (chestType == 'spellbound') and "SPELLBOUND" or "HEXED"

      if not st.disarmed then
        gsay(string.format("%s %s: Disarm (%s)", tag(ctx), label, req.disarm))
        local okCast, why = Spells.cast_spell(req.disarm, 9000)
        if not okCast then
          if debug then ctx.dbg("[mpg_subversion] Disarm blocked: " .. tostring(why)) end
          return
        end
        st.disarmed = true
        mq.delay(300)
      end

      if not st.unlocked then
        gsay(string.format("%s %s: Unlock (%s)", tag(ctx), label, req.unlock))
        local okCast, why = Spells.cast_spell(req.unlock, 9000)
        if not okCast then
          if debug then ctx.dbg("[mpg_subversion] Unlock blocked: " .. tostring(why)) end
          return
        end
        st.unlocked = true
        mq.delay(300)
      end

      if not st.opened then
        gsay(string.format("%s %s: /open", tag(ctx), label))
        local opened = Spawn.open_and_verify_despawn(id, 2500)
        if opened then
          st.opened = true
          mq.delay(300)
        else
          -- rollback so we retry unlock next time
          st.opened = false
          st.unlocked = false
          if debug then ctx.dbg("[mpg_subversion] " .. label .. " open failed -> rollback unlocked=false") end
          return
        end
      end

      mq.cmd('/target clear')
      return
    end
  end)

  if not ok then
    gsay(string.format("%s ERROR while handling chest: %s", tag(ctx), tostring(err)))
  end
end

-- =========================
-- Module lifecycle
-- =========================
function M.can_start(ctx)
  -- Only meaningful if you want to *prevent* starting when not in the trial.
  return true
end

function M.start(ctx, reason)
  cfg = select(1, Config.load(M.id, DEFAULTS))

  running = true
  validated_once = false
  last_attempt_ms = 0
  last_heartbeat_ms = 0

  chest_state_map = State.make_ttl_map(CHEST_STATE_TTL_MS)
  chest_locks_map = State.make_lock_map(CHEST_LOCK_MS)

  missing_book_reported = {}
  missing_mem_reported = {}

  gsay(string.format("%s Subversion module started (%s).", tag(ctx), tostring(reason or '')))
  gsay(string.format("%s Using DanNet group: %s", tag(ctx), tostring(cfg.dannet_group)))
end

function M.tick(ctx)
  local mq = ctx.mq
  local now = mq.gettime()
  
  if not running then return end
  if mq.TLO.Me.Dead() then return end

  -- periodic cleanup
  if (now - last_heartbeat_ms) > 5000 then
    last_heartbeat_ms = now
    State.ttl_cleanup(chest_state_map, now)
  end

  -- DanNet group gate (same behavior as your standalone script)
  if not cfg or not DanNet.joined_group(cfg.dannet_group) then
    validated_once = false    
    return
  end

  if not validated_once then
    validated_once = true
    validate_required_spells_and_announce(ctx)
    ensure_chest_spells_memmed_in_last_gems(ctx)
  end

  if now - last_attempt_ms < ATTEMPT_COOLDOWN_MS then
    return
  end
  last_attempt_ms = now

  -- Priority
  local order = { 'ironbound', 'spellbound', 'hexed' }
  for _, chestType in ipairs(order) do
    if class_can_handle(ctx, chestType) then
      local s = spawn_for_type(ctx, chestType)
      if s and s() then
        handle_chest(ctx, s, chestType)
        mq.delay(600)
        break
      end
    end
  end
end

function M.stop(ctx, reason)
  running = false

  CWTN.byos_off()
  CWTN.manual_off()

  gsay(string.format("%s Subversion module stopped (%s).", tag(ctx), tostring(reason or '')))
end

-- =========================
-- Module commands
-- /autobot mpg_subversion <command>
-- =========================
M.commands = {}

function M.commands.status(ctx, args)
  ctx.log(string.format('[mpg_subversion] running=%s validated=%s debug=%s',
    tostring(running), tostring(validated_once), tostring(debug)))
end

function M.commands.debug(ctx, args)
  local v = (args[1] or ''):lower()
  if v == 'on' then debug = true end
  if v == 'off' then debug = false end
  ctx.log('[mpg_subversion] debug=' .. tostring(debug))
end

function M.commands.stop(ctx, args)
  -- stop the module, but let AutoBot keep running
  M.stop(ctx, 'module command stop')
end

function M.commands.start(ctx, args)
  M.start(ctx, 'module command start')
end

function M.commands.group(ctx, args)
  cfg = cfg or select(1, Config.load(M.id, DEFAULTS))

  local newName = args[1] -- params-only after init.lua fix

  if not newName or newName == '' then
    ctx.log(('[mpg_subversion] dannet_group=%s'):format(tostring(cfg.dannet_group)))
    return
  end

  cfg.dannet_group = newName
  local ok, err = Config.save(M.id, cfg)
  if not ok then
    ctx.log('[mpg_subversion] ERROR saving config: ' .. tostring(err))
    return
  end

  ctx.log('[mpg_subversion] Saved dannet_group=' .. tostring(cfg.dannet_group))
end

return M