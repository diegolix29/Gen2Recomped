do
  local root = (os.getenv("ROOT") or love.filesystem.getWorkingDirectory()):gsub("\\", "/")
  local ffi = require("ffi")
  pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
    local ok, l = pcall(lib)
    if ok and l then
      local okf, fn = pcall(function() return l.PHYSFS_mount end)
      if okf and fn and fn(root, "", 1) ~= 0 then break end
    end
  end
end

local Task,job,frames,maxPoll= nil,nil,0,0
function love.load()
 if os.getenv('CLOUD_CHECK_CONFIG') then
  local clients=require('src.cloud.CloudClients')
  assert(clients.googleDevice(),'Google device client missing from package')
  assert(clients.microsoft(),'Microsoft client missing from package')
  print('Packaged cloud client configuration: present')
 end
 Task=require('src.cloud.Task')
 job=assert(Task.new(function()
  local status,body=require('src.cloud.Http').request('GET',assert(os.getenv('CLOUD_TEST_URL')))
  assert(status==200 and body=='worker-ok','HTTP worker response mismatch: '..tostring(status)..' '..tostring(body))
  return 'done'
 end))
end
function love.update()
 frames=frames+1
 local before=love.timer.getTime()
 local result=job:poll()
 maxPoll=math.max(maxPoll,love.timer.getTime()-before)
 if result then
  assert(result.kind=='done',result.error)
  assert(result.first=='done')
  assert(frames>10,'did not keep updating while waiting for HTTP')
  assert(maxPoll<0.1,'HTTP stalled the render thread')
  print(('Cloud real-worker check passed: %d frames; longest poll %.4fs'):format(frames,maxPoll))
  love.event.quit()
 end
end
