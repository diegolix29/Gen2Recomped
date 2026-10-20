-- Detach unseen terrain immediately; release its GPU buffers between frames.
-- Deleting a neighbourhood's buffers during setLive used to sit on the seam.
local V = ...
local Budget = V.require("BuildBudget")
local Q = {}
function Q.new()
  local queue, head, co = {}, 1, nil
  local q = {}
  function q:add(value, release)
    queue[#queue+1] = {value=value, release=release}
  end
  function q:pending() return co ~= nil or queue[head] ~= nil end
  function q:pump(seconds)
    if not co then
      if not queue[head] then return end
      co = coroutine.create(function()
        while queue[head] do
          local item = queue[head]
          item.release(item.value)
          -- Do not create holes: appends while suspended must stay after head.
          queue[head] = false
          head = head + 1
          Budget.check()
        end
      end)
    end
    Budget.begin(co, seconds, {})
    local ok, err = coroutine.resume(co)
    Budget.finish()
    assert(ok, err)
    if coroutine.status(co) == "dead" then queue, head, co = {}, 1, nil end
  end
  function q:finish()
    while self:pending() do self:pump(math.huge) end
  end
  return q
end
return Q
