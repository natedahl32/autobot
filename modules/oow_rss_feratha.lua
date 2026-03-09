local mq = require('mq')

local RaidBoss = require('AutoBot.lib.raidboss')
local BossRoles = require('AutoBot.lib.bossroles')

local M = {}

M.id = "oow_rss_feratha"

M.help = {
  'Omens of War - Riftseekers Sanctum - Feratha',
  '',
  'Commands:',
  '  /autobot oow_rss_feratha start',
  '  /autobot oow_rss_feratha stop',
  '  /autobot oow_rss_feratha startfight',
  '  /autobot oow_rss_feratha stopfight',
  '  /autobot oow_rss_feratha mtset',
  '  /autobot oow_rss_feratha bmtset',
  '  /autobot oow_rss_feratha maset',
  '  /autobot oow_rss_feratha mtclear',
  '  /autobot oow_rss_feratha bmtclear',
  '  /autobot oow_rss_feratha maclear',
  '  /autobot oow_rss_feratha rtadd',
  '  /autobot oow_rss_feratha rtdel',
  '  /autobot oow_rss_feratha rtclear',
  '  /autobot oow_rss_feratha otadd',
  '  /autobot oow_rss_feratha otdel',
  '  /autobot oow_rss_feratha otclear',
  '  /autobot oow_rss_feratha otstatus',
  '  /autobot oow_rss_feratha otsetmobs <mob1|mob2|...>',
  '  /autobot oow_rss_feratha otclearmobs',
  '  /autobot oow_rss_feratha tankstatus',
  '  /autobot oow_rss_feratha rtstatus',
  '  /autobot oow_rss_feratha mastatus',
}

-- Add CC buff names you actually see on your server/raid here.
local MEZ_BUFF_NAMES = {
  ["Anxiety Attack"] = true, -- example placeholder if used as mez elsewhere; replace as needed
}

local FEAR_BUFF_NAMES = {
  ["Shadow Howl"] = true,    -- example placeholder; replace as needed
}

local boss = RaidBoss.new(M.id, "Feratha", {
  attack_distance = 18,
  nav_timeout_ms = 30000,
  mez_buff_names = MEZ_BUFF_NAMES,
  fear_buff_names = FEAR_BUFF_NAMES,
})

local function me_name()
  local n = mq.TLO.Me.Name()
  return (type(n) == 'function') and n() or n
end

local function say(msg)
  mq.cmdf('/dga /echo [Feratha:%s] %s', mq.TLO.Me.Name() or 'Me', msg)
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
end

M.commands = {}

M.commands.startfight = function()
  boss.start_fight()
  say("Fight started.")
end

M.commands.stopfight = function()
  boss.stop_fight()
  say("Fight stopped.")
end

M.commands.mtset = function()
  local name = BossRoles.set_mt(M.id)
  boss.reload_roles()
  say("MT set to " .. tostring(name))
end

M.commands.bmtset = function()
  local name = BossRoles.set_bmt(M.id)
  boss.reload_roles()
  say("BMT set to " .. tostring(name))
end

M.commands.maset = function()
  local name = BossRoles.set_ma(M.id)
  boss.reload_roles()
  say("MA set to " .. tostring(name))
end

M.commands.mtclear = function()
  BossRoles.clear_mt(M.id)
  boss.reload_roles()
  say("MT cleared")
end

M.commands.bmtclear = function()
  BossRoles.clear_bmt(M.id)
  boss.reload_roles()
  say("BMT cleared")
end

M.commands.maclear = function()
  BossRoles.clear_ma(M.id)
  boss.reload_roles()
  say("MA cleared")
end

M.commands.rtadd = function()
  local name = BossRoles.add_rampage_tank(M.id)
  boss.reload_roles()
  say("Rampage tank added " .. tostring(name))
end

M.commands.rtdel = function()
  local name = BossRoles.remove_rampage_tank(M.id)
  boss.reload_roles()
  say("Rampage tank removed " .. tostring(name))
end

M.commands.rtclear = function()
  BossRoles.clear_rampage_tanks(M.id)
  boss.reload_roles()
  say("All rampage tanks cleared")
end

M.commands.otadd = function()
  local name = BossRoles.add_offtank(M.id)
  boss.reload_roles()
  say("Offtank added " .. tostring(name))
end

M.commands.otdel = function()
  local name = BossRoles.remove_offtank(M.id)
  boss.reload_roles()
  say("Offtank removed " .. tostring(name))
end

M.commands.otclear = function()
  BossRoles.clear_offtanks(M.id)
  boss.reload_roles()
  say("All offtanks cleared")
end

M.commands.otstatus = function()
  local names = BossRoles.get_offtank_names(M.id)
  local mine = BossRoles.get_offtank_mobs(M.id, me_name())

  say(
    "OTs=" .. (#names > 0 and table.concat(names, ", ") or "none") ..
    " my_mobs=" .. (#mine > 0 and table.concat(mine, ", ") or "default/any")
  )
end

M.commands.otsetmobs = function(ctx, args)
  local spec = table.concat(args or {}, ' ')
  if spec == '' then
    say("Usage: /autobot oow_rss_feratha otsetmobs <mob1|mob2|...>")
    return
  end

  local mobs = BossRoles.set_offtank_mobs(M.id, nil, spec)
  boss.reload_roles()
  say("Offtank mob filters set: " .. (#mobs > 0 and table.concat(mobs, ", ") or "none"))
end

M.commands.otclearmobs = function()
  BossRoles.clear_offtank_mobs(M.id)
  boss.reload_roles()
  say("Offtank mob filters cleared")
end

M.commands.rtstatus = function()
  local r = BossRoles.get_rampage_tanks(M.id)
  say("RT: " .. (#r > 0 and table.concat(r, ", ") or "none"))
end

M.commands.tankstatus = function()
  local ots = BossRoles.get_offtank_names(M.id)
  say(
    "MT=" .. tostring(BossRoles.get_mt(M.id)) ..
    " BMT=" .. tostring(BossRoles.get_bmt(M.id)) ..
    " MA=" .. tostring(BossRoles.get_ma(M.id)) ..
    " OTs=" .. (#ots > 0 and table.concat(ots, ", ") or "none")
  )
end

M.commands.mastatus = function()
  local ma = BossRoles.get_ma(M.id)
  local mine = BossRoles.is_ma(M.id, me_name())
  say(
    "MA=" .. tostring(ma) ..
    " me=" .. tostring(me_name()) ..
    " is_ma=" .. tostring(mine)
  )
end

return M