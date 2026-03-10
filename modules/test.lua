local mq = require('mq')

local M = {}

M.id = 'test'
M.help = {
  'Test module',
  '  /autobot test helloworld',
  '  /autobot test xtargetdump',
}

M.commands = {}

M.commands.helloworld = function(ctx, args)
  ctx.log('[test] hello world')
end

M.commands.xtargetdump = function(ctx, args)
  local cnt = mq.TLO.Me.XTarget()
  cnt = (type(cnt) == 'function') and cnt() or (cnt or 0)

  ctx.log(('[test] XTarget count = %s'):format(tostring(cnt)))

  for i = 1, cnt do
    local xt = mq.TLO.Me.XTarget(i)

    if not xt or not xt() then
      ctx.log(('[test] XTarget[%d] = nil/invalid'):format(i))
    else
      local id = xt.ID and xt.ID() or nil
      local name = xt.Name and xt.Name() or nil
      local targetType = xt.TargetType and xt.TargetType() or nil

      ctx.log(('[test] XTarget[%d] raw: id=%s name=%s type=%s')
        :format(i, tostring(id), tostring(name), tostring(targetType)))

      if id and id > 0 then
        local s = mq.TLO.Spawn(('id %d'):format(id))
        if s and s() then
          local sName = s.Name and s.Name() or nil
          local dist = s.Distance and s.Distance() or nil
          local clean = s.CleanName and s.CleanName() or nil

          ctx.log(('[test] XTarget[%d] spawn: id=%d name=%s clean=%s dist=%s')
            :format(i, id, tostring(sName), tostring(clean), tostring(dist)))
        else
          ctx.log(('[test] XTarget[%d] spawn lookup failed for id=%d')
            :format(i, id))
        end
      end
    end
  end
end

return M