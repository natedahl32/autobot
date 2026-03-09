-- AutoBot/modules/mpg_ingenuity.lua
local mq = require('mq')
local Chat  = require('AutoBot.lib.chat')
local Items = require('AutoBot.lib.items')
local Spawn = require('AutoBot.lib.spawn')

local M = {}

M.id = 'mpg_ingenuity'
M.help = {
  'MPG: Mastery of Ingenuity',
  'Equips Suffusive bane weapons when available, clicks the weapon DD on boss when ready,',
  'attacks adds always, and attacks boss only while a bane weapon is equipped.',
  '',
  'Commands:',
  '  /autobot mpg_ingenuity start',
  '  /autobot mpg_ingenuity stop',
  '  /autobot mpg_ingenuity status',
}

-- =========================
-- CONFIG
-- =========================
local BOSS_NAME = 'Mater of Ingenuity'

local ADD_RADIUS = 120
local ADD_NAMES = {
  'a dragorn armskeeper',
  'a stoic dragorn armsman',
}

local BANE_SUBSTRING = 'Suffusive'

local LOOP_DELAY_MS = 150
local ATTEMPT_EQUIP_MS = 800
local CLICK_THROTTLE_MS = 500
local ATTACK_DISTANCE = 18

-- =========================
-- INTERNAL STATE
-- =========================
local running = false
local saved_weapons = nil

local last_click_ms = 0
local last_equip_try_ms = 0

-- bane helper announcements
local last_bane_seen_name = nil
local last_bane_seen_where = nil
local last_bane_equipped = false
local announced_need_bane = false

-- =========================
-- Helpers
-- =========================
local function tag()
  return Chat.tag('MPG_Ingenuity')
end

local function gsay(msg)
  Chat.dga_echo(msg)
end

local function boss_spawn()
  local s = mq.TLO.Spawn(BOSS_NAME)
  if s and s() then return s end
  return nil
end

local function boss_targeted()
  if not mq.TLO.Target() then return false end
  local n = mq.TLO.Target.Name()
  return n == BOSS_NAME
end

local function bane_equipped()
  local mh = Items.equipped_name('Mainhand')
  local oh = Items.equipped_name('Offhand')
  return Items.contains_ci(mh, BANE_SUBSTRING) or Items.contains_ci(oh, BANE_SUBSTRING)
end

local function equipped_bane_item()
  local mh = Items.inv_item('Mainhand')
  local oh = Items.inv_item('Offhand')

  if mh and mh() and Items.contains_ci(mh.Name(), BANE_SUBSTRING) then return mh end
  if oh and oh() and Items.contains_ci(oh.Name(), BANE_SUBSTRING) then return oh end

  return nil
end

local function find_best_add()
  local best = nil
  local bestDist = 999999

  for _, nm in ipairs(ADD_NAMES) do
    local s = mq.TLO.Spawn(string.format('%s radius %d', nm, ADD_RADIUS))
    if s and s() then
      local d = s.Distance() or 999999
      if d < bestDist then
        best = s
        bestDist = d
      end
    end
  end

  return best
end

local function announce_bane_seen(name, where)
  if name == last_bane_seen_name and where == last_bane_seen_where then return end
  last_bane_seen_name = name
  last_bane_seen_where = where
  gsay(string.format('%s GOT BANE: %s (%s)', tag(), name, where))
end

local function announce_bane_equipped(name)
  gsay(string.format('%s EQUIPPED BANE: %s', tag(), tostring(name)))
end

local function announce_need_bane()
  if announced_need_bane then return end
  announced_need_bane = true
  gsay(string.format('%s NEED BANE (no Suffusive equipped)', tag()))
end

local function clear_need_bane()
  announced_need_bane = false
end

local function try_use_bane_clicky_if_ready()
  if not bane_equipped() then return end
  if mq.TLO.Me.Casting() then return end
  if not boss_targeted() then return end

  local now = mq.gettime()
  if now - last_click_ms < CLICK_THROTTLE_MS then return end

  local baneItem = equipped_bane_item()
  if not baneItem then return end
  if not Items.item_has_clicky(baneItem) then return end
  if not Items.item_clicky_ready(baneItem) then return end

  local n = baneItem.Name()
  if not n or n == '' then return end

  Items.use_item_by_name(n)
  last_click_ms = now
