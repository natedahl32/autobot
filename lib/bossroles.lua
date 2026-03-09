-- AutoBot/lib/bossroles.lua
local mq = require('mq')
local Config = require('AutoBot.lib.config')
local DanNet = require('AutoBot.lib.dannet')

local M = {}

-- cache[moduleId] = {
--   main_tank=...,
--   backup_tank=...,
--   main_assist=...,
--   rampage_tanks={...},
--   offtanks = {
--     ["Name"] = { mobs = {"mob a", "mob b"} }
--   },
--   offtank_group = 'raid_offtanks',
-- }
local cache = {}

local DEFAULT_OFFTANK_GROUP = 'raid_offtanks'

local function me_name()
  local n = mq.TLO.Me.Name()
  return (type(n) == 'function') and n() or n
end

local function clone_array(src)
  local out = {}
  if src then
    for i, v in ipairs(src) do
      out[i] = v
    end
  end
  return out
end

local function clone_offtanks(src)
  local out = {}
  if not src then return out end

  for name, data in pairs(src) do
    out[name] = {
      mobs = clone_array(data and data.mobs or {}),
    }
  end

  return out
end

local function defaults()
  return {
    main_tank = nil,
    backup_tank = nil,
    main_assist = nil,
    rampage_tanks = {},
    offtanks = {},
    offtank_group = DEFAULT_OFFTANK_GROUP,
  }
end

local function clone_roles(src)
  return {
    main_tank = src.main_tank,
    backup_tank = src.backup_tank,
    main_assist = src.main_assist,
    rampage_tanks = clone_array(src.rampage_tanks),
    offtanks = clone_offtanks(src.offtanks),
    offtank_group = src.offtank_group or DEFAULT_OFFTANK_GROUP,
  }
end

local function ensure_loaded(moduleId)
  if cache[moduleId] then
    return cache[moduleId]
  end

  local loaded = Config.load(moduleId .. '_roles', defaults())
  loaded.main_tank = loaded.main_tank or nil
  loaded.backup_tank = loaded.backup_tank or nil
  loaded.main_assist = loaded.main_assist or nil
  loaded.rampage_tanks = loaded.rampage_tanks or {}
  loaded.offtanks = loaded.offtanks or {}
  loaded.offtank_group = loaded.offtank_group or DEFAULT_OFFTANK_GROUP

  cache[moduleId] = loaded
  return cache[moduleId]
end

local function save(moduleId)
  local roles = ensure_loaded(moduleId)
  Config.save(moduleId .. '_roles', roles)
end

local function normalize_mob_list(mobs)
  local out = {}

  if type(mobs) == 'string' then
    for part in mobs:gmatch('[^|]+') do
      local s = tostring(part):gsub('^%s+', ''):gsub('%s+$', '')
      if s ~= '' then
        table.insert(out, s)
      end
    end
  elseif type(mobs) == 'table' then
    for _, v in ipairs(mobs) do
      local s = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
      if s ~= '' then
        table.insert(out, s)
      end
    end
  end

  return out
end

local function ensure_offtank_entry(roles, name)
  roles.offtanks = roles.offtanks or {}
  roles.offtanks[name] = roles.offtanks[name] or { mobs = {} }
  roles.offtanks[name].mobs = roles.offtanks[name].mobs or {}
  return roles.offtanks[name]
end

function M.load_for_module(moduleId)
  return clone_roles(ensure_loaded(moduleId))
end

function M.reload_for_module(moduleId)
  cache[moduleId] = nil
  return clone_roles(ensure_loaded(moduleId))
end

function M.clear_cache(moduleId)
  if moduleId then
    cache[moduleId] = nil
  else
    cache = {}
  end
end

function M.get_roles(moduleId)
  return ensure_loaded(moduleId)
end

function M.get_mt(moduleId)
  return ensure_loaded(moduleId).main_tank
end

function M.get_bmt(moduleId)
  return ensure_loaded(moduleId).backup_tank
end

function M.get_ma(moduleId)
  return ensure_loaded(moduleId).main_assist
end

function M.get_rampage_tanks(moduleId)
  return ensure_loaded(moduleId).rampage_tanks
end

function M.get_offtank_group(moduleId)
  return ensure_loaded(moduleId).offtank_group or DEFAULT_OFFTANK_GROUP
end

function M.set_offtank_group(moduleId, groupName)
  local roles = ensure_loaded(moduleId)
  roles.offtank_group = (groupName and groupName ~= '') and groupName or DEFAULT_OFFTANK_GROUP
  save(moduleId)
  return roles.offtank_group
end

function M.get_offtanks(moduleId)
  return ensure_loaded(moduleId).offtanks
end

function M.get_offtank_names(moduleId)
  local roles = ensure_loaded(moduleId)
  local names = {}

  for name, _ in pairs(roles.offtanks or {}) do
    table.insert(names, name)
  end

  table.sort(names)
  return names
end

