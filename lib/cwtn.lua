-- AutoBot/lib/cwtn.lua
local mq = require('mq')

local M = {}

local function class_short_lower()
  return M.class_short_lower()
end

function M.class_short()
  local s = mq.TLO.Me.Class.ShortName()
  return (type(s) == "function") and s() or s
end

function M.class_short_lower()
  local s = M.class_short()
  return s and s:lower() or nil
end

function M.byos_on()
  local short = class_short_lower(); if not short then return end
  mq.cmdf('/%s BYOS on nosave', short)
end

function M.byos_off()
  local short = class_short_lower(); if not short then return end
  mq.cmdf('/%s BYOS off nosave', short)
end

function M.manual_on()
  local short = class_short_lower(); if not short then return end
  mq.cmdf('/%s mode 0 nosave', short)
end

function M.manual_off()
  local short = class_short_lower(); if not short then return end
  mq.cmdf('/%s mode 2 nosave', short)
end

function M.vorpal_on()
  local short = class_short_lower(); if not short then return end
  mq.cmdf('/%s mode 3 nosave', short)
end

function M.sic_tank_on()
  local short = class_short_lower(); if not short then return end
  mq.cmdf('/%s mode 7 nosave', short)
end

function M.pause_on()
  local short = class_short_lower(); if not short then return end
  mq.cmdf('/%s pause on', short)
end

function M.pause_off()
  local short = class_short_lower(); if not short then return end
  mq.cmdf('/%s pause off', short)
end

function M.with_manual_mode(fn)
  M.manual_on()
  local ok, err = pcall(fn)
  M.manual_off()
  return ok, err
end

return M