-- AutoBot/lib/chat.lua
local mq = require('mq')

local M = {}

function M.tag(prefix)
  return string.format('[%s:%s]', tostring(prefix or 'AutoBot'), mq.TLO.Me.Name() or 'Me')
end

-- Broadcast to your whole crew (DanNet group assist style)
function M.dga_echo(msg)
  if not msg or msg == '' then return end
  mq.cmdf('/dga /echo %s', msg)
end

return M