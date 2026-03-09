local mq = require('mq')

local BossRoles = require('AutoBot.lib.bossroles')
local BossCombat = require('AutoBot.lib.bosscombat')
local Spawn = require('AutoBot.lib.spawn')

local M = {}

local function now()
  return mq.gettime()
end

local function me()
  local n = mq.TLO.Me.Name()
  return (type(n) == 'function') and n() or n
end

local function norm_name(name)
  name = (name or ''):lower()
  name = name:gsub('_', ' ')
  name = name:gsub('%d+$', '')
  name = name:gsub('%s+', ' ')
  name = name:gsub('^%s+', ''):gsub('%s+$', '')
  return name
end

local function list_to_map(list)
  local map = {}
  if not list then return map end
  for _, v in ipairs(list) do
    map[norm_name(v)] = true
  end
  return map
end

local function safe_spawn_target_name(spawnObj)
  if not spawnObj or not spawnObj() then return nil end

  local ok, val = pcall(function()
    if spawnObj.Target and spawnObj.Target() then
      local t = spawnObj.Target
      if t.CleanName and t.CleanName() then return t.CleanName() end
      if t.Name and t.Name() then return t.Name() end
    end
    return nil
  end)

  if ok and val then
    return tostring(val)
  end

  return nil
end

local function iter_xtarget_spawns()
  local cnt = mq.TLO.Me.XTarget()
  cnt = (type(cnt) == 'function') and cnt() or (cnt or 0)
  if not cnt or cnt <= 0 then
    return function() end
  end

  local i = 0
  return function()
    while true do
      i = i + 1
      if i > cnt then return nil end

      local xt = mq.TLO.Me.XTarget(i)
      if xt and xt() then
        local id = xt.ID()
        if id and id > 0 then
          local s = mq.TLO.Spawn(('id %d'):format(id))
          if s and s() then
            return s
          end
        end
      end
    end
  end
end

