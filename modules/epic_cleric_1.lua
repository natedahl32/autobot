-- AutoBot/modules/epic_cleric_1.lua
local mq = require('mq')

local Items  = require('AutoBot.lib.items')
local Config = require('AutoBot.lib.config')

-- Steps
local Step1A = require('AutoBot.modules.EpicSteps.CLR1_1A')

local M = {}

M.id = 'epic_cleric_1'
M.help = {
  'Cleric Epic 1.0 (Water Sprinkler of Nem`Ankh) - Step tracker',
  '',
  'Commands:',
  '  /autobot epic_cleric_1 start     (start or continue)',
  '  /autobot epic_cleric_1 pause',
  '  /autobot epic_cleric_1 resume',
  '  /autobot epic_cleric_1 status',
  '  /autobot epic_cleric_1 reset     (clears saved progress)',
}

-- =========================
-- Runner knobs
-- =========================
local CHECK_THROTTLE_MS = 300

-- =========================
-- STATE (runtime + persisted)
-- =========================
local running = false
local paused = false
local paused_reason = nil

-- persisted
local state = {
  step = '1A',
  done = {},   -- done['1A']=true
}

-- runtime
local last_check_ms = 0
local active_step_id = nil

-- =========================
-- Step registry
-- =========================
local STEPS = {
  ['1A'] = Step1A,
}

-- =========================
-- Persistence
-- =========================
local function load_state()
  local t = Config.load(M.id) or {}
  state.step = t.step or '1A'
  state.done = t.done or {}
end

local function save_state()
  Config.save(M.id, {
    step = state.step,
    done = state.done,
  })
end

-- =========================
-- Announce helpers
-- =========================
local function tag()
  return string.format('[ClericEpic:%s]', mq.TLO.Me.Name() or 'Me')
end

local function say(ctx, msg)
  ctx.log(('%s %s'):format(tag(), msg))
  print(string.format('%s %s', tag(), msg))
end

local function hard_pause(ctx, reason)
  paused = true
  paused_reason = reason or 'paused'
  say(ctx, ('PAUSED: %s. Use "/autobot %s resume" to continue.'):format(paused_reason, M.id))
end

-- Build a step-context wrapper the step files can use.
local function make_step_ctx(ctx)
  return {
    mq = mq,
    log = ctx.log,
    dbg = ctx.dbg,

    say = function(msg) say(ctx, msg) end,
    hard_pause = function(reason) hard_pause(ctx, reason) end,
    save = function() save_state() end,
  }
end

local function get_step()
  return STEPS[state.step]
end

local function enter_step(ctx, stepObj)
  if not stepObj then return end
  active_step_id = stepObj.id
  if stepObj.on_enter then
    local ok, err = pcall(stepObj.on_enter, make_step_ctx(ctx), state)
    if not ok then
      say(ctx, ('ERROR in step %s on_enter: %s'):format(tostring(stepObj.id), tostring(err)))
      hard_pause(ctx, 'step on_enter error')
    end
  end
end

local function advance_step(ctx, nextStepId)
  if not nextStepId or nextStepId == '' then
    say(ctx, ('Step %s complete, but next step not implemented yet.'):format(tostring(state.step)))
    hard_pause(ctx, 'waiting for next-step implementation')
    return
  end

  state.step = nextStepId
  save_state()

  local nxt = STEPS[state.step]
  if not nxt then
    say(ctx, ('Next step "%s" not found/registered.'):format(tostring(state.step)))
    hard_pause(ctx, 'missing step implementation')
    return
  end

  say(ctx, ('Advancing to step %s...'):format(tostring(state.step)))
  enter_step(ctx, nxt)
end

-- =========================
-- Module lifecycle
-- =========================
function M.can_start(ctx)
  return true
end

function M.start(ctx, reason)
  load_state()
  running = true
  paused = false
  paused_reason = nil
  last_check_ms = 0

  say(ctx, ('Started (%s). Current step=%s'):format(tostring(reason or 'start'), tostring(state.step)))

  local st = get_step()
  if not st then
    say(ctx, ('Current step "%s" not found/registered.'):format(tostring(state.step)))
    hard_pause(ctx, 'missing step implementation')
    return
  end

  -- call on_enter when starting or if step changed since last tick
  enter_step(ctx, st)
end

function M.stop(ctx, reason)
  running = false
  paused = false
  paused_reason = nil
  mq.cmd('/attack off')
  say(ctx, ('Stopped (%s).'):format(tostring(reason or 'stop')))
end

function M.tick(ctx)
  if not running then return end

  -- Hard pause on death until explicit resume
  if mq.TLO.Me.Dead() then
    if not paused then
      hard_pause(ctx, 'YOU DIED')
    end
    return
  end

  if paused then return end

  -- throttle
  local now = mq.gettime()
  if now - last_check_ms < CHECK_THROTTLE_MS then return end
  last_check_ms = now

  local stepObj = get_step()
  if not stepObj then
    hard_pause(ctx, 'unknown/unregistered step: ' .. tostring(state.step))
    return
  end

  -- If step changed externally (config edit / reload), re-enter it.
  if active_step_id ~= stepObj.id then
    enter_step(ctx, stepObj)
  end

  local ok, doneOrErr, nextOrNil = pcall(stepObj.tick, make_step_ctx(ctx), state)
  if not ok then
    say(ctx, ('ERROR in step %s tick: %s'):format(tostring(stepObj.id), tostring(doneOrErr)))
    hard_pause(ctx, 'step tick error')
    return
  end

  local done = (doneOrErr == true)
  local nextStep = nextOrNil

  if done then
    advance_step(ctx, nextStep)
  end
end

-- =========================
-- Commands
-- =========================
M.commands = {}

M.commands.start = function(ctx, args)
  if M.can_start(ctx) then M.start(ctx, 'manual start') end
end

M.commands.pause = function(ctx, args)
  if running and not paused then
    hard_pause(ctx, 'manual pause')
  end
end

M.commands.resume = function(ctx, args)
  if not running then
    M.start(ctx, 'resume (auto-start)')
    return
  end
  paused = false
  paused_reason = nil
  say(ctx, 'Resumed.')
end

M.commands.status = function(ctx, args)
  ctx.log(('%s running=%s paused=%s reason=%s step=%s done_1A=%s'):format(
    tag(),
    tostring(running),
    tostring(paused),
    tostring(paused_reason or ''),
    tostring(state.step),
    tostring(state.done and state.done['1A'] == true)
  ))
end

M.commands.reset = function(ctx, args)
  running = false
  paused = false
  paused_reason = nil
  state.step = '1A'
  state.done = {}
  save_state()
  ctx.log(('%s Progress reset.'):format(tag()))
end

return M