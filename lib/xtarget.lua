-- AutoBot/lib/xtarget.lua
local mq = require('mq')

local M = {}

function M.count()
  local c = mq.TLO.Me.XTarget()
  if type(c) == "function" then
    return c() or 0
  end
  return c or 0
end

function M.spawn_by_index(index)
  local xt = mq.TLO.Me.XTarget(index)
  if not xt or not xt() then return nil end

  local id = xt.ID()
  if not id or id <= 0 then return nil end

  local s = mq.TLO.Spawn(("id %d"):format(id))
  if s and s() then
    return s
  end

  return nil
end

function M.iter_spawns()
  local cnt = M.count()
  if cnt <= 0 then
    return function() end
  end

  local i = 0

  return function()
    while true do
      i = i + 1
      if i > cnt then return nil end

      local s = M.spawn_by_index(i)
      if s then
        return s
      end
    end
  end
end

return M