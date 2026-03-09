-- AutoBot/lib/log.lua
local mq = require('mq')

local M = {}

function M.make(prefix, debugFlagFn)
  local function who()
    return mq.TLO.Me.Name() or 'Me'
  end

  local function stamp()
    return string.format('[%s:%s]', prefix, who())
  end

  local function log(msg)
    print(string.format('%s %s', stamp(), tostring(msg)))
  end

  local function dbg(msg)
    local dbgOn = false
    if type(debugFlagFn) == 'function' then
      local ok, v = pcall(debugFlagFn)
      if ok then dbgOn = v == true end
    end
    if dbgOn then
      log('[debug] ' .. tostring(msg))
    end
  end

  return {
    log = log,
    dbg = dbg,
  }
end

return M