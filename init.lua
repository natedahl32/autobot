-- AutoBot/init.lua
-- Run with: /lua run AutoBot
--
-- Folder layout:
--   lua/AutoBot/init.lua
--   lua/AutoBot/lib/log.lua
--   lua/AutoBot/modules/*.lua   (each module returns a table)

local mq = require('mq')
local Log = require('AutoBot.lib.log')
local PackageMan = require('mq.PackageMan')
local lfs = PackageMan.Require('luafilesystem', 'lfs')
if not lfs then
    print('\arError loading LuaFileSystem dependency, ending script\ax')
    mq.exit()
end
local tunpack = table.unpack or unpack

-- =========================
-- CONFIG
-- =========================
local DEBUG_DEFAULT = false

-- =========================
-- INTERNAL STATE
-- =========================
local running = true
local debug = DEBUG_DEFAULT

local modules = {}        -- id -> module table
local active = nil        -- active module table
local active_id = nil     -- string
local active_reason = nil -- last stop reason (for status)

local log = Log.make('AutoBot', function() return debug end)
local rebuild_triggers -- forward declare 
local register_chat_triggers -- forward declare

-- Context passed into modules
local ctx = {
  mq = mq,
  now = function() return mq.gettime() end,
  debug = function() return debug end,
  log = function(msg) log.log(msg) end,
  dbg = function(msg) log.dbg(msg) end,
}

-- =========================
-- MODULE LIFECYCLE
-- =========================
local function stop_active(reason)
  reason = reason or 'stop requested'
  if not active then
    active_reason = reason
    return
  end

  log.dbg(string.format('Stopping module "%s" (%s)', tostring(active_id), tostring(reason)))

  local ok, err = pcall(function()
    if active.stop then active.stop(ctx, reason) end
  end)

  if not ok then
    log.log(string.format('ERROR while stopping module "%s": %s', tostring(active_id), tostring(err)))
  end

  active = nil
  active_id = nil
  active_reason = reason
end

local function start_module(id, reason)
  local m = modules[id]
  if not m then
    log.log('Unknown module: ' .. tostring(id))
    return
  end

  if active then
    stop_active('switching to ' .. id)
  end

  if m.can_start then
    local ok, allowed_or_err = pcall(function() return m.can_start(ctx) end)
    if not ok then
      log.log(string.format('ERROR in %s.can_start: %s', id, tostring(allowed_or_err)))
      return
    end
    if not allowed_or_err then
      log.dbg(string.format('Module "%s" can_start returned false', id))
      return
    end
  end

  local ok, err = pcall(function()
    if m.start then m.start(ctx, reason or 'start requested') end
  end)
  if not ok then
    log.log(string.format('ERROR starting module "%s": %s', id, tostring(err)))
    return
  end

  active = m
  active_id = id
  active_reason = nil
  log.log(string.format('Started module "%s"%s', id, reason and (' (' .. reason .. ')') or ''))
end

-- =========================
-- MODULE LOADING
-- =========================
local function module_require_name(modname)
  return 'AutoBot.modules.' .. modname
end

local function unload_module_require(modname)
  local req = module_require_name(modname)
  package.loaded[req] = nil
  -- Some MQ Lua setups also cache in package.preload occasionally; safe to clear:
  if package.preload then package.preload[req] = nil end
end

local function list_module_filenames()
  local modules_dir = mq.luaDir .. '\\autobot\\modules'
  local files = {}

  local attr = lfs.attributes(modules_dir)
  if not attr or attr.mode ~= 'directory' then
    log.log(('Reload ERROR: modules folder not found: %s'):format(modules_dir))
    return files, modules_dir
  end

  for file in lfs.dir(modules_dir) do
    if file ~= '.' and file ~= '..' then
      local modname = file:match('^(.-)%.lua$')
      if modname and modname ~= 'init' and not modname:match('^_') then
        table.insert(files, modname)
      end
    end
  end

  table.sort(files)
  return files, modules_dir
end

local function cmd_reload()
  -- If a module is currently running, safest is to stop it before reloading
  -- (prevents calling tick/stop on stale function closures).
  if active then
    stop_active('reload')
  end

  local modnames, modules_dir = list_module_filenames()
  if #modnames == 0 then
    log.log(('Reload: no module files found in %s'):format(tostring(modules_dir)))
    return
  end

  -- Unload requires for all module files so require() re-executes
  for _, modname in ipairs(modnames) do
    unload_module_require(modname)
  end

  -- Reload them
  local new_modules = {}
  local loaded = 0

  for _, modname in ipairs(modnames) do
    local req = module_require_name(modname)
    local ok, modOrErr = pcall(require, req)
    if not ok then
      log.log(('Reload ERROR: require failed for "%s": %s'):format(req, tostring(modOrErr)))
    elseif type(modOrErr) ~= 'table' then
      log.log(('Reload ERROR: module "%s" did not return a table (got %s)'):format(req, type(modOrErr)))
    elseif not modOrErr.id then
      log.log(('Reload ERROR: module "%s" missing id'):format(req))
    else
      new_modules[modOrErr.id] = modOrErr
      loaded = loaded + 1
      log.dbg(('Reload: loaded module id=%s (file=%s.lua)'):format(modOrErr.id, modname))
    end
  end

  modules = new_modules
  rebuild_triggers()
  register_chat_triggers()
  log.log(('Reload complete. Modules loaded: %d'):format(loaded))
end

local function autoload_modules(add)
  local baseLua = mq.TLO.MacroQuest.Path('lua')()
  local modules_dir = mq.luaDir .. '\\autobot\\modules'   -- NOTE: AutoBot (case)
  local require_prefix = 'AutoBot.modules.'            -- NOTE: AutoBot (case)

  log.dbg(('Autoload: modules_dir="%s" require_prefix="%s"'):format(modules_dir, require_prefix))

  -- Helper: iterate module filenames (*.lua) either with lfs or dir /b fallback
  local function iter_module_files()
    local files = {}

    if lfs and lfs.attributes then
      local attr = lfs.attributes(modules_dir)
      if not attr or attr.mode ~= 'directory' then
        log.log(('Autoload ERROR: modules folder not found: %s'):format(modules_dir))
        return files
      end

      for file in lfs.dir(modules_dir) do
        if file ~= '.' and file ~= '..' then
          table.insert(files, file)
        end
      end
    end
    return files
  end

  local loaded = 0
  local files = iter_module_files()

  if #files == 0 then
    log.log('Autoload: no module files found (or modules folder not readable).')
    return 0
  end

  for _, file in ipairs(files) do
    local modname = file:match('^(.-)%.lua$')
    if modname and modname ~= 'init' and not modname:match('^_') then
      local req = require_prefix .. modname
      log.dbg(('Autoload: requiring "%s"'):format(req))

      local ok, modOrErr = pcall(require, req)
      if not ok then
        log.log(('Autoload ERROR: require failed for "%s": %s'):format(req, tostring(modOrErr)))
      elseif type(modOrErr) ~= 'table' then
        log.log(('Autoload ERROR: module "%s" did not return a table (got %s)'):format(req, type(modOrErr)))
      else
        local okAdd, addErr = pcall(add, modOrErr)
        if not okAdd then
          log.log(('Autoload ERROR: add() failed for "%s": %s'):format(req, tostring(addErr)))
        else
          loaded = loaded + 1
        end
      end
    end
  end

  log.dbg(('Autoload: loaded=%d'):format(loaded))
  return loaded
end

local function load_modules()
  modules = {}

  local function add(m)
    if not m or not m.id then
      log.log('Skipping invalid module (missing id)')
      return
    end
    modules[m.id] = m
    log.dbg('Loaded module: ' .. m.id)
  end

  -- call it once during init
  autoload_modules(add)

  local count = 0
  for _ in pairs(modules) do count = count + 1 end
  log.log('Modules loaded: ' .. tostring(count))
end

-- =========================
-- TRIGGERS (optional starter)
-- =========================
local trigger_list = {}

rebuild_triggers = function()
  trigger_list = {}
  for id, m in pairs(modules) do
    if m.triggers then
      for _, t in ipairs(m.triggers) do
        table.insert(trigger_list, {
          type = t.type,
          pattern = t.pattern,
          name = t.name,
          start = t.start or id,
          reason = t.reason,
        })
      end
    end
  end
  log.dbg('Trigger count: ' .. tostring(#trigger_list))
end

register_chat_triggers = function()
  mq.unevent('AutoBotChatTrigger')
  mq.event('AutoBotChatTrigger', '#*#', function(line)
    if not line or line == '' then return end
    for _, t in ipairs(trigger_list) do
      if t.type == 'chat' and t.pattern and line:find(t.pattern, 1, true) then
        log.dbg('Chat trigger matched: ' .. t.pattern)
        start_module(t.start, t.reason or ('trigger: ' .. t.pattern))
        break
      end
    end
  end)
end

local last_zone = nil
local function poll_zone_triggers()
  local z = mq.TLO.Zone.Name()
  if not z or z == last_zone then return end
  last_zone = z

  for _, t in ipairs(trigger_list) do
    if t.type == 'zone' and t.name and z == t.name then
      log.dbg('Zone trigger matched: ' .. tostring(t.name))
      start_module(t.start, t.reason or ('zone: ' .. tostring(z)))
      break
    end
  end
end

-- =========================
-- COMMANDS
-- =========================
local function show_help()
  log.log('Commands:')
  log.log('  /autobot help')
  log.log('  /autobot status')
  log.log('  /autobot list')
  log.log('  /autobot start <moduleId>')
  log.log('  /autobot stop')
  log.log('  /autobot quit   (stop + exit AutoBot)')
  log.log('  /autobot debug on|off')
  log.log('  /autobot reload (reload all modules)')
end

local function cmd_status()
  if active then
    log.log(string.format('Active: %s', tostring(active_id)))
  else
    log.log(string.format('Active: none (%s)', tostring(active_reason or 'idle')))
  end
end

local function cmd_list()
  log.log('Loaded modules:')
  local any = false
  for id in pairs(modules) do
    any = true
    log.log('  - ' .. id)
  end
  if not any then
    log.log('  (none)')
  end
end

local function cmd_debug(arg)
  if arg == 'on' then debug = true end
  if arg == 'off' then debug = false end
  log.log('Debug=' .. tostring(debug))
end

-- IMPORTANT FIX:
-- mq.bind passes varargs tokens, not necessarily a raw line.
-- So we parse ( ... ) tokens directly, and also support the old "line" style.
local function autobot_cmd(...)
  local args = { ... }

  -- Some MQ builds pass a single string line. Support both.
  if #args == 1 and type(args[1]) == 'string' and args[1]:find('%s') then
    local line = args[1]
    args = {}
    for w in line:gmatch('%S+') do table.insert(args, w) end
    -- If the first token is "/autobot", drop it.
    if args[1] and args[1]:lower() == '/autobot' then
      table.remove(args, 1)
    end
  end

  local sub = (args[1] or 'help'):lower()

  if sub == '' or sub == 'help' then
    show_help()
    return
  end

  if sub == 'status' then return cmd_status() end
  if sub == 'list' then return cmd_list() end
  if sub == 'stop' then
    stop_active('stop command')
    return
  end
  if sub == 'quit' then
    stop_active('quit command')
    running = false
    return
  end
  if sub == 'debug' then
    return cmd_debug((args[2] or ''):lower())
  end
  if sub == 'start' then
    local id = args[2]
    if not id or id == '' then
      log.log('Usage: /autobot start <moduleId>')
      return
    end
    return start_module(id, 'manual start')
  end
    if sub == 'reload' then
    return cmd_reload()
  end

  -- =========================
  -- MODULE COMMAND ROUTING
  -- /autobot <moduleId> <command> [args...]
  -- =========================
  local mod = modules[sub]
  if mod then
    local cmd = (args[2] or ''):lower()
    if cmd == '' then
      log.log(string.format('Module "%s" requires a command.', sub))
      if mod.help then
        for _, line in ipairs(mod.help) do log.log('  ' .. line) end
      end
      return
    end

    -- Prefer commands table
    if mod.commands and mod.commands[cmd] then
      local ok, err = pcall(function()
        mod.commands[cmd](ctx, { select(3, tunpack(args)) })
      end)
      if not ok then
        log.log(string.format('ERROR in module "%s" command "%s": %s', sub, cmd, tostring(err)))
      end
      return
    end

    -- Optional fallback: handle_command(ctx, cmd, args)
    if mod.handle_command then
      local ok, err = pcall(function()
        mod.handle_command(ctx, cmd, { select(3, table.unpack(args)) })
      end)
      if not ok then
        log.log(string.format('ERROR in module "%s" handle_command("%s"): %s', sub, cmd, tostring(err)))
      end
      return
    end

    log.log(string.format('Unknown command "%s" for module "%s".', cmd, sub))
    if mod.help then
      for _, line in ipairs(mod.help) do log.log('  ' .. line) end
    end
    return
  end

  log.log('Unknown subcommand. Try: /autobot help')
end

-- Register slash command
mq.bind('/autobot', autobot_cmd)

-- =========================
-- MAIN
-- =========================
log.log('Starting AutoBot...')
load_modules()
rebuild_triggers()
register_chat_triggers()
log.log('Ready. Use /autobot help')

while running do
  mq.delay(50)

  -- optional: zone trigger polling
  poll_zone_triggers()

  if active and active.tick then
    local ok, err = pcall(function() active.tick(ctx) end)
    if not ok then
      log.log(string.format('ERROR in module "%s" tick: %s', tostring(active_id), tostring(err)))
      stop_active('module error')
    end
  end
end

-- cleanup on exit
stop_active('autobot exit')
log.log('Exited AutoBot.')