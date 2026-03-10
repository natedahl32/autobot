local mq = require('mq')

local BossRoles = require('AutoBot.lib.bossroles')
local BossCombat = require('AutoBot.lib.bosscombat')
local CTWN = require('AutoBot.lib.cwtn')
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

    -- Check roles and turn on correct CWTN modes
    if BossRoles.is_ma(self.module_id, me()) then
        CTWN.vorpal_on()
    elseif self.is_ot() or self.is_mt() or self.is_bmt() then
        CTWN.sic_tank_on()
    end

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
          local summary = self.role_summary and self.role_summary() or nil
          if sayFn and summary then
            sayFn('Role loaded: ' .. summary)
          end
        end
      end,

      stop = function(ctx, args)
        if moduleTable and moduleTable.stop then
          moduleTable.stop(ctx)
        else
          self.stop()
          local summary = self.role_summary and self.role_summary() or nil
          if sayFn and summary then
            sayFn('Module stopped. Role=' .. summary)
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

      reloadroles = function(ctx, args)
        self.reload_roles()
        if sayFn then
          local summary = self.role_summary and self.role_summary() or nil
          if summary then
            sayFn('Roles reloaded. Role=' .. summary)
          end
        end
      end,
    }
  end

  function self.standard_role_commands(sayFn)
    return {
      mtset = function(ctx, args)
        local name = BossRoles.set_mt(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('MT set to ' .. tostring(name)) end
      end,

      bmtset = function(ctx, args)
        local name = BossRoles.set_bmt(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('BMT set to ' .. tostring(name)) end
      end,

      maset = function(ctx, args)
        local name = BossRoles.set_ma(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('MA set to ' .. tostring(name)) end
      end,

      mtclear = function(ctx, args)
        BossRoles.clear_mt(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('MT cleared') end
      end,

      bmtclear = function(ctx, args)
        BossRoles.clear_bmt(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('BMT cleared') end
      end,

      maclear = function(ctx, args)
        BossRoles.clear_ma(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('MA cleared') end
      end,

      rtadd = function(ctx, args)
        local name = BossRoles.add_rampage_tank(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('Rampage tank added ' .. tostring(name)) end
      end,

      rtdel = function(ctx, args)
        local name = BossRoles.remove_rampage_tank(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('Rampage tank removed ' .. tostring(name)) end
      end,

      rtclear = function(ctx, args)
        BossRoles.clear_rampage_tanks(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('All rampage tanks cleared') end
      end,

      rtstatus = function(ctx, args)
        local r = BossRoles.get_rampage_tanks(self.module_id)
        if sayFn then
          sayFn('RT: ' .. (#r > 0 and table.concat(r, ', ') or 'none'))
        end
      end,

      otadd = function(ctx, args)
        local name = BossRoles.add_offtank(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('Offtank added ' .. tostring(name)) end
      end,

      otdel = function(ctx, args)
        local name = BossRoles.remove_offtank(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('Offtank removed ' .. tostring(name)) end
      end,

      otclear = function(ctx, args)
        BossRoles.clear_offtanks(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('All offtanks cleared') end
      end,

      otstatus = function(ctx, args)
        local names = BossRoles.get_offtank_names(self.module_id)
        local mine = BossRoles.get_offtank_mobs(self.module_id, me())
        if sayFn then
          sayFn(
            'OTs=' .. (#names > 0 and table.concat(names, ', ') or 'none') ..
            ' my_mobs=' .. (#mine > 0 and table.concat(mine, ', ') or 'default/any')
          )
        end
      end,

      otsetmobs = function(ctx, args)
        local spec = table.concat(args or {}, ' ')
        if spec == '' then
          if sayFn then sayFn('Usage: otsetmobs <mob1|mob2|...>') end
          return
        end

        local mobs = BossRoles.set_offtank_mobs(self.module_id, nil, spec)
        self.reload_roles()
        if sayFn then
          sayFn('Offtank mob filters set: ' .. (#mobs > 0 and table.concat(mobs, ', ') or 'none'))
        end
      end,

      otclearmobs = function(ctx, args)
        BossRoles.clear_offtank_mobs(self.module_id)
        self.reload_roles()
        if sayFn then sayFn('Offtank mob filters cleared') end
      end,

      tankstatus = function(ctx, args)
        local ots = BossRoles.get_offtank_names(self.module_id)
        if sayFn then
          sayFn(
            'MT=' .. tostring(BossRoles.get_mt(self.module_id)) ..
            ' BMT=' .. tostring(BossRoles.get_bmt(self.module_id)) ..
            ' MA=' .. tostring(BossRoles.get_ma(self.module_id)) ..
            ' OTs=' .. (#ots > 0 and table.concat(ots, ', ') or 'none')
          )
        end
      end,

      mastatus = function(ctx, args)
        local ma = BossRoles.get_ma(self.module_id)
        local mine = BossRoles.is_ma(self.module_id, me())
        if sayFn then
          sayFn(
            'MA=' .. tostring(ma) ..
            ' me=' .. tostring(me()) ..
            ' is_ma=' .. tostring(mine)
          )
        end
      end,
    }
  end

  function self.standard_help(opts)
    opts = opts or {}

    local lines = {}

    if opts.title and opts.title ~= '' then
      table.insert(lines, opts.title)
      table.insert(lines, '')
    end

    table.insert(lines, 'Commands:')
    table.insert(lines, ('  /autobot %s start'):format(self.module_id))
    table.insert(lines, ('  /autobot %s stop'):format(self.module_id))
    table.insert(lines, ('  /autobot %s startfight'):format(self.module_id))
    table.insert(lines, ('  /autobot %s stopfight'):format(self.module_id))
    table.insert(lines, ('  /autobot %s status'):format(self.module_id))

    table.insert(lines, ('  /autobot %s mtset'):format(self.module_id))
    table.insert(lines, ('  /autobot %s bmtset'):format(self.module_id))
    table.insert(lines, ('  /autobot %s maset'):format(self.module_id))
    table.insert(lines, ('  /autobot %s mtclear'):format(self.module_id))
    table.insert(lines, ('  /autobot %s bmtclear'):format(self.module_id))
    table.insert(lines, ('  /autobot %s maclear'):format(self.module_id))

    table.insert(lines, ('  /autobot %s rtadd'):format(self.module_id))
    table.insert(lines, ('  /autobot %s rtdel'):format(self.module_id))
    table.insert(lines, ('  /autobot %s rtclear'):format(self.module_id))
    table.insert(lines, ('  /autobot %s rtstatus'):format(self.module_id))

    if opts.include_ot then
      table.insert(lines, ('  /autobot %s otadd'):format(self.module_id))
      table.insert(lines, ('  /autobot %s otdel'):format(self.module_id))
      table.insert(lines, ('  /autobot %s otclear'):format(self.module_id))
      table.insert(lines, ('  /autobot %s otstatus'):format(self.module_id))
      table.insert(lines, ('  /autobot %s otsetmobs <mob1|mob2|...>'):format(self.module_id))
      table.insert(lines, ('  /autobot %s otclearmobs'):format(self.module_id))
    end

    table.insert(lines, ('  /autobot %s tankstatus'):format(self.module_id))
    table.insert(lines, ('  /autobot %s mastatus'):format(self.module_id))
    table.insert(lines, ('  /autobot %s reloadroles'):format(self.module_id))

    if opts.extra and #opts.extra > 0 then
      table.insert(lines, '')
      for _, line in ipairs(opts.extra) do
        table.insert(lines, line)
      end
    end

    return lines
  end

  function self.merge_commands(...)
    local out = {}
    for i = 1, select('#', ...) do
      local t = select(i, ...)
      if t then
        for k, v in pairs(t) do
          out[k] = v
        end
      end
    end
    return out
  end

  return self
end

return M