local mq = require('mq')

local RaidBoss = require('AutoBot.lib.raidboss')

local M = {}

M.id = "oow_wos_velitorkin"

local boss = RaidBoss.new(M.id, "Velitorkin")

M.help = boss.standard_help({
  title = 'Omens of War - Wall of Slaughter - Velitorkin',
  include_ot = false,
})

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

M.commands = boss.merge_commands(
  boss.standard_commands(M, say),
  boss.standard_role_commands(say, {
    include_ot = false,
  })
)

return M