function M.new(module_id, boss_name, opts)
  opts = opts or {}

  local self = {
    module_id = module_id,
    boss_name = boss_name,

    running = false,
    fight_started = false,
    fight_start_time = 0,

    mt_tagged = false,
    rt_tagged = false,
    bmt_tagged = false,

    roles = {
      main_tank = nil,
      backup_tank = nil,
      main_assist = nil,
      rampage_tanks = {},
      offtanks = {},
      offtank_group = 'raid_offtanks',
    },

    attack_distance = opts.attack_distance or 18,
    nav_timeout_ms = opts.nav_timeout_ms or 30000,

    mt_tag_delay_ms = opts.mt_tag_delay_ms or 1000,
    rt_tag_delay_ms = opts.rt_tag_delay_ms or 2000,
    bmt_tag_delay_ms = opts.bmt_tag_delay_ms or 3000,

    default_offtank_names = opts.default_offtank_names or nil,
    default_offtank_name_map = list_to_map(opts.default_offtank_names or nil),

    mez_buff_names = opts.mez_buff_names or {},
    fear_buff_names = opts.fear_buff_names or {},
  }

  function self.reload_roles()
    self.roles = BossRoles.load_for_module(module_id)
  end

  function self.is_mt()
    return self.roles.main_tank == me()
  end

  function self.is_bmt()
    return self.roles.backup_tank == me()
  end

  function self.is_ma()
    return self.roles.main_assist == me()
  end

  function self.is_rt()
    local m = me()
    for _, n in ipairs(self.roles.rampage_tanks or {}) do
      if n == m then return true end
    end
    return false
  end

  function self.is_ot()
    local m = me()
    return self.roles.offtanks ~= nil and self.roles.offtanks[m] ~= nil
  end

  function self.role()
    if self.is_mt() then return 'MT' end
    if self.is_bmt() then return 'BMT' end
    if self.is_ma() then return 'MA' end
    if self.is_rt() then return 'RT' end
    if self.is_ot() then return 'OT' end
    return nil
  end

  function self.role_summary()
    local parts = {}

    if self.is_mt() then table.insert(parts, 'MT') end
    if self.is_bmt() then table.insert(parts, 'BMT') end
    if self.is_ma() then table.insert(parts, 'MA') end
    if self.is_rt() then table.insert(parts, 'RT') end
    if self.is_ot() then table.insert(parts, 'OT') end

    if #parts == 0 then
      return nil
    end

    return table.concat(parts, '/')
  end

  function self.reset_opener()
    self.mt_tagged = false
    self.rt_tagged = false
    self.bmt_tagged = false
  end

  function self.start()
    self.running = true
    self.reload_roles()
    self.reset_opener()
  end

  function self.stop()
    self.running = false
    mq.cmd('/attack off')
  end

  function self.start_fight()
    self.fight_started = true
    self.fight_start_time = now()
    self.reset_opener()
  end

  function self.stop_fight()
    self.fight_started = false
    mq.cmd('/attack off')
  end

  function self.elapsed()
    return now() - self.fight_start_time
  end

  function self.phase()
    local e = self.elapsed()

    if e < self.mt_tag_delay_ms then
      return 'mt'
    elseif e < self.rt_tag_delay_ms then
      return 'rt'
    elseif e < self.bmt_tag_delay_ms then
      return 'bmt'
    else
      return 'live'
    end
  end

  function self.boss_up()
    return Spawn.spawn_by_name(self.boss_name) ~= nil
  end

  function self.mt_opener()
    if self.mt_tagged then return end
    local ok = BossCombat.ranged_tag_boss(self.boss_name)
    if ok then self.mt_tagged = true end
  end

  function self.rt_opener()
    if self.rt_tagged then return end
    local ok = BossCombat.ranged_tag_boss(self.boss_name)
    if ok then self.rt_tagged = true end
  end

  function self.bmt_opener()
    if self.bmt_tagged then return end
    local ok = BossCombat.ranged_tag_boss(self.boss_name)
    if ok then self.bmt_tagged = true end
  end

  function self.live_combat()
    local ok = BossCombat.keep_on_boss(self.boss_name, self.attack_distance, self.nav_timeout_ms)
    if not ok then
      mq.cmd('/attack off')
    end
  end

  function self.offtank_filter_map()
    local entry = self.roles.offtanks and self.roles.offtanks[me()]
    if entry and entry.mobs and #entry.mobs > 0 then
      return list_to_map(entry.mobs)
    end

    if self.default_offtank_name_map and next(self.default_offtank_name_map) ~= nil then
      return self.default_offtank_name_map
    end

    return nil
  end

  function self.other_offtank_names()
    local out = {}
    local mine = me()

    for name, _ in pairs(self.roles.offtanks or {}) do
      if name ~= mine then
        out[name] = true
      end
    end

    return out
  end

  function self.is_ccd(spawnObj)
    if not spawnObj or not spawnObj() then return false end

    if self.mez_buff_names and next(self.mez_buff_names) ~= nil then
      if Spawn.spawn_has_any_buff(spawnObj, self.mez_buff_names) then
        return true
      end
    end

    if self.fear_buff_names and next(self.fear_buff_names) ~= nil then
      if Spawn.spawn_has_any_buff(spawnObj, self.fear_buff_names) then
        return true
      end
    end

    return false
  end

  function self.is_valid_offtank_target(spawnObj)
    if not spawnObj or not spawnObj() then return false end

    local rawName = spawnObj.Name() or ''
    local name = norm_name(rawName)

    if name == '' then return false end
    if name == norm_name(self.boss_name) then return false end

    -- respect configured/default add-name filters if present
    local filterMap = self.offtank_filter_map()
    if filterMap and not filterMap[name] then
      return false
    end

    -- skip mezzed/fear targets
    if self.is_ccd(spawnObj) then
      return false
    end

    -- skip anything already targeting another offtank
    local tgtName = safe_spawn_target_name(spawnObj)
    if tgtName and tgtName ~= '' then
      local otherOTs = self.other_offtank_names()
      if otherOTs[tostring(tgtName)] then
        return false
      end
    end

    return true
  end

  function self.find_offtank_target()
    local best = nil
    local bestDist = 999999

    for s in iter_xtarget_spawns() do
      if self.is_valid_offtank_target(s) then
        local d = s.Distance() or 999999
        if d < bestDist then
          best = s
          bestDist = d
        end
      end
    end

    return best
  end

  function self.keep_on_spawn(spawnObj)
    if not spawnObj or not spawnObj() then
      mq.cmd('/attack off')
      return false, 'spawn missing'
    end

    local id = spawnObj.ID()
    if not id or id <= 0 then
      mq.cmd('/attack off')
      return false, 'invalid spawn id'
    end

    local dist = spawnObj.Distance() or 999999
    if dist > self.attack_distance then
      mq.cmdf('/nav id %d', id)
      local reached = Spawn.wait_until_close(id, self.attack_distance, self.nav_timeout_ms)
      if not reached then
        mq.cmd('/attack off')
        return false, 'nav timeout'
      end
      mq.delay(150)
    end

    Spawn.target_id(id)
    mq.cmd('/pet attack')

    if (mq.TLO.Target.Distance() or 9999) <= self.attack_distance then
      mq.cmd('/attack on')
    else
      mq.cmd('/attack off')
    end

    return true
  end

  function self.offtank_live()
    local target = self.find_offtank_target()
    if not target then
      mq.cmd('/attack off')
      return
    end

    local ok = self.keep_on_spawn(target)
    if not ok then
      mq.cmd('/attack off')
    end
  end

  function self.tick()
    if not self.running then return end
    if not self.fight_started then return end

    if self.boss_up() then
      local phase = self.phase()

      if phase == 'mt' then
        if self.is_mt() then self.mt_opener() end
        mq.cmd('/attack off')
        return
      end

      if phase == 'rt' then
        if self.is_rt() then self.rt_opener() end
        mq.cmd('/attack off')
        return
      end

      if phase == 'bmt' then
        if self.is_bmt() then self.bmt_opener() end
        mq.cmd('/attack off')
        return
      end
    end

    -- live phase
    if self.is_mt() or self.is_bmt() or self.is_rt() then
      if self.boss_up() then
        self.live_combat()
      else
        mq.cmd('/attack off')
      end
      return
    end

    if self.is_ot() then
      self.offtank_live()
      return
    end
  end

  function self.standard_commands(moduleTable, sayFn)
    return {
      start = function(ctx, args)
        if moduleTable and moduleTable.start then
          moduleTable.start(ctx)
        else
          self.start()
          if sayFn then
            local summary = self.role_summary and self.role_summary() or nil
            if summary then
              sayFn('Role loaded: ' .. summary)
            end
          end
        end
      end,

      stop = function(ctx, args)
        if moduleTable and moduleTable.stop then
          moduleTable.stop(ctx)
        else
          self.stop()
          if sayFn then
            local summary = self.role_summary and self.role_summary() or nil
            if summary then
              sayFn('Module stopped. Role=' .. summary)
            end
          end
        end
      end,

      startfight = function(ctx, args)
        self.start_fight()
        if sayFn then
          sayFn('Fight started.')
        end
      end,

      stopfight = function(ctx, args)
        self.stop_fight()
        if sayFn then
          sayFn('Fight stopped.')
        end
      end,

      status = function(ctx, args)
        if sayFn then
          local summary = self.role_summary and self.role_summary() or 'none'
          sayFn('Role=' .. tostring(summary) .. ' fight_started=' .. tostring(self.fight_started))
        end
      end,
    }
  end

  return self
end

return M