function M.get_offtank_mobs(moduleId, name)
  local roles = ensure_loaded(moduleId)
  local entry = roles.offtanks and roles.offtanks[name]
  if not entry then return {} end
  return clone_array(entry.mobs)
end

function M.set_mt(moduleId, name)
  local roles = ensure_loaded(moduleId)
  roles.main_tank = name or me_name()
  save(moduleId)
  return roles.main_tank
end

function M.set_bmt(moduleId, name)
  local roles = ensure_loaded(moduleId)
  roles.backup_tank = name or me_name()
  save(moduleId)
  return roles.backup_tank
end

function M.set_ma(moduleId, name)
  local roles = ensure_loaded(moduleId)
  roles.main_assist = name or me_name()
  save(moduleId)
  return roles.main_assist
end

function M.clear_mt(moduleId)
  local roles = ensure_loaded(moduleId)
  roles.main_tank = nil
  save(moduleId)
end

function M.clear_bmt(moduleId)
  local roles = ensure_loaded(moduleId)
  roles.backup_tank = nil
  save(moduleId)
end

function M.clear_ma(moduleId)
  local roles = ensure_loaded(moduleId)
  roles.main_assist = nil
  save(moduleId)
end

function M.add_rampage_tank(moduleId, name)
  local roles = ensure_loaded(moduleId)
  local who = name or me_name()

  for _, n in ipairs(roles.rampage_tanks) do
    if n == who then
      return who
    end
  end

  table.insert(roles.rampage_tanks, who)
  save(moduleId)
  return who
end

function M.remove_rampage_tank(moduleId, name)
  local roles = ensure_loaded(moduleId)
  local who = name or me_name()
  local out = {}

  for _, n in ipairs(roles.rampage_tanks) do
    if n ~= who then
      table.insert(out, n)
    end
  end

  roles.rampage_tanks = out
  save(moduleId)
  return who
end

function M.clear_rampage_tanks(moduleId)
  local roles = ensure_loaded(moduleId)
  roles.rampage_tanks = {}
  save(moduleId)
end

function M.add_offtank(moduleId, name, mobs)
  local roles = ensure_loaded(moduleId)
  local who = name or me_name()
  local entry = ensure_offtank_entry(roles, who)

  if mobs ~= nil then
    entry.mobs = normalize_mob_list(mobs)
  end

  save(moduleId)

  if who == me_name() then
    DanNet.join_group(roles.offtank_group)
  end

  return who
end

function M.remove_offtank(moduleId, name)
  local roles = ensure_loaded(moduleId)
  local who = name or me_name()

  if roles.offtanks then
    roles.offtanks[who] = nil
  end

  save(moduleId)

  if who == me_name() then
    DanNet.leave_group(roles.offtank_group)
  end

  return who
end

function M.clear_offtanks(moduleId)
  local roles = ensure_loaded(moduleId)
  local me = me_name()
  local was_offtank = roles.offtanks and roles.offtanks[me] ~= nil

  roles.offtanks = {}
  save(moduleId)

  if was_offtank then
    DanNet.leave_group(roles.offtank_group)
  end
end

function M.set_offtank_mobs(moduleId, name, mobs)
  local roles = ensure_loaded(moduleId)
  local who = name or me_name()
  local entry = ensure_offtank_entry(roles, who)

  entry.mobs = normalize_mob_list(mobs)
  save(moduleId)

  return clone_array(entry.mobs)
end

function M.clear_offtank_mobs(moduleId, name)
  local roles = ensure_loaded(moduleId)
  local who = name or me_name()
  local entry = ensure_offtank_entry(roles, who)

  entry.mobs = {}
  save(moduleId)

  return entry.mobs
end

function M.is_mt(moduleId, name)
  local who = name or me_name()
  local roles = ensure_loaded(moduleId)
  return roles.main_tank ~= nil and roles.main_tank == who
end

function M.is_bmt(moduleId, name)
  local who = name or me_name()
  local roles = ensure_loaded(moduleId)
  return roles.backup_tank ~= nil and roles.backup_tank == who
end

function M.is_ma(moduleId, name)
  local who = name or me_name()
  local roles = ensure_loaded(moduleId)
  return roles.main_assist ~= nil and roles.main_assist == who
end

function M.is_rampage_tank(moduleId, name)
  local who = name or me_name()
  local roles = ensure_loaded(moduleId)

  for _, n in ipairs(roles.rampage_tanks) do
    if n == who then
      return true
    end
  end

  return false
end

function M.is_offtank(moduleId, name)
  local who = name or me_name()
  local roles = ensure_loaded(moduleId)
  return roles.offtanks ~= nil and roles.offtanks[who] ~= nil
end

function M.is_any_tank(moduleId, name)
  return M.is_mt(moduleId, name)
      or M.is_bmt(moduleId, name)
      or M.is_rampage_tank(moduleId, name)
      or M.is_offtank(moduleId, name)
end

return M