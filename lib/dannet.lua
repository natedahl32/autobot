local mq = require('mq')

local M = {}

function M.joined_group(groupName)
  local joined = mq.TLO.DanNet.Joined()
  joined = (type(joined) == 'function') and joined() or joined
  joined = tostring(joined or '')
  local norm = '|' .. joined:gsub('%s+', '') .. '|'
  return norm:find('|' .. groupName .. '|', 1, true) ~= nil
end

function M.join_group(groupName)
  if not groupName or groupName == '' then return false end
  if M.joined_group(groupName) then return true end
  mq.cmdf('/djoin %s', groupName)
  mq.delay(100)
  return M.joined_group(groupName)
end

function M.leave_group(groupName)
  if not groupName or groupName == '' then return false end
  if not M.joined_group(groupName) then return true end
  mq.cmdf('/dleave %s', groupName)
  mq.delay(100)
  return not M.joined_group(groupName)
end

function M.dga_echo(msg)
  mq.cmdf('/dga /echo %s', msg)
end

return M