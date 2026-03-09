-- AutoBot/lib/spells.lua
local mq = require('mq')

local M = {}

function M.spell_ready(spellName)
  local ok, res = pcall(function()
    local t = mq.TLO.Me.SpellReady(spellName)
    return t and t() == true
  end)
  if ok then return res end

  -- fallback: if a gem exists by that name, assume potentially usable
  local g = mq.TLO.Me.Gem(spellName)
  if g and g() then return true end
  return true
end

function M.ability_ready(abilityName)
  local ok, res = pcall(function()
    local t = mq.TLO.Me.AbilityReady(abilityName)
    return t and t() == true
  end)
  if ok then return res end
  return true
end

function M.wait_spell_ready(spellName, timeoutMs)
  timeoutMs = timeoutMs or 8000
  local start = mq.gettime()
  while mq.gettime() - start < timeoutMs do
    if M.spell_ready(spellName) and not mq.TLO.Me.Casting() then
      return true
    end
    mq.delay(50)
  end
  return false
end

function M.cast_spell(spellName, maxWaitMs)
  maxWaitMs = maxWaitMs or 12000

  -- don't issue /cast while already casting
  mq.delay(8000, function() return not mq.TLO.Me.Casting() end)

  if not M.wait_spell_ready(spellName, 8000) then
    return false, "spell not ready"
  end

  local startTime = mq.gettime()
  mq.cmdf('/cast "%s"', spellName)
  mq.delay(50)

  -- confirm cast begins
  local beganBy = mq.gettime() + 2000
  while mq.gettime() < beganBy do
    if mq.TLO.Me.Casting() then break end
    mq.delay(25)
  end
  if not mq.TLO.Me.Casting() then
    return false, "cast did not start"
  end

  -- wait for cast to finish
  while mq.TLO.Me.Casting() and (mq.gettime() - startTime) < maxWaitMs do
    mq.delay(50)
  end
  if mq.TLO.Me.Casting() then
    return false, "cast timed out"
  end

  mq.delay(250) -- settle buffer
  return true
end

-- ===== Spellbook / mem helpers =====

function M.has_spell_in_book(spellName)
  local b = mq.TLO.Me.Book(spellName)
  local v = b and b() or nil
  return v ~= nil and v ~= false and v ~= 0
end

function M.current_gem_spell_name(gem)
  local g = mq.TLO.Me.Gem(gem)
  if not g() then return nil end
  local n = g.Name()
  return (n and n ~= '' and n) or nil
end

function M.is_memmed_in_slot(spellName, gem)
  return M.current_gem_spell_name(gem) == spellName
end

function M.memorize_spell_to_gem(spellName, gem, on_timeout_cb)
  mq.delay(5000, function() return not mq.TLO.Me.Casting() end)
  mq.delay(250)
  mq.cmdf('/memspell %d "%s"', gem, spellName)

  local start = mq.gettime()
  while mq.gettime() - start < 30000 do
    if M.current_gem_spell_name(gem) == spellName then
      return true
    end
    mq.delay(200)
  end

  if on_timeout_cb then
    on_timeout_cb(spellName, gem, M.current_gem_spell_name(gem))
  end
  return false
end

return M