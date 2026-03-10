local mq = require('mq')

local RaidBoss = require('AutoBot.lib.raidboss')

local M = {}

M.id = "oow_mpg_endurance"

-- Replace these with the real mez/fear buff names you use on this encounter.
local MEZ_BUFF_NAMES = {
  -- ["Your Mez Spell Name"] = true,
}

local FEAR_BUFF_NAMES = {
  -- ["Your Fear Spell Name"] = true,
}

local boss = RaidBoss.new(M.id, "Ansdaicher", {
  opener_mode = 'offtank_first',
  ma_target_source = 'xtarget',
  ma_priority = {
    'a Muramite sentinel',
    'a dragorn defender',
    'a frantic discordling',
    'a dragorn antagonist',
    'a dragorn champion',
  },
  offtank_ordered_pull = true,
  mez_buff_names = MEZ_BUFF_NAMES,
  fear_buff_names = FEAR_BUFF_NAMES,
})

M.help = boss.standard_help({
  title = 'Omens of War - MPG Raid Trial - The Mastery of Endurance',
  include_ot = true,
  extra = {
    'Notes:',
    '  Assign Drolador and Bricklayor as Offtanks for Ansdaicher and Zellucheraz.',
    '  Assign other tanks as Offtanks for specific add names using otsetmobs.',
    '  Do not include Ansdaicher or Zellucheraz in MA priority.',
    '  MA will only target mobs listed in ma_priority.',
    '  Fight starts with offtanks picking up their assigned targets first.',
    '  Do not use startbossphase unless you intentionally want boss-phase tank logic.',
  },
})

local function say(msg)
  mq.cmdf('/dga /echo [Endurance:%s] %s', mq.TLO.Me.Name() or 'Me', msg)
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
  boss.standard_role_commands(say, { include_ot = true })
)

return M