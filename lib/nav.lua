-- AutoBot/lib/nav.lua
local mq = require('mq')

local M = {}

local state = {
  kind = nil,         -- 'loc' or 'id'
  key = nil,          -- unique string describing the current nav request
  started_at = 0,
  grace_ms = 1500,    -- how long to give nav to become active before declaring failure
}

local function now_ms()
  return mq.gettime()
end

function M.active()
  local v = mq.TLO.Nav.Active()
  return (type(v) == 'function') and v() == true or v == true
end

function M.reset()
  state.kind = nil
  state.key = nil
  state.started_at = 0
  state.grace_ms = 1500
end

local function begin_request(kind, key, cmd, graceMs)
  state.kind = kind
  state.key = key
  state.started_at = now_ms()
  state.grace_ms = graceMs or 1500
  mq.cmd(cmd)
end

-- Generic status machine:
-- returns:
--   true,  'arrived'
--   false, 'started'
--   false, 'navigating'
--   false, 'failed'
--
-- arrived_fn must return true when destination is reached.
function M.ensure_loc(y, x, z, arrived_fn, graceMs)
  if arrived_fn() then
    M.reset()
    return true, 'arrived'
  end

  local key = ('loc:%s,%s,%s'):format(tostring(y), tostring(x), tostring(z))

  if state.kind ~= 'loc' or state.key ~= key then
    begin_request('loc', key, ('/nav loc %s %s %s'):format(y, x, z), graceMs)
    return false, 'started'
  end

  if M.active() then
    return false, 'navigating'
  end

  -- nav is not active and we still haven't arrived
  if (now_ms() - state.started_at) >= (state.grace_ms or 1500) then
    M.reset()
    return false, 'failed'
  end

  return false, 'started'
end

function M.ensure_id(spawnID, arrived_fn, graceMs)
  if arrived_fn() then
    M.reset()
    return true, 'arrived'
  end

  local key = ('id:%s'):format(tostring(spawnID))

  if state.kind ~= 'id' or state.key ~= key then
    begin_request('id', key, ('/nav id %d'):format(spawnID), graceMs)
    return false, 'started'
  end

  if M.active() then
    return false, 'navigating'
  end

  if (now_ms() - state.started_at) >= (state.grace_ms or 1500) then
    M.reset()
    return false, 'failed'
  end

  return false, 'started'
end

return M