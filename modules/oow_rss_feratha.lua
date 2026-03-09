local mq = require('mq')

local RaidBoss = require('AutoBot.lib.raidboss')

local M = {}

M.id = "oow_rss_feratha"

M.help = boss.standard_help({
  title = 'Omens of War - Riftseekers Sanctum - Feratha',
  include_ot = true,
  extra = {
    'Notes:',
    '  Offtanks skip mezzed and feared mobs.',
  },
})

local MEZ_BUFF_NAMES = {
  ["Anxiety Attack"] = true,
}

local FEAR_BUFF_NAMES = {
  ["Shadow Howl"] = true,
}

local boss = RaidBoss.new(M.id, "Feratha", {
  attack_distance = 18,
  nav_timeout_ms = 30000,
  mez_buff_names = MEZ_BUFF_NAMES,
  fear_buff_names = FEAR_BUFF_NAMES,
})

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

M.commands = boss.merge_commands(
  boss.standard_commands(M, say),
  boss.standard_role_commands(say)
)

return M