end

-- =========================
-- Module lifecycle
-- =========================
function M.can_start(ctx)
  -- This module is safe for everyone to run; even if no bane can be used,
  -- it still assists adds/pets and will equip bane when it appears.
  return true
end

function M.start(ctx, reason)
  running = true

  last_click_ms = 0
  last_equip_try_ms = 0

  last_bane_seen_name = nil
  last_bane_seen_where = nil
  announced_need_bane = false

  saved_weapons = Items.save_weapons()
  last_bane_equipped = bane_equipped()

  ctx.log(string.format('[mpg_ingenuity] Started (%s).', tostring(reason or 'start')))
  gsay(string.format('%s Started. Saved weapons: MH=%s OH=%s',
    tag(), tostring(saved_weapons.main), tostring(saved_weapons.off)))
end

function M.stop(ctx, reason)
  running = false
  mq.cmd('/attack off')
  Items.restore_weapons(saved_weapons)
  ctx.log(string.format('[mpg_ingenuity] Stopped (%s). Restored weapons.', tostring(reason or 'stop')))
  gsay(string.format('%s Stopped. Restored weapons.', tag()))
end

function M.tick(ctx)
  mq.delay(LOOP_DELAY_MS)
  if not running then return end

  if mq.TLO.Me.Dead() then
    mq.cmd('/attack off')
    mq.delay(1000)
    return
  end

  local boss = boss_spawn()
  if not boss then
    mq.cmd('/attack off')
    mq.delay(250)
    return
  end

  -- Track bane availability for announcements
  local baneName, where = Items.find_item_name_by_substring(BANE_SUBSTRING)
  if baneName then
    announce_bane_seen(baneName, where)
  end

  -- If bane expired and left us empty-handed, re-equip saved weapons for add DPS
  local has_bane_now = bane_equipped()
  if last_bane_equipped and not has_bane_now then
    local did = Items.equip_saved_weapons_if_empty(saved_weapons)
    if did then
      gsay(string.format('%s Bane expired -> re-equipped saved weapons for adds.', tag()))
    end
    clear_need_bane()
  end

  -- Equip bane if we don't have it (throttled)
  local now = mq.gettime()
  if not has_bane_now and (now - last_equip_try_ms) > ATTEMPT_EQUIP_MS then
    last_equip_try_ms = now
    if baneName then
      local ok = Items.equip_item_by_name(baneName, bane_equipped)
      if ok then
        announce_bane_equipped(baneName)
        clear_need_bane()
        has_bane_now = true
      end
    end
  end

  -- Need-bane reminder if we don't have one
  if not has_bane_now then
    announce_need_bane()
  end
  last_bane_equipped = has_bane_now

  -- Priority:
  -- 1) Adds: always attack
  -- 2) Otherwise: attack boss only if bane equipped
  local add = find_best_add()
  if add then
    local addId = add.ID()
    if addId then
      Spawn.target_id(addId)
      mq.cmd('/pet attack')
      mq.cmd('/attack on')
    end
    return
  end

  -- No adds
  local bossId = boss.ID()
  if not bossId then return end

  Spawn.target_id(bossId)
  mq.cmd('/pet attack')

  if has_bane_now then
    local dist = mq.TLO.Target.Distance() or 9999
    if dist <= ATTACK_DISTANCE then
      mq.cmd('/attack on')
    else
      mq.cmd('/attack off')
    end

    -- Clicky: requires boss targeted + ready (adds do not matter)
    try_use_bane_clicky_if_ready()
  else
    -- No bane: don't melee boss, but keep pet on boss
    mq.cmd('/attack off')
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
  ctx.log(string.format(
    '[mpg_ingenuity] running=%s baneEquipped=%s savedMH=%s savedOH=%s',
    tostring(running),
    tostring(bane_equipped()),
    tostring(saved_weapons and saved_weapons.main or 'nil'),
    tostring(saved_weapons and saved_weapons.off or 'nil')
  ))
end

return M