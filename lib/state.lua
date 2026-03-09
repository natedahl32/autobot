-- AutoBot/lib/state.lua
local M = {}

function M.make_ttl_map(ttlMs)
  return { ttl = ttlMs or 600000, data = {} }
end

function M.ttl_get(map, key, defaultFactory, nowMs)
  local d = map.data
  local v = d[key]
  if not v then
    v = defaultFactory()
    d[key] = v
  end
  v.last = nowMs
  return v
end

function M.ttl_cleanup(map, nowMs)
  local ttl = map.ttl
  for k, v in pairs(map.data) do
    if (nowMs - (v.last or 0)) > ttl then
      map.data[k] = nil
    end
  end
end

function M.make_lock_map(lockMs)
  return { lock = lockMs or 20000, data = {} }
end

function M.locked(lockMap, key, nowMs)
  local t = lockMap.data[key]
  if not t then return false end
  return (nowMs - t) < lockMap.lock
end

function M.lock(lockMap, key, nowMs)
  lockMap.data[key] = nowMs
end

return M