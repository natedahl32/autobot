local mq = require('mq')

local RaidBoss = require('AutoBot.lib.raidboss')
local BossRoles = require('AutoBot.lib.bossroles')

local M = {}

M.id = "oow_wos_velitorkin"

M.help = {
  'Omens of War - Wall of Slaughter - Velitorkin',
  '',
  'Commands:',
  '  /autobot oow_wos_velitorkin start',
  '  /autobot oow_wos_velitorkin stop',
  '  /autobot oow_wos_velitorkin startfight',
  '  /autobot oow_wos_velitorkin stopfight',
  '  /autobot oow_wos_velitorkin mtset',
  '  /autobot oow_wos_velitorkin bmtset',
  '  /autobot oow_wos_velitorkin maset',
  '  /autobot oow_wos_velitorkin mtclear',
  '  /autobot oow_wos_velitorkin bmtclear',
  '  /autobot oow_wos_velitorkin maclear',
  '  /autobot oow_wos_velitorkin rtadd',
  '  /autobot oow_wos_velitorkin rtdel',
  '  /autobot oow_wos_velitorkin rtclear',
  '  /autobot oow_wos_velitorkin tankstatus',
  '  /autobot oow_wos_velitorkin rtstatus',
  '  /autobot oow_wos_velitorkin mastatus',
}

local boss = RaidBoss.new(M.id, "Velitorkin")

local function me_name()
  local n = mq.TLO.Me.Name()
  return (type(n) == 'function') and n() or n
end

local function say(msg)
  mq.cmdf('/dga /echo [Velitorkin:%s] %s', mq.TLO.Me.Name() or 'Me', msg)
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

M.commands.rtstatus = function()
  local r = BossRoles.get_rampage_tanks(M.id)
  say("RT: " .. (#r > 0 and table.concat(r, ", ") or "none"))
end

M.commands.tankstatus = function()
  say(
    "MT=" .. tostring(BossRoles.get_mt(M.id)) ..
    " BMT=" .. tostring(BossRoles.get_bmt(M.id)) ..
    " MA=" .. tostring(BossRoles.get_ma(M.id))
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