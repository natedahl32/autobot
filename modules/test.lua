-- AutoBot/modules/test.lua
local Spawn  = require('AutoBot.lib.spawn')

local M = {}

M.id = 'test'
M.name = 'Test Module'

-- Optional: shown in /autobot list later if you want
M.help = {
  'test helloworld  - prints "hello world"'
}

-- Module-owned commands:
-- args = { "helloworld", ... }
M.commands = {}

M.commands.helloworld = function(ctx, args)
  local spawn = Spawn.spawn_by_name('bixbot')
  ctx.log(spawn.Name())
end

return M