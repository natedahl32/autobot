local mq = require('mq')

local M = {}

function M.joined_group(groupName)
  local joined = mq.TLO.DanNet.Joined()
  joined = (type(joined) == 'function') and joined() or joined
  joined = tostring(joined or '')
  local norm = '|' .. joined:gsub('%s+', '') .. '|'
  return norm:find('|' .. groupName .. '|', 1, true) ~= nil
end

function M.dga_echo(msg)
  mq.cmdf('/dga /echo %s', msg)
end